#' Update packages with pak
#'
#' @details `utils::old.packages()` only compares against configured repos (CRAN),
#'   so GitHub-sourced packages such as HSItools and unmixR are never updated here.
#'   Use [zar_hsitools()] for HSItools.
#'
#' @returns `NULL`, invisibly.
#'
#' @export
zar_update <- function() {
  pkgs <- utils::old.packages()

  if (is.null(pkgs)) {
    cli::cli_alert_success("All CRAN packages are up to date.")
    return(invisible(NULL))
  }

  to_update <- unname(pkgs[, "Package"])
  cli::cli_alert_info("Updating {length(to_update)} package{?s}.")
  pak::pkg_install(to_update)
  invisible(NULL)
}
