#' Internal template copying function
#' @param template_file Name of the template file in inst/templates/
#' @param path Destination path for the new file
#' @param data Named list of template variables passed to whisker
#' @param if_exists What to do if file exists: "error", "skip", or "overwrite"
#' @return Invisibly returns the destination path
#' @noRd
use_template <- function(
  template_file,
  path,
  data = list(),
  if_exists = "error"
) {
  if_exists <- match.arg(if_exists, c("error", "skip", "overwrite"))

  # Sanitise path-like variables to bare names
  if (!is.null(data$capture)) {
    data$capture <- fs::path_file(data$capture)
  }
  if (!is.null(data$reference)) {
    data$reference <- fs::path_file(data$reference)
  }
  if (!is.null(data$vnir_capture)) {
    data$vnir_capture <- fs::path_file(data$vnir_capture)
  }

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

  # Ensure destination directory exists
  dest_dir <- fs::path_dir(path)

  if (!fs::dir_exists(dest_dir)) {
    fs::dir_create(dest_dir)
  }

  # Read and render template
  template_raw <- readLines(template_path, warn = FALSE)
  template_rendered <- whisker::whisker.render(template_raw, data = data)

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
    path <- fs::path(path, "01_reflectance.R")
  }

  if (is.null(capture)) {
    cli::cli_abort("Must provide {.arg capture} when {.arg path} is a file.")
  }

  use_template(
    "reflectance_vnir.R",
    path,
    data = list(capture = capture, reference = reference),
    if_exists = if_exists
  )
}


#' Use SWIR reflectance template
#' @param path Destination path (file or directory)
#' @param capture Capture directory name. If NULL and path is directory, inferred from path.
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
    path <- fs::path(path, "01_reflectance.R")
  }

  if (is.null(capture)) {
    cli::cli_abort("Must provide {.arg capture} when {.arg path} is a file.")
  }

  use_template(
    "reflectance_swir.R",
    path,
    data = list(capture = capture, reference = reference),
    if_exists = if_exists
  )
}


#' Use VNIR postprocess template
#' @param path Destination path (file or directory)
#' @param capture Capture directory name. If NULL and path is directory, inferred from path.
#' @param if_exists What to do if file exists: "error", "skip", or "overwrite"
#' @export
zar_template_vnir_postprocess <- function(
  path,
  capture = NULL,
  if_exists = "error"
) {
  if (fs::is_dir(path)) {
    capture <- capture %||% fs::path_file(path)
    path <- fs::path(path, "postprocess.R")
  }

  if (is.null(capture)) {
    cli::cli_abort("Must provide {.arg capture} when {.arg path} is a file.")
  }

  use_template(
    "postprocess_vnir.R",
    path,
    data = list(capture = capture),
    if_exists = if_exists
  )
}


#' Use SWIR postprocess template
#' @param path Destination path (file or directory)
#' @param capture Capture directory name. If NULL and path is directory, inferred from path.
#' @param vnir_capture Paired VNIR capture directory name. Used to locate the
#'   transect layer computed during VNIR postprocessing.
#' @param if_exists What to do if file exists: "error", "skip", or "overwrite"
#' @export
zar_template_swir_postprocess <- function(
  path,
  capture = NULL,
  vnir_capture,
  if_exists = "error"
) {
  if (fs::is_dir(path)) {
    capture <- capture %||% fs::path_file(path)
    path <- fs::path(path, "postprocess.R")
  }

  if (is.null(capture)) {
    cli::cli_abort("Must provide {.arg capture} when {.arg path} is a file.")
  }

  use_template(
    "postprocess_swir.R",
    path,
    data = list(capture = capture, vnir_capture = vnir_capture),
    if_exists = if_exists
  )
}

#' Use VNIR features template
#' @param path Destination path (file or directory)
#' @param capture Capture directory name. If NULL and path is directory, inferred from path.
#' @param n_components Number of PCA/MNF components to retain. Default 10.
#' @param if_exists What to do if file exists: "error", "skip", or "overwrite"
#' @export
zar_template_vnir_features <- function(
  path,
  capture = NULL,
  n_components = 10L,
  if_exists = "error"
) {
  if (fs::is_dir(path)) {
    capture <- capture %||% fs::path_file(path)
    path <- fs::path(path, "features.R")
  }

  if (is.null(capture)) {
    cli::cli_abort("Must provide {.arg capture} when {.arg path} is a file.")
  }

  use_template(
    "features_vnir.R",
    path,
    data = list(capture = capture, n_components = n_components),
    if_exists = if_exists
  )
}

#' Use SWIR features template
#' @param path Destination path (file or directory)
#' @param capture Capture directory name. If NULL and path is directory, inferred from path.
#' @param n_components Number of PCA/MNF components to retain. Default 10.
#' @param if_exists What to do if file exists: "error", "skip", or "overwrite"
#' @export
zar_template_swir_features <- function(
  path,
  capture = NULL,
  n_components = 10L,
  if_exists = "error"
) {
  if (fs::is_dir(path)) {
    capture <- capture %||% fs::path_file(path)
    path <- fs::path(path, "features.R")
  }

  if (is.null(capture)) {
    cli::cli_abort("Must provide {.arg capture} when {.arg path} is a file.")
  }

  use_template(
    "features_swir.R",
    path,
    data = list(capture = capture, n_components = n_components),
    if_exists = if_exists
  )
}
