#' Update packages with pak
#'
#' @returns NULL
#'
#' @export
zar_update <- function() {
  pak::pkg_install(unname(utils::old.packages()[, "Package"]))
}
