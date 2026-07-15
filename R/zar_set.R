#' Install pak and purrr before using zar_install
#'
#' @returns `NULL`, invisibly.
#'
#' @export
zar_set <- function() {
  if (!requireNamespace("pak", quietly = TRUE)) {
    utils::install.packages("pak")
  }
  pak::pkg_install("purrr")
  invisible(NULL)
}
