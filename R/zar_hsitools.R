#' Install HSItools from GitHub
#'
#' @param branch which branch to use. Default "dev".
#'
#' @returns NULL
#'
#' @export
zar_hsitools <- function(branch = "dev") {
  # Install from dev, default
  if (branch == "dev") {
    pak::pkg_install("mzarowka/HSItools@dev")
  } else {
    pak::pkg_install("mzarowka/HSItools")
  }
}
