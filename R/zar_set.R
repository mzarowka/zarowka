#' Install pak and purrr before using zar_install
#'
#' @returns NULL
#'
#' @export
zar_set <- function() {
  # Install pak
  install.packages("pak")

  # Install purrr
  pak::pkg_install("purrr")
}
