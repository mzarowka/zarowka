#' Create a new core directory scaffold
#' @param core Core directory name, e.g. "GKUT25_02".
#' @param path Path to the site directory where the core should be created.
#' @param if_exists What to do if core directory already exists: "error" or "skip".
#' @return Invisibly returns the path to the created core directory.
#' @export
zar_create_core <- function(
  core,
  path,
  if_exists = "error"
) {
  if_exists <- match.arg(if_exists, c("error", "skip"))

  core_path <- fs::path(path, core)

  if (fs::dir_exists(core_path)) {
    switch(
      if_exists,
      error = cli::cli_abort(c(
        "Core directory already exists: {.path {core_path}}",
        "i" = "Use {.arg if_exists = 'skip'} to skip silently."
      )),
      skip = {
        cli::cli_alert_info("Skipping existing core: {.path {core_path}}")
        return(invisible(core_path))
      }
    )
  }

  # Create sensor subdirectories
  purrr::walk(
    c("vnir", "swir"),
    \(sensor) fs::dir_create(fs::path(core_path, sensor))
  )

  # Drop .here anchor in core root
  fs::file_create(fs::path(core_path, ".here"))

  cli::cli_alert_success("Core scaffold created at {.path {core_path}}")

  invisible(core_path)
}
