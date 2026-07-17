#' Apply a fitted reduction model to a raster
#'
#' @family HSI Transformations
#'
#' @param x A [`SpatRaster`][terra::SpatRaster-class] with hyperspectral data.
#' @param model A fitted reduction model. Currently a
#'   [`prcomp`][stats::prcomp] object (PCA); other reductions are not yet
#'   supported.
#' @param cores Positive integer. Number of parallel cores. Default `1`.
#' @param filename Character. Output filename. Default `""` keeps result in memory.
#' @param overwrite Logical. Overwrite existing file. Default `FALSE`.
#' @param ... Additional arguments passed to [`terra::writeRaster()`].
#'
#' @returns A [`SpatRaster`][terra::SpatRaster-class] with one score layer per
#'   component of `model`.
#'
#' @details
#' The transform is carried by the model's own `predict` method via
#' [`terra::predict()`], so the function is agnostic to the reduction once the
#' model class is recognised. All model-class knowledge (how many input bands
#' the model expects, how many components it produces, and their names) lives in
#' the internal `reduction_info()` helper; adding a new reduction means adding a
#' branch there, not changing this function.
#'
#' `x` must carry the **same bands, trimmed the same way and in the same order**,
#' that the model was fit on. Only the band *count* is checked here; wavelength
#' alignment and edge trimming are the caller's responsibility (the same
#' load-bearing trim assumed throughout the unmixing pipeline). Background
#' (`NA`) pixels pass through as `NA` scores.
#'
#' @seealso
#' [`hsi_calc_endmembers()`] produces the reduction model during endmember
#' search; [`hsi_calc_abundance()`] is the companion apply step in reflectance
#' space.
#'
#' @examples
#' \dontrun{
#' x <- terra::rast("REFLECTANCE_testdata.tif")
#'
#' # Fit a reduction on extracted spectra, then project the whole scene.
#' spectra <- hsi_extract_spectra(x, n = 1000)
#' band_cols <- setdiff(names(spectra), c("scene", "roi", "cell"))
#' pca <- stats::prcomp(spectra[band_cols], center = TRUE)
#'
#' x_scores <- hsi_apply_reduction(x, model = pca)
#'
#' x_scores <- hsi_apply_reduction(
#'   x,
#'   model = pca,
#'   filename = "scores.tif",
#'   overwrite = TRUE
#' )
#' }
#'
#' @export
hsi_apply_reduction <- function(
  x,
  model,
  cores = 1,
  filename = "",
  overwrite = FALSE,
  ...
) {
  # Validate inputs
  HSItools:::check_spatraster(x)
  info <- reduction_info(model)

  # The model was fit on a fixed set of bands; x must present the same count,
  # in the same order. Only the count is checked here (see @details).
  n_layers <- terra::nlyr(x)
  if (n_layers != info$nvars) {
    cli::cli_abort(c(
      "{.arg x} has the wrong number of layers for {.arg model}.",
      "i" = "{.arg model} was fit on {info$nvars} band{?s}, but {.arg x} has {n_layers}.",
      "i" = "Reduce {.arg x} to the same trimmed bands, in the same order, used to fit {.arg model}."
    ))
  }

  rlang::check_string(filename)

  rlang::check_bool(overwrite)

  # Build write options
  wopt_default <- list(names = info$names)
  wopt_user <- rlang::list2(...)
  wopt <- purrr::list_modify(wopt_default, !!!wopt_user)

  # Apply reduction. terra::predict dispatches on the model's predict method,
  # streams block by block (out-of-core), and writes directly — it accepts
  # filename = "" unlike terra::writeRaster(), so no separate write guard is
  # needed. na.rm keeps background NA cells out of the model and back as NA.
  result <- terra::predict(
    x,
    model,
    na.rm = TRUE,
    cores = cores,
    filename = filename,
    overwrite = overwrite,
    wopt = wopt
  )

  # Return result
  result
}

#' Reduction model metadata
#'
#' Single point of model-class knowledge for [`hsi_apply_reduction()`]. Returns
#' the number of input bands the model expects, the number of components it
#' produces, and the output layer names. Aborts for unsupported model classes.
#'
#' @param model A fitted reduction model.
#' @param call Environment for error reporting. Auto-detected via
#'   [rlang::caller_env()].
#'
#' @returns A named list with elements `nvars` (integer), `ncomp` (integer),
#'   and `names` (character vector of length `ncomp`).
#'
#' @noRd
reduction_info <- function(model, call = rlang::caller_env()) {
  if (inherits(model, "prcomp")) {
    component_names <- colnames(model$rotation)
    if (is.null(component_names)) {
      component_names <- paste0("PC", seq_len(ncol(model$rotation)))
    }
    return(list(
      nvars = nrow(model$rotation),
      ncomp = ncol(model$rotation),
      names = component_names
    ))
  }

  cli::cli_abort(
    c(
      "{.arg model} is not a supported reduction model.",
      "i" = "Got a {.cls {class(model)}}; only {.cls prcomp} (PCA) is supported.",
      "x" = "MNF support is not yet implemented."
    ),
    call = call
  )
}
