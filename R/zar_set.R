#' Install pak and purrr before using zar_install
#'
#' @returns
#'
#' @export
#' @examples
zar_set <- function() {
  # Install pak
  install.packages("pak")

  # Install purrr
  pak::pkg_install("purrr")
}
