#' Convert a SAM angle table to a distance object
#'
#' @family Spectral Unmixing
#'
#' @param sam `A tibble of pairwise SAM angles as returned by [\`hsi_calc_sam()\`], with columns \`a\`, \`b\`, and \`angle\`.`
#'
#' @returns `A [\`dist\`][stats::dist] object of pairwise SAM angles.`
#'
#' @details
#' Spectral angle is a metric (symmetric, non-negative, zero for identical
#' spectra), so the pairwise table is a distance matrix in melted form. This
#' reshapes it into a [`dist`][stats::dist] object that downstream tools consume
#' directly — [`stats::hclust()`] for a dendrogram, [`stats::cmdscale()`] for an
#' ordination, and so on. Linkage method, cut height, and plotting are left to
#' the caller; this does only the reshape.
#'
#' The input is the triangular output of [`hsi_calc_sam()`] (each pair once).
#' Pairs are mirrored to a full symmetric matrix and the absent diagonal fills
#' to `0` (the zero self-angle) before coercion. Any table with `a`, `b`, and
#' `angle` columns works — real endmembers, synthetic spectra, or a hand-built
#' table — so the reshape is agnostic to what produced the angles.
#'
#' @seealso [`hsi_calc_sam()`]
#'
#' @examples
#' \dontrun{
#' sam <- tibble::tribble(
#'   ~a,    ~b,    ~angle,
#'   "EM1", "EM2", 5.7,
#'   "EM1", "EM3", 22.4,
#'   "EM2", "EM3", 18.9
#' )
#'
#' sam_dist <- hsi_sam_dist(sam)
#'
#' stats::hclust(sam_dist, method = "complete")
#' }
#'
#' @export
hsi_sam_dist <- function(sam) {
  # Validate inputs
  required <- c("a", "b", "angle")
  absent <- setdiff(required, names(sam))

  if (length(absent) > 0) {
    cli::cli_abort("{.arg sam} must contain column{?s} {.val {absent}}.")
  }

  # Consistent label order for both matrix dimensions
  labels <- union(sam$a, sam$b)

  # Mirror the triangular pairs, pivot to a square symmetric matrix ordered by
  # `labels`, and coerce to dist (the absent diagonal fills to a 0 self-angle).
  result <- sam |>
    dplyr::rename(a = "b", b = "a") |>
    dplyr::bind_rows(sam) |>
    tidyr::pivot_wider(
      id_cols = "a",
      names_from = "b",
      values_from = "angle",
      values_fill = 0
    ) |>
    tibble::column_to_rownames("a") |>
    as.matrix() |>
    (\(m) m[labels, labels])() |>
    stats::as.dist()

  # Return result
  result
}
