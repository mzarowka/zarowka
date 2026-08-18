#' Pairwise spectral angles between spectra
#'
#' @family HSI Unmixing
#'
#' @param spectra A numeric matrix of spectra, bands in rows and named spectra in
#'   columns, such as the `spectra` component of [`hsi_calc_endmembers()`].
#'
#' @returns A [tibble][tibble::tibble] of spectrum pairs and their spectral angle
#'   in degrees, ascending. Near-zero pairs signal collinear (effectively
#'   duplicate) spectra.
#'
#' @details
#' The spectral angle treats each spectrum as a vector over its bands and
#' measures the angle between two such vectors, following Kruse et al. (1993):
#' \deqn{\alpha = \cos^{-1}\left(\frac{\sum_i a_i b_i}{\sqrt{\sum_i a_i^2}\,
#'   \sqrt{\sum_i b_i^2}}\right)}
#' the arc-cosine of the cosine similarity between spectra `a` and `b`. The cosine
#' is clamped to \eqn{[-1, 1]} before `acos()` to guard against floating-point
#' overshoot, then converted to degrees.
#'
#' Because only vector direction enters, the angle is invariant to a constant
#' multiplicative scaling such as illumination or albedo — its defining property.
#' For non-negative reflectance the angle lies on a 0–90° scale. Smaller is more
#' similar: as a practical rule of thumb, pairs below roughly 5° are effectively
#' the same material and flag over-extraction, while pairs above ~17° are clearly
#' distinct. These thresholds are working conventions, not from a specific source.
#'
#' @references
#' Kruse, F. A., Lefkoff, A. B., Boardman, J. W., Heidebrecht, K. B., Shapiro,
#' A. T., Barloon, P. J., Goetz, A. F. H. (1993). The Spectral Image Processing
#' System (SIPS) — Interactive Visualization and Analysis of Imaging Spectrometer
#' Data. \emph{Remote Sensing of Environment} 44(2–3), 145–163.
#' \doi{10.1016/0034-4257(93)90013-N}
#'
#' Yuhas, R. H., Goetz, A. F. H., Boardman, J. W. (1992). Discrimination among
#' semi-arid landscape endmembers using the Spectral Angle Mapper (SAM)
#' algorithm. In \emph{Summaries of the Third Annual JPL Airborne Geoscience
#' Workshop}, JPL Publication 92-14, vol. 1, 147–149.
#'
#' @examples
#' \dontrun{
#' em <- hsi_calc_endmembers(spectra, reduction = red, n_endmembers = 6)
#' hsi_calc_sam(em$spectra)
#' }
#'
#' @export
hsi_calc_sam <- function(spectra) {
  # Validate inputs
  if (!is.matrix(spectra) || is.null(colnames(spectra))) {
    cli::cli_abort("{.arg spectra} must be a matrix with named columns.")
  }

  # Spectral angle (Kruse et al. 1993): arccos(a.b / (||a|| ||b||)), in degrees.
  # The cosine is clamped to [-1, 1] to guard against floating-point overshoot.
  sam <- \(a, b) {
    acos(pmin(pmax(sum(a * b) / sqrt(sum(a^2) * sum(b^2)), -1), 1)) * 180 / pi
  }

  # Every unordered pair of columns, ascending by angle
  labels <- colnames(spectra)

  tidyr::expand_grid(a = labels, b = labels) |>
    dplyr::filter(.data$a < .data$b) |>
    dplyr::mutate(
      angle = purrr::map2_dbl(
        .data$a,
        .data$b,
        \(i, j) sam(spectra[, i], spectra[, j])
      )
    ) |>
    dplyr::arrange(.data$angle)
}
