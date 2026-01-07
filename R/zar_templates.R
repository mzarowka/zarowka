#' Internal template copying function
#' @param template_file Name of the template file in inst/templates/
#' @param path Destination path for the new file
#' @param capture Capture directory name
#' @param reference Reference directory name
#' @param if_exists What to do if file exists: "error", "skip", or "overwrite"
#' @return Invisibly returns the destination path
#' @noRd
use_template <- function(
  template_file,
  path,
  capture,
  reference,
  if_exists = "error"
) {
  if_exists <- match.arg(if_exists, c("error", "skip", "overwrite"))

  template_path <- system.file(
    "templates",
    template_file,
    package = "zarowka",
    mustWork = TRUE
  )

  # Check if destination exists
  if (fs::file_exists(path)) {
    switch(
      if_exists,
      error = cli::cli_abort(c(
        "File already exists: {.path {path}}",
        "i" = "Use {.arg if_exists = 'skip'} or {.arg 'overwrite'}."
      )),
      skip = {
        cli::cli_alert_info("Skipping existing file: {.path {path}}")
        return(invisible(path))
      },
      overwrite = NULL
    )
  }

  # Ensure destination directory exists (skip if root/drive)
  dest_dir <- fs::path_dir(path)

  if (!fs::dir_exists(dest_dir)) {
    fs::dir_create(dest_dir)
  }

  # Read and render template
  template_raw <- readLines(template_path, warn = FALSE)
  template_rendered <- whisker::whisker.render(
    template_raw,
    data = list(capture = capture, reference = reference)
  )

  # Write rendered template
  writeLines(template_rendered, path)

  cli::cli_alert_success("Template created at {.path {path}}")

  invisible(path)
}


#' Use VNIR reflectance template
#' @param path Destination path (file or directory)
#' @param capture Capture directory name. If NULL and path is directory, inferred from path.
#' @param reference Reference directory name. Defaults to capture.
#' @param if_exists What to do if file exists: "error", "skip", or "overwrite"
#' @export
zar_template_vnir <- function(
  path,
  capture = NULL,
  reference = capture,
  if_exists = "error"
) {
  if (fs::is_dir(path)) {
    capture <- capture %||% fs::path_file(path)
    reference <- reference %||% capture
    path <- fs::path(path, "reflectance_vnir.R")
  }

  if (is.null(capture)) {
    cli::cli_abort("Must provide {.arg capture} when {.arg path} is a file.")
  }

  use_template("reflectance_vnir.R", path, capture, reference, if_exists)
}


#' Use SWIR reflectance template
#' @param path Destination path (file or directory)
#' @param capture Capture directory name. If NULL and path is directory, inferred from path.
#' @param reference Reference directory name. Defaults to capture.
#' @param reference Reference directory name. Defaults to capture.
#' @param if_exists What to do if file exists: "error", "skip", or "overwrite"
#' @export
zar_template_swir <- function(
  path,
  capture = NULL,
  reference = capture,
  if_exists = "error"
) {
  if (fs::is_dir(path)) {
    capture <- capture %||% fs::path_file(path)
    reference <- reference %||% capture
    path <- fs::path(path, "reflectance_swir.R")
  }

  if (is.null(capture)) {
    cli::cli_abort("Must provide {.arg capture} when {.arg path} is a file.")
  }

  use_template("reflectance_swir.R", path, capture, reference, if_exists)
}
