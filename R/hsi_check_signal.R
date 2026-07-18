#' Check a raster for pixels below the detection limit
#'
#' @family HSI Diagnostics
#'
#' @param x A [`SpatRaster`][terra::SpatRaster-class] with hyperspectral data.
#' @param darkref A [`SpatRaster`][terra::SpatRaster-class] with the dark
#'   reference. Must have the same bands and wavelengths as `x`. Required.
#' @param k Numeric. Noise multiplier defining the detection limit as
#'   `mean + k * sd` of `darkref` in each band. Default `3`.
#' @param fraction Numeric. Fraction of bands, in `(0, 1]`, that must fall below
#'   the detection limit for a pixel to be flagged when collapsing. Default `0.9`.
#' @param collapse Logical. Reduce the per-band mask to a single layer marking
#'   pixels below the detection limit in at least `fraction` of bands. Default
#'   `FALSE`.
#' @param filename Character. Output filename. Default `""` keeps result in memory.
#' @param overwrite Logical. Overwrite existing file. Default `FALSE`.
#' @param ... Additional arguments passed to [`terra::writeRaster()`].
#'
#' @returns A [`SpatRaster`][terra::SpatRaster-class] of `0`/`1` values marking
#'   pixels below the detection limit. With `collapse = FALSE` it has one layer
#'   per band of `x`, carrying the band names of `x`; with `collapse = TRUE` it
#'   has a single layer named `"no_signal"`.
#'
#' @description
#' Mark every pixel whose signal fails to clear the dark-current detection limit.
#' The mask is the primitive: pixel-level crack and defect masks, per-band
#' dead-band diagnostics and target-space masking are all derived from it by the
#' caller.
#'
#' @details
#' This is the floor counterpart of [`hsi_check_saturation()`]. Saturation flags
#' pixels that hit the sensor's ceiling; this flags pixels that never rose above
#' its floor. Both mean the same thing physically — the sensor recorded no
#' information about the material there — but the threshold differs in kind. The
#' saturation limit is instrument knowledge and is supplied; the detection limit
#' is stochastic and is measured, per band, from `darkref` as
#' `mean + k * sd` over all its pixels.
#'
#' The band axis inverts too. A single clipped band already corrupts that band,
#' so saturation collapses with `any()`. A single low band is normal — that is
#' what an absorption feature looks like — so the floor collapses on a fraction
#' of bands instead.
#'
#' Further caveats:
#'
#' * **Intended for raw digital numbers**, with the matched dark reference from
#'   the same session at the same integration time. The function cannot verify
#'   the processing level of `x` or that `darkref` is matched to it; run on
#'   calibrated data or against a mismatched dark, the floor is meaningless.
#' * **What it detects.** Pixels genuinely below detection: deep cracks, holes,
#'   gaps between sections, off-target background. It does **not** detect shallow
#'   or partially illuminated cracks. Shadow is multiplicative — those pixels keep
#'   a plausible spectral shape at reduced brightness, and no per-pixel spectral
#'   criterion separates them from genuinely dark material. That case belongs to
#'   the caller: a brightness threshold via [`HSItools::hsi_mask()`], optionally
#'   followed by spatial morphology, since cracks are connected elongated features.
#' * **No repair path.** The per-band salvage available for saturation does not
#'   apply here. A below-floor pixel has no valid bands to interpolate from, so
#'   spectral interpolation is undefined and spatial interpolation would fabricate
#'   material. Drop these pixels.
#' * **`NA` propagates rather than defaulting to "has signal".** Any `NA` in a
#'   pixel's spectrum makes that pixel `NA` in the collapsed mask, because an
#'   unknown band cannot help a pixel read as clean. Raw digital numbers seldom
#'   contain `NA` at all; the usual source is a raster that has already been
#'   cropped or masked. `NA` cells in `darkref` are dropped when computing the
#'   per-band statistics, since those summarise the noise rather than judging a
#'   pixel. A band with no valid dark cells left has an undefined detection
#'   limit: the function warns, and that band's mask — and therefore the whole
#'   collapsed mask — is `NA`.
#' * **`k` interpretation.** `mean + 3 * sd` is the conventional detection limit;
#'   raising `k` makes the screen more aggressive.
#'
#' Per-band counts come from `terra::global(mask, "sum")`, and join the output of
#' [`hsi_calc_snr()`] on wavelength — a high below-floor fraction at the edge
#' bands marks the same bands where signal-to-noise collapses, which is useful
#' when choosing a trim range.
#'
#' @seealso [`hsi_check_saturation()`], [`hsi_calc_snr()`],
#'   [`HSItools::hsi_mask()`]
#'
#' @examples
#' \dontrun{
#' x <- terra::rast("CAPTURE_testdata.tif")
#' darkref <- terra::rast("DARKREF_testdata.tif")
#'
#' # Per-band mask at the conventional 3-sigma detection limit
#' x_floor <- hsi_check_signal(x, darkref)
#'
#' # Per-band counts of below-detection pixels
#' terra::global(x_floor, "sum", na.rm = TRUE)
#'
#' # Single-layer mask of pixels below floor in 90% of bands, written to disk
#' x_no_signal <- hsi_check_signal(
#'   x,
#'   darkref,
#'   collapse = TRUE,
#'   filename = "no_signal.tif",
#'   overwrite = TRUE
#' )
#'
#' # Drop those pixels from a reflectance product
#' HSItools::hsi_mask(x_reflectance, x_no_signal, inverse = TRUE)
#' }
#'
#' @export
hsi_check_signal <- function(
  x,
  darkref,
  k = 3,
  fraction = 0.9,
  collapse = FALSE,
  filename = "",
  overwrite = FALSE,
  ...
) {
  # Validate inputs
  HSItools:::check_spatraster(x)

  rlang::check_required(darkref)
  HSItools:::check_spatraster(darkref)

  n_bands_x <- terra::nlyr(x)
  n_bands_darkref <- terra::nlyr(darkref)

  if (n_bands_x != n_bands_darkref) {
    cli::cli_abort(
      c(
        "{.arg darkref} must have the same number of bands as {.arg x}.",
        "x" = "Sample: {n_bands_x} band{?s}",
        "x" = "Dark reference: {n_bands_darkref} band{?s}"
      ),
      class = "hsitools_error"
    )
  }

  if (!identical(names(x), names(darkref))) {
    cli::cli_warn(
      "Band names don't match across inputs. Proceeding band by band.",
      class = "hsitools_warning"
    )
  }

  # Finiteness is checked before sign so that NaN cannot reach a comparison:
  # NaN <= 0 is NA, which would crash an if() instead of aborting cleanly.
  HSItools:::check_numeric(k, len = 1)

  if (!is.finite(k) || k <= 0) {
    cli::cli_abort(
      "{.arg k} must be a positive finite number, not {.val {k}}.",
      class = "hsitools_error"
    )
  }

  HSItools:::check_numeric(fraction, len = 1)

  if (!is.finite(fraction) || fraction <= 0 || fraction > 1) {
    cli::cli_abort(
      "{.arg fraction} must be in the interval (0, 1], not {.val {fraction}}.",
      class = "hsitools_error"
    )
  }

  rlang::check_bool(collapse)

  rlang::check_string(filename)

  rlang::check_bool(overwrite)

  wopt_user <- rlang::list2(...)
  HSItools:::check_dots_write(wopt_user, filename)

  # The detection limit is measured, not assumed: pooled mean and standard
  # deviation of the dark reference in each band. Per-column statistics would be
  # more faithful for a pushbroom sensor, but they are sensor-specific.
  dark_stats <- terra::global(darkref, c("mean", "sd"), na.rm = TRUE)

  # A dark band with no variance degenerates the criterion to the dark mean, so
  # the k-sigma margin vanishes. Report every offender at once rather than once
  # per band.
  degenerate <- which(dark_stats$sd == 0)

  if (length(degenerate) > 0) {
    bands_degenerate <- names(darkref)[degenerate]

    cli::cli_warn(
      c(
        "{.arg darkref} has {length(degenerate)} band{?s} with zero variance.",
        "i" = "The detection limit there is the dark mean: {.val {bands_degenerate}}."
      ),
      class = "hsitools_warning"
    )
  }

  # A dark band with no valid cells (or a single one) has no standard deviation
  # at all: the floor is undefined and the whole band masks to NA — which, with
  # na.rm = FALSE, turns the entire collapsed mask NA. Say so rather than let
  # the user meet a blank mask.
  missing <- which(is.na(dark_stats$sd))

  if (length(missing) > 0) {
    bands_missing <- names(darkref)[missing]

    cli::cli_warn(
      c(
        "{.arg darkref} has {length(missing)} band{?s} with no valid dark data.",
        "i" = "The detection limit is undefined and the mask is NA there: {.val {bands_missing}}."
      ),
      class = "hsitools_warning"
    )
  }

  floor <- dark_stats$mean + k * dark_stats$sd

  # A value sitting exactly on the detection limit has not demonstrably cleared
  # it, so the comparison is inclusive, mirroring the saturation twin. terra
  # recycles the floor by layer. The comparison is lazy, and NA propagates.
  result <- x <= floor

  # Collapsing keeps na.rm = FALSE so that an unknown band cannot silently clear
  # a pixel: any NA in a pixel's spectrum yields NA here. The per-pixel mean of
  # the 0/1 stack is the fraction of bands below floor.
  if (collapse) {
    result <- terra::mean(result, na.rm = FALSE) >= fraction
    names(result) <- "no_signal"
  }

  # Build write options
  wopt_default <- list(names = names(result))
  wopt <- purrr::list_modify(wopt_default, !!!wopt_user)

  # Write to file
  if (filename != "") {
    result <- terra::writeRaster(
      result,
      filename = filename,
      overwrite = overwrite,
      wopt = wopt
    )
  }

  # Return result
  result
}
