#' Use SWIR coregister template
#' @param path Destination path (file or directory)
#' @param capture Capture directory name. If NULL and path is directory,
#'   inferred from path.
#' @param vnir_capture Paired VNIR capture directory name. Used to locate
#'   target GCPs and RGB reference raster from VNIR spatial directory.
#' @param if_exists What to do if file exists: "error", "skip", or "overwrite"
#' @export
zar_template_swir_coregister <- function(
  path,
  capture = NULL,
  vnir_capture,
  if_exists = "error"
) {
  if (fs::is_dir(path)) {
    capture <- capture %||% fs::path_file(path)
    path <- fs::path(path, "02_coregister.R")
  }

  if (is.null(capture)) {
    cli::cli_abort("Must provide {.arg capture} when {.arg path} is a file.")
  }

  use_template(
    "coregister_swir.R",
    path,
    data = list(capture = capture, vnir_capture = vnir_capture),
    if_exists = if_exists
  )
}
