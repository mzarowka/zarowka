#' Unmix a hyperspectral raster into per-endmember abundances
#'
#' @family HSI Unmixing
#'
#' @param x A [`SpatRaster`][terra::SpatRaster-class] with hyperspectral data.
#' @param endmembers Numeric matrix of endmember spectra, bands in rows and
#'   endmembers in columns, as returned in the `spectra` component of
#'   [`hsi_calc_endmembers()`]. Must have one row per layer of `x`. Column names,
#'   when present, become the output layer names.
#' @param cores Positive integer. Number of parallel cores. Default `1`.
#' @param filename Character. Output filename. Default `""` keeps result in memory.
#' @param overwrite Logical. Overwrite existing file. Default `FALSE`.
#' @param ... Additional arguments passed to [`terra::writeRaster()`].
#'
#' @returns A [`SpatRaster`][terra::SpatRaster-class] with one abundance layer
#'   per endmember, sharing the geometry of `x`.
#'
#' @details
#' Each pixel spectrum is decomposed as a non-negative linear combination of the
#' supplied endmember spectra by non-negative least squares (Lawson & Hanson
#' 1974, via the \pkg{nnls} package), producing one output layer per endmember
#' on the same grid as `x`. Abundances are constrained to be non-negative
#' without being forced to sum to one, which suits scenes with albedo and shade
#' variation. Wavelength correspondence between `x` and `endmembers` is the
#' caller's responsibility: the function checks band count, not band alignment.
#' Fully `NA` (background) pixels return `NA` abundances.
#'
#' @references
#' Lawson, C. L. & Hanson, R. J. (1974). *Solving Least Squares Problems*.
#' Prentice-Hall (reprinted as SIAM Classics in Applied Mathematics, 1995).
#'
#' @examples
#' \dontrun{
#' spectra <- hsi_extract_spectra(x, n = 5000)
#' red <- stats::prcomp(spectra, center = TRUE, scale. = FALSE)
#' em <- hsi_calc_endmembers(spectra, reduction = red, n_endmembers = 5)
#'
#' x_abundance <- hsi_calc_abundance(x, endmembers = em$spectra)
#' x_abundance <- hsi_calc_abundance(
#'   x,
#'   endmembers = em$spectra,
#'   cores = 4,
#'   filename = "abundance.tif",
#'   overwrite = TRUE
#' )
#' }
#'
#' @export
hsi_calc_abundance <- function(
  x,
  endmembers,
  cores = 1,
  filename = "",
  overwrite = FALSE,
  ...
) {
  # Validate inputs
  HSItools:::check_spatraster(x)
  endmembers <- as.matrix(endmembers)

  if (nrow(endmembers) != terra::nlyr(x)) {
    cli::cli_abort(c(
      "{.arg endmembers} must have one row per layer of {.arg x}.",
      "i" = "{.arg x} has {terra::nlyr(x)} layer{?s}; {.arg endmembers} has {nrow(endmembers)} row{?s}."
    ))
  }

  rlang::check_string(filename)

  rlang::check_bool(overwrite)

  wopt_user <- rlang::list2(...)
  HSItools:::check_dots_write(wopt_user, filename)

  # Output layer names from endmember columns
  layer_names <- colnames(endmembers) %||%
    paste0("EM", seq_len(ncol(endmembers)))

  # Build the per-pixel unmixing function
  n_em <- ncol(endmembers)

  solve_cell <- \(i) {
    if (anyNA(i)) {
      return(rep(NA_real_, n_em))
    }
    nnls::nnls(endmembers, i)$x
  }

  # Unmix each pixel
  result <- terra::app(x, fun = solve_cell, cores = cores)
  names(result) <- layer_names

  # Build write options
  wopt_default <- list(names = layer_names)
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
