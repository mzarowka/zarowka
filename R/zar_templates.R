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
  path_like <- c("capture", "reference", "darkspec", "vnir_capture")

  data[path_like] <- purrr::map(
    data[path_like],
    \(i) if (is.null(i)) NULL else fs::path_file(i)
  )

  data <- purrr::compact(data)

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


#' Resolve the capture name and output path for a generator
#'
#' When `path` is a directory the capture is inferred from its basename and the
#' output filename is fixed; when `path` is a file, `capture` must be supplied.
#'
#' @param path Destination path (file or directory)
#' @param capture Capture directory name, or NULL to infer
#' @param filename Output filename used when `path` is a directory
#' @return A list with `capture` and `path`
#' @noRd
resolve_target <- function(path, capture, filename) {
  if (fs::is_dir(path)) {
    capture <- capture %||% fs::path_file(path)
    path <- fs::path(path, filename)
  }

  if (is.null(capture)) {
    cli::cli_abort("Must provide {.arg capture} when {.arg path} is a file.")
  }

  list(capture = capture, path = path)
}


#' Use preview template
#'
#' Calibrates three bands for markup in a GIS and writes the geopackage that
#' every later stage digitises into. Run this first.
#'
#' @param path Destination path (file or directory)
#' @param sensor Sensor name: "vnir" or "swir"
#' @param capture Capture directory name. If NULL and path is directory,
#'   inferred from path.
#' @param reference White reference capture directory name. Defaults to
#'   `capture` (single-session workflow).
#' @param darkspec Specimen-side dark reference capture directory name.
#'   Defaults to `capture` (specimen's own DARKREF). Override only when
#'   sourcing the specimen-side dark from a different session.
#' @param if_exists What to do if file exists: "error", "skip", or "overwrite"
#' @export
zar_template_preview <- function(
  path,
  sensor,
  capture = NULL,
  reference = capture,
  darkspec = capture,
  if_exists = "error"
) {
  sensor <- match.arg(sensor, c("vnir", "swir"))

  target <- resolve_target(path, capture, "01_preview.R")

  use_template(
    paste0("preview_", sensor, ".R"),
    target$path,
    data = list(
      capture = target$capture,
      reference = reference %||% target$capture,
      darkspec = darkspec %||% target$capture
    ),
    if_exists = if_exists
  )
}


#' Use reflectance template
#'
#' Calibrates the cube cropped to the transect digitised on the preview. Run
#' [`zar_template_preview()`] first and digitise `ends`.
#'
#' @inheritParams zar_template_preview
#' @export
zar_template_reflectance <- function(
  path,
  sensor,
  capture = NULL,
  reference = capture,
  darkspec = capture,
  if_exists = "error"
) {
  sensor <- match.arg(sensor, c("vnir", "swir"))

  target <- resolve_target(path, capture, "02_reflectance.R")

  use_template(
    "reflectance.R",
    target$path,
    data = list(
      sensor = sensor,
      capture = target$capture,
      reference = reference %||% target$capture,
      darkspec = darkspec %||% target$capture
    ),
    if_exists = if_exists
  )
}


#' Use coregister template
#'
#' Warps this sensor's reflectance onto the paired VNIR grid using GCPs
#' digitised on both previews.
#'
#' @inheritParams zar_template_preview
#' @param vnir_capture Paired VNIR capture directory name. Supplies the target
#'   GCPs and the target grid.
#' @export
zar_template_coregister <- function(
  path,
  sensor,
  capture = NULL,
  vnir_capture,
  if_exists = "error"
) {
  sensor <- match.arg(sensor, c("vnir", "swir"))

  target <- resolve_target(path, capture, "03_coregister.R")

  use_template(
    "coregister.R",
    target$path,
    data = list(
      sensor = sensor,
      capture = target$capture,
      vnir_capture = vnir_capture
    ),
    if_exists = if_exists
  )
}


#' Use postprocess template
#'
#' Smooths and prepares derivatives. A co-registered sensor postprocesses the
#' warped product; otherwise its own reflectance.
#'
#' @inheritParams zar_template_preview
#' @param coregistered Logical. Postprocess the co-registered product from
#'   [`zar_template_coregister()`] rather than this sensor's own reflectance.
#'   Default `FALSE`.
#' @export
zar_template_postprocess <- function(
  path,
  sensor,
  capture = NULL,
  coregistered = FALSE,
  if_exists = "error"
) {
  sensor <- match.arg(sensor, c("vnir", "swir"))

  target <- resolve_target(path, capture, "04_postprocess.R")

  use_template(
    "postprocess.R",
    target$path,
    data = list(
      sensor = sensor,
      capture = target$capture,
      source_suffix = if (coregistered) "_coreg" else ""
    ),
    if_exists = if_exists
  )
}


#' Use features template
#'
#' PCA and MNF on the smoothed and continuum-removed products.
#'
#' @inheritParams zar_template_preview
#' @param n_components Number of PCA/MNF components to retain. Default 10.
#' @export
zar_template_features <- function(
  path,
  sensor,
  capture = NULL,
  n_components = 10L,
  if_exists = "error"
) {
  sensor <- match.arg(sensor, c("vnir", "swir"))

  target <- resolve_target(path, capture, "05_features.R")

  use_template(
    "features.R",
    target$path,
    data = list(
      sensor = sensor,
      capture = target$capture,
      n_components = n_components
    ),
    if_exists = if_exists
  )
}
