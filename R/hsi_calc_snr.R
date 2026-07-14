#' Per-band signal-to-noise ratio
#'
#' @family HSI Diagnostics
#'
#' @param x A [`SpatRaster`][terra::SpatRaster-class] with hyperspectral data.
#' @param na.rm Logical. Remove `NA` values. Default `TRUE`.
#'
#' @returns A [tibble][tibble::tibble] with columns:
#'   \item{wavelength}{Numeric. Band wavelength in nm.}
#'   \item{mean}{Numeric. Mean of the band's values.}
#'   \item{sd}{Numeric. Standard deviation of the band's values.}
#'   \item{snr}{Numeric. Signal-to-noise ratio, `mean / sd`.}
#'
#' @description
#' Compute mean, standard deviation and their ratio for every band of a raster,
#' as a diagnostic for identifying bands whose signal-to-noise collapses relative
#' to their neighbours.
#'
#' @details
#' Statistics are computed over the full raster with [terra::global()], so the
#' result is exact rather than sampled. Digital numbers, radiance and reflectance
#' are all accepted — the function makes no assumption about calibration state,
#' sensor or material.
#'
#' Interpretation is the caller's, and depends on the scene:
#'
#' * **On a heterogeneous scene this is *apparent* signal-to-noise.** Per-band
#'   standard deviation is dominated by scene variability rather than by sensor
#'   noise, so absolute values are scene-relative and not comparable across
#'   captures. Relative comparison *between bands of one cube* remains valid —
#'   the scene-variability contribution largely cancels — which is what the
#'   band-dropping use case needs.
#' * **On a homogeneous target this approximates true sensor signal-to-noise**
#'   at that signal level. Running the function on the raw digital numbers of a
#'   white-reference scan is the practical way to get such an estimate, since the
#'   panel is uniform and spatial variance is therefore close to noise.
#' * **Signal-to-noise depends on signal level.** An underexposed capture reports
#'   the ratio achieved at that exposure, which is useful for judging whether the
#'   exposure was adequate but says nothing about the ratio available at a proper
#'   one.
#' * **Saturation inflates the ratio.** Clipped values compress the standard
#'   deviation toward zero, so a saturated band reports a high — in the limit,
#'   infinite — signal-to-noise. Screen a possibly-saturated capture with
#'   [`hsi_check_saturation()`] before trusting these numbers; its per-band counts,
#'   via `terra::global(mask, "sum")`, join this tibble on wavelength.
#'
#' A band with zero variance divides by zero and so yields `Inf` (or `NaN` when
#' its mean is also zero). Those values are reported as computed; a warning names
#' the affected wavelengths, because such a band sorts *above* every real band
#' when ranking by signal-to-noise. A fully saturated band is exactly this case.
#'
#' @seealso [`hsi_check_saturation()`]
#'
#' @examples
#' \dontrun{
#' x <- terra::rast("REFLECTANCE_testdata.tif")
#' x_snr <- hsi_calc_snr(x)
#'
#' # Sensor signal-to-noise from the raw digital numbers of a white reference
#' whiteref <- terra::rast("WHITEREF_testdata.tif")
#' whiteref_snr <- hsi_calc_snr(whiteref)
#' }
#'
#' @export
hsi_calc_snr <- function(
  x,
  na.rm = TRUE
) {
  # Validate inputs
  HSItools:::check_spatraster(x)
  rlang::check_bool(na.rm)
  wavelengths <- HSItools:::check_wavelengths(x)

  # Per-band statistics over the full raster: exact, lazy and file-backed
  stats <- terra::global(x, fun = c("mean", "sd"), na.rm = na.rm)

  snr <- tibble::tibble(
    wavelength = wavelengths,
    mean = stats[["mean"]],
    sd = stats[["sd"]]
  ) |>
    dplyr::mutate(snr = .data$mean / .data$sd)

  # A zero-variance band is typically dead or fully saturated. Its ratio is
  # reported as computed, but it would rank above every real band when sorting
  # by signal-to-noise, so it must not pass unnoticed.
  degenerate <- which(snr$sd == 0)

  if (length(degenerate) > 0) {
    degenerate_wavelengths <- snr$wavelength[degenerate]

    cli::cli_warn(
      c(
        "!" = "{length(degenerate)} band{?s} {?has/have} zero variance; {.field snr} is not finite.",
        "i" = "Wavelength{?s}: {.val {degenerate_wavelengths}}.",
        "i" = "A constant band is typically dead or fully saturated."
      ),
      class = "hsitools_warning"
    )
  }

  # Return result
  snr
}
