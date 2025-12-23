#' Internal template copying function
#' @param template_file Name of the template file in inst/templates/
#' @param path Destination path for the new file
#' @param overwrite Whether to overwrite existing file
#' @return Invisibly returns the destination path
#' @noRd
.use_template <- function(template_file, path, overwrite = FALSE) {
  # Locate template in installed package
  template_path <- system.file(
    "templates",
    template_file,
    package = "zarowka",
    mustWork = TRUE
  )

  # Check if destination exists
  if (!overwrite && fs::file_exists(path)) {
    cli::cli_abort(c(
      "File already exists: {.path {path}}",
      "i" = "Use {.arg overwrite = TRUE} to replace it."
    ))
  }

  # Ensure destination directory exists (skip if root/drive)
  dest_dir <- fs::path_dir(path)

  if (!fs::dir_exists(dest_dir)) {
    fs::dir_create(dest_dir)
  }

  # Copy template
  fs::file_copy(template_path, path, overwrite = overwrite)

  cli::cli_alert_success("Template created at {.path {path}}")

  invisible(path)
}


#' Use SWIR reflectance template
#' @param path Destination path for the script
#' @param overwrite Overwrite existing file? Default FALSE
#' @export
zar_template_swir <- function(path, overwrite = FALSE) {
  .use_template("template_swir.R", path, overwrite)
}


#' Use VNIR reflectance template
#' @param path Destination path for the script
#' @param overwrite Overwrite existing file? Default FALSE
#' @export
zar_template_vnir <- function(path, overwrite = FALSE) {
  .use_template("template_vnir.R", path, overwrite)
}
