#' Unmix a hyperspectral raster into per-endmember abundances
#'
#' @family HSI Transformations
#'
#' @param x A [`SpatRaster`][terra::SpatRaster-class] with hyperspectral data.
#' @param endmembers Numeric matrix of endmember spectra, bands in rows and
#'   endmembers in columns. Must have one row per layer of `x`. Column names,
#'   if present, become output layer names.
#' @param method Character. Unmixing estimator. One of `"nnls"`
#'   (non-negative least squares) or `"ols"` (ordinary least squares).
#'   Default `"nnls"`.
#' @param index_name Character. Name for the output layer. Default `NULL`.
#' @param cores Positive integer. Number of parallel cores. Default `1`.
#' @param filename Character. Output filename. Default `""` keeps result in memory.
#' @param overwrite Logical. Overwrite existing file. Default `FALSE`.
#' @param ... Additional arguments passed to [`terra::writeRaster()`].
#'
#' @returns A [`SpatRaster`][terra::SpatRaster-class] with one abundance layer
#'   per endmember.
#'
#' @details
#' Each pixel spectrum is decomposed as a linear combination of the supplied
#' endmember spectra. `"nnls"` constrains abundances to be non-negative without
#' forcing them to sum to one, which suits scenes with albedo and shade
#' variation. `"ols"` is unconstrained and faster but can return negative
#' abundances. Wavelength correspondence between `x` and `endmembers` is the
#' caller's responsibility: the function checks band count, not band alignment.
#'
#' @examples
#' \dontrun{
#' x <- terra::rast("REFLECTANCE_testdata.tif")
#' em <- matrix(stats::runif(terra::nlyr(x) * 3), ncol = 3)
#' x_abundance <- hsi_calc_abundance(x, endmembers = em)
#' x_abundance <- hsi_calc_abundance(
#'   x,
#'   endmembers = em,
#'   method = "ols",
#'   cores = 4,
#'   filename = "output_abundance.tif",
#'   overwrite = TRUE
#' )
#' }
#'
#' @export
hsi_calc_abundance <- function(
  x,
  endmembers,
  method = "nnls",
  index_name = NULL,
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

  method <- match.arg(method, choices = c("nnls", "ols"))

  # Resolve output layer names from endmember columns
  layer_names <- index_name %||%
    colnames(endmembers) %||%
    paste0("EM", seq_len(ncol(endmembers)))

  # Build the per-pixel unmixing function
  n_em <- ncol(endmembers)

  solve_cell <- switch(
    method,
    nnls = \(i) {
      if (anyNA(i)) {
        return(rep(NA_real_, n_em))
      }
      nnls::nnls(endmembers, i)$x
    },
    ols = \(i) {
      if (anyNA(i)) {
        return(rep(NA_real_, n_em))
      }
      stats::.lm.fit(endmembers, i)$coefficients
    }
  )

  # Unmix each pixel
  result <- terra::app(x, fun = solve_cell, cores = cores)
  names(result) <- layer_names

  # Build write options
  wopt_default <- list(names = layer_names)
  wopt_user <- rlang::list2(...)
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
