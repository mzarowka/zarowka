#' Extract a pixel-by-band table from a hyperspectral raster
#'
#' @family HSI Extraction
#'
#' @param x     A [`SpatRaster`][terra::SpatRaster-class] with hyperspectral data.
#' @param roi   A [`SpatVector`][terra::SpatVector-class] of polygons to extract
#'   pixels from, or `NULL` for the whole scene. Default `NULL`.
#' @param n     Positive integer. Number of pixels to randomly sample, or `NULL`
#'   to take every pixel. Default `NULL`.
#' @param scene Character. Scene identifier stamped into the `scene` column.
#'   Default `NA`.
#'
#' @returns A [tibble][tibble::tibble] with one row per extracted pixel:
#'   \item{scene}{Character. The `scene` identifier.}
#'   \item{roi}{Integer. Source polygon index, or `NA` outside ROI extraction.}
#'   \item{cell}{Integer. Source cell number in `x`.}
#'   \item{...}{One column per band, named by wavelength.}
#'
#' @details
#' The `roi` and `n` arguments compose into four modes. With `roi` only, every
#' pixel inside the polygons is returned, carrying the polygon index as `roi`.
#' With `n` only, `n` cells are sampled across the whole scene and `roi` is `NA`.
#' With both, `n` pixels are sampled from within the ROIs. With neither, every
#' pixel in `x` is returned and the pixel count is reported — convenient for
#' small scenes, but a whole-scene pull on large rasters, so an explicit `n`
#' is preferred there.
#'
#' Sampling uses the ambient random state; call [`set.seed()`] beforehand for
#' reproducible extraction. Pixels that are entirely `NA` (no data) are dropped;
#' pixels with some `NA` bands are kept, since trimming bad or edge bands is the
#' caller's responsibility — pass an already-trimmed `x`.
#'
#' @examples
#' \dontrun{
#' x <- terra::rast("REFLECTANCE_testdata.tif")
#' rois <- terra::vect("rois.gpkg")
#'
#' # All pixels inside the ROIs.
#' fit <- hsi_extract_spectra(x, roi = rois, scene = "scene_a")
#'
#' # Random sample across the whole scene.
#' fit <- hsi_extract_spectra(x, n = 5000, scene = "scene_a")
#' }
#'
#' @export
hsi_extract_spectra <- function(x, roi = NULL, n = NULL, scene = NA) {
  # Validate inputs
  HSItools:::check_spatraster(x)

  if (!is.null(roi)) {
    HSItools:::check_spatvector(roi)
  }

  if (!is.null(n) && (n < 1 || n > terra::ncell(x))) {
    cli::cli_abort(c(
      "{.arg n} must be between 1 and the number of cells.",
      "i" = "Got {n} with {terra::ncell(x)} cell{?s}."
    ))
  }

  # Extract pixels with their source cell numbers
  pixels <- if (is.null(roi)) {
    extract_scene(x, n)
  } else {
    extract_roi(x, roi, n)
  }

  band_cols <- setdiff(names(pixels), c("roi", "cell"))

  # Drop no-data (entirely NA) pixels only. A pixel with some NA bands is real
  # data; trimming bad bands is the caller's responsibility, like edge trimming.
  pixels |>
    dplyr::filter(!dplyr::if_all(dplyr::all_of(band_cols), is.na)) |>
    dplyr::mutate(scene = scene, .before = 1) |>
    dplyr::relocate(dplyr::any_of(c("scene", "roi", "cell")))
}

#' Extract whole-scene pixels, optionally sampled
#'
#' @param x A [`SpatRaster`][terra::SpatRaster-class].
#' @param n Positive integer sample size, or `NULL` for all cells.
#'
#' @returns A [tibble][tibble::tibble] with `roi`, `cell`, and band columns.
#'
#' @noRd
extract_scene <- function(x, n) {
  cells <- if (is.null(n)) {
    cli::cli_inform(
      "Extracting all {terra::ncell(x)} pixel{?s} from the scene."
    )
    seq_len(terra::ncell(x))
  } else {
    sort(sample(terra::ncell(x), n))
  }

  x[cells] |>
    tibble::as_tibble() |>
    tibble::add_column(roi = NA_integer_, cell = cells, .before = 1)
}

#' Extract ROI pixels, optionally sampled
#'
#' @param x   A [`SpatRaster`][terra::SpatRaster-class].
#' @param roi A [`SpatVector`][terra::SpatVector-class] of polygons.
#' @param n   Positive integer sample size, or `NULL` for all ROI pixels.
#'
#' @returns A [tibble][tibble::tibble] with `roi`, `cell`, and band columns.
#'
#' @noRd
extract_roi <- function(x, roi, n) {
  pixels <- terra::extract(x, roi, cells = TRUE, ID = TRUE) |>
    tibble::as_tibble() |>
    dplyr::rename(roi = "ID")

  if (!is.null(n)) {
    pixels <- dplyr::slice_sample(pixels, n = min(n, nrow(pixels)))
  }

  pixels
}
