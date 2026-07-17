#' Install HSItools from GitHub
#'
#' @param branch Character. Which branch to install. Default `"dev"`.
#'
#' @returns `NULL`, invisibly. Called for its side effect.
#'
#' @export
zar_hsitools <- function(branch = "dev") {
  pak::pkg_install(paste0("mzarowka/HSItools@", branch))
  invisible(NULL)
}
