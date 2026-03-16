#' Update packages with pak
#'
#' @returns NULL invisibly
#'
#' @export
zar_update <- function() {
  pkgs <- utils::old.packages()

  if (is.null(pkgs)) {
    message("All packages are up to date.")
    return(invisible(NULL))
  }

  pak::pkg_install(unname(pkgs[, "Package"]))
  invisible(NULL)
}
