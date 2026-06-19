#' Extract a spectra matrix from a hyperspectral raster
#'
#' @family HSI Unmixing
#'
#' @param x A [`SpatRaster`][terra::SpatRaster-class] with hyperspectral data.
#' @param n Positive number. Pixels to randomly sample, or `Inf` to take every
#'   valid pixel. Default `NULL`.
#' @param cells Numeric vector of [`terra`][terra::terra-package] cell numbers
#'   to fetch, in the returned row order. Default `NULL`.
#'
#' @returns A numeric matrix of pixels (rows) by bands (columns), with cell
#'   numbers as row names and band names as column names.
#'
#' @details
#' Exactly one of `n` or `cells` must be supplied; they are mutually exclusive.
#' A bare call with neither errors on purpose, so that materialising every pixel
#' of a large raster is always a deliberate choice (`n = Inf`) rather than a
#' silent default.
#'
#' The three modes map to the cheapest read for the job:
#' * `n` (finite) samples random pixels via [`terra::spatSample()`] without
#'   reading the whole raster.
#' * `n = Inf` reads every pixel via [`terra::values()`] — the deliberate
#'   full-materialisation path.
#' * `cells` reads only the requested cells.
#'
#' Cell numbers are a stable address: across co-registered rasters of the same
#' geometry (e.g. reflectance, Savitzky-Golay, continuum-removed), the same cell
#' number refers to the same physical pixel. Passing `cells = em$locations` from
#' [`hsi_calc_endmembers()`] therefore re-fetches the spectra of the chosen
#' endmember pixels in whatever processing space `x` represents. Ensuring `x` is
#' co-registered with the raster the cells came from is the caller's
#' responsibility; only the cell-number range is checked.
#'
#' Background pixels (fully `NA` rows) are dropped. In `cells` mode any requested
#' cell that is background is dropped with a warning, since that breaks the
#' one-to-one mapping the caller may expect.
#'
#' @seealso
#' [`hsi_calc_endmembers()`] which produces the `locations` to pass as `cells`.
#' [`hsi_plot_endmembers()`] and [`hsi_calc_sam()`] for what the matrix feeds.
#'
#' @examples
#' \dontrun{
#' x <- terra::rast("REFLECTANCE_testdata.tif")
#'
#' # Random sample for endmember search
#' x_spectra <- hsi_extract_spectra(x, n = 5000)
#'
#' # Every valid pixel (small rasters only)
#' x_spectra <- hsi_extract_spectra(x, n = Inf)
#'
#' # Re-fetch the endmember pixels in another co-registered space
#' red <- stats::prcomp(x_spectra, center = TRUE, scale. = FALSE)
#' em <- hsi_calc_endmembers(x_spectra, reduction = red, n_endmembers = 6)
#'
#' x_conrem <- terra::rast("CONREM_testdata.tif")
#' x_spectra_conrem <- hsi_extract_spectra(x_conrem, cells = em$locations)
#' }
#'
#' @export
hsi_extract_spectra <- function(
  x,
  n = NULL,
  cells = NULL
) {
  # Validate inputs
  if (!inherits(x, "SpatRaster")) {
    cli::cli_abort(
      "{.arg x} must be a {.cls SpatRaster}, not {.cls {class(x)}}."
    )
  }

  # Resolve selection mode: exactly one of n / cells
  if (is.null(n) && is.null(cells)) {
    cli::cli_abort(
      c(
        "Choose which pixels to extract.",
        "i" = "{.arg n}: randomly sample that many pixels, e.g. {.code n = 5000}.",
        "i" = "{.code n = Inf}: take every valid pixel (reads the whole raster).",
        "i" = "{.arg cells}: fetch specific cells, e.g. {.code cells = em$locations}."
      )
    )
  }

  if (!is.null(n) && !is.null(cells)) {
    cli::cli_abort(
      c(
        "{.arg n} and {.arg cells} are mutually exclusive.",
        "i" = "Sample with {.arg n} or fetch known pixels with {.arg cells}, not both."
      )
    )
  }

  if (!is.null(n)) {
    if (!is.numeric(n) || length(n) != 1L || is.na(n) || n <= 0) {
      cli::cli_abort(
        "{.arg n} must be a single positive number, or {.code Inf} for all pixels."
      )
    }
  }

  if (!is.null(cells)) {
    if (!is.numeric(cells) || length(cells) == 0L || anyNA(cells)) {
      cli::cli_abort(
        "{.arg cells} must be a non-empty numeric vector of cell numbers."
      )
    }

    cells <- as.integer(cells)

    if (anyDuplicated(cells)) {
      cli::cli_warn(
        "Duplicate {.arg cells} dropped; keeping the first occurrence of each."
      )
      cells <- cells[!duplicated(cells)]
    }

    out_of_range <- cells[cells < 1L | cells > terra::ncell(x)]

    if (length(out_of_range) > 0L) {
      cli::cli_abort(
        c(
          "{.arg cells} contains values outside {.arg x}.",
          "i" = "{.arg x} has {terra::ncell(x)} cells; out of range: {.val {out_of_range}}."
        )
      )
    }
  }

  # Extract the requested pixels as a matrix with cell numbers as row names
  if (!is.null(cells)) {
    # Cells mode: read only the requested cells, in the caller's order
    spectra <- x[cells] |>
      as.matrix()

    rownames(spectra) <- cells
  } else if (is.finite(n)) {
    # Sample mode: random pixels, read without materialising the whole raster
    sampled <- terra::spatSample(
      x,
      size = as.integer(n),
      method = "random",
      na.rm = TRUE,
      cells = TRUE,
      values = TRUE
    )

    band_cols <- setdiff(names(sampled), "cell")

    spectra <- sampled[, band_cols, drop = FALSE] |>
      as.matrix()

    rownames(spectra) <- sampled[["cell"]]
  } else {
    # All mode: every pixel (n = Inf) — deliberate full materialisation
    spectra <- terra::values(x, mat = TRUE)

    rownames(spectra) <- seq_len(nrow(spectra))
  }

  # Carry exact band-name strings as column names
  colnames(spectra) <- terra::names(x)

  # Drop background (fully-NA) pixels
  background <- rowSums(is.na(spectra)) == ncol(spectra)

  if (!is.null(cells) && any(background)) {
    cli::cli_warn(
      c(
        "Some requested {.arg cells} are empty (background) and were dropped.",
        "i" = "Dropped cells: {.val {rownames(spectra)[background]}}."
      )
    )
  }

  spectra <- spectra[!background, , drop = FALSE]

  # Return result
  spectra
}
