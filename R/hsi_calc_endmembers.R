#' Extract endmembers from a pooled pixel table
#'
#' @family HSI Transformations
#'
#' @param data         A [tibble][tibble::tibble] or matrix of pixel spectra:
#'   wavelength-named band columns, optionally preceded by the reserved
#'   provenance columns `scene`, `roi`, and `cell`.
#' @param n_endmembers Positive integer. Number of endmembers to extract.
#' @param reduction    Character. Dimensionality reduction front-end. One of
#'   `"pca"` or `"mnf"`. Default `"pca"`.
#'
#' @returns A named list with components:
#'   \item{spectra}{Numeric matrix of endmember spectra, bands in rows and
#'     endmembers in columns, in reflectance space. Ready for
#'     [`hsi_calc_abundance()`].}
#'   \item{indices}{Integer vector. Rows of `data` chosen as endmembers.}
#'   \item{locations}{A [tibble][tibble::tibble] of the provenance rows at
#'     those indices, or `NULL` when `data` carries no provenance columns.}
#'   \item{model}{The fitted reduction model (e.g. a `prcomp` object).}
#'   \item{diagnostics}{A [tibble][tibble::tibble] of pairwise spectral angles
#'     between endmembers, ascending. Near-zero pairs signal over-extraction.}
#'
#' @details
#' Endmembers are extracted by VCA-seeded N-FINDR: VCA supplies a fast, robust
#' set of extreme pixels, and N-FINDR refines them by maximising simplex volume
#' jointly. Neither half is exposed as an option. VCA alone never re-evaluates
#' its greedy, seed-sensitive picks; N-FINDR alone needs a starting simplex, and
#' `unmixR`'s built-in initialisers fail on real data. The pairing is the only
#' path that is both robust and volume-optimal, so it is the algorithm this
#' function implements rather than one of several user-selectable methods.
#'
#' VCA and N-FINDR require different search dimensionalities. VCA needs `p`
#' projection directions, so it runs in `n_endmembers` reduced components;
#' N-FINDR's volume search lives in the `p - 1` dimensions a `p`-vertex simplex
#' spans, so it runs in `n_endmembers - 1`. Both stay below `unmixR`'s internal
#' SNR step, which builds an O(N^2) pixel cross-product and exhausts memory on
#' pooled sets. Endmember spectra are re-read from the original bands at the
#' selected pixels, so the reduction only governs which pixels are chosen — the
#' reported spectra are reduction-invariant.
#'
#' VCA has a stochastic projection step; call [`set.seed()`] before this
#' function for reproducible extraction.
#'
#' @examples
#' \dontrun{
#' fit <- hsi_extract_spectra(x, roi = rois)
#' em <- hsi_calc_endmembers(fit, n_endmembers = 5)
#' x_abundance <- hsi_calc_abundance(x, endmembers = em$spectra)
#' }
#'
#' @export
hsi_calc_endmembers <- function(data, n_endmembers, reduction = "pca") {
  # Validate inputs
  rlang::check_installed("unmixR")
  reduction <- match.arg(reduction, choices = c("pca", "mnf"))

  reserved <- c("scene", "roi", "cell")
  data <- tibble::as_tibble(data)
  has_provenance <- all(reserved %in% names(data))

  bands <- if (has_provenance) {
    dplyr::select(data, -dplyr::all_of(reserved))
  } else {
    data
  }
  reflectance <- as.matrix(bands)

  n_bands <- ncol(reflectance)

  if (n_endmembers < 2 || n_endmembers > n_bands) {
    cli::cli_abort(c(
      "{.arg n_endmembers} must be between 2 and the number of bands.",
      "i" = "Got {n_endmembers} with {n_bands} band{?s}."
    ))
  }

  # Reduce dimensionality (the search space only; spectra are re-read below)
  reduced <- reduce_spectra(reflectance, reduction)

  # VCA and N-FINDR want different dimensionalities. VCA needs p projection
  # directions, so it takes p components. N-FINDR's volume search lives in the
  # p - 1 dimensions a p-vertex simplex spans, so it takes p - 1. Both stay
  # below unmixR's internal SNR branch (the O(N^2) pixel cross-product that
  # exhausts memory on pooled sets).
  scores_vca <- reduced$scores[, seq_len(n_endmembers), drop = FALSE]
  scores_nfindr <- reduced$scores[, seq_len(n_endmembers - 1), drop = FALSE]

  # VCA-seeded N-FINDR
  vca_fit <- unmixR::vca(scores_vca, p = n_endmembers)
  nfindr_fit <- unmixR::nfindr(
    scores_nfindr,
    p = n_endmembers,
    indices = vca_fit$indices
  )
  indices <- nfindr_fit$indices

  # Re-read endmember spectra from the original bands (reduction-invariant)
  spectra <- t(reflectance[indices, , drop = FALSE])
  colnames(spectra) <- paste0("EM", seq_len(n_endmembers))

  # Provenance of the selected pixels, when available
  locations <- if (has_provenance) {
    data |>
      dplyr::slice(indices) |>
      dplyr::select(dplyr::all_of(reserved)) |>
      dplyr::mutate(endmember = colnames(spectra), .before = 1)
  } else {
    NULL
  }

  # Pairwise spectral angles — near-zero pairs flag over-extraction
  diagnostics <- endmember_angles(spectra)

  # Return result
  list(
    spectra = spectra,
    indices = indices,
    locations = locations,
    model = reduced$model,
    diagnostics = diagnostics
  )
}

#' Reduce a pixel-by-band matrix to component scores
#'
#' @param reflectance Numeric matrix, pixels in rows and bands in columns.
#' @param reduction   Character. One of `"pca"` or `"mnf"`.
#'
#' @returns A named list with `scores` (pixels by components) and `model`
#'   (the fitted reduction object).
#'
#' @noRd
reduce_spectra <- function(reflectance, reduction = "pca") {
  if (reduction == "pca") {
    model <- stats::prcomp(reflectance, center = TRUE, scale. = TRUE)
    return(list(scores = model$x, model = model))
  }

  # mnf: placeholder for the noise-adjusted front-end. Pooled pixels break
  # spacetime's lag-1 noise estimate, so a pooled-safe MNF is needed before
  # this path is enabled.
  cli::cli_abort("{.val mnf} reduction is not implemented yet.")
}

#' Pairwise spectral angles between endmember spectra
#'
#' @param spectra Numeric matrix, bands in rows and endmembers in columns.
#'
#' @returns A [tibble][tibble::tibble] of endmember pairs and their spectral
#'   angle in degrees, ascending.
#'
#' @noRd
endmember_angles <- function(spectra) {
  sam <- \(a, b) {
    acos(pmin(pmax(sum(a * b) / sqrt(sum(a^2) * sum(b^2)), -1), 1)) * 180 / pi
  }

  ems <- colnames(spectra)

  tidyr::expand_grid(a = ems, b = ems) |>
    dplyr::filter(a < b) |>
    dplyr::mutate(
      angle = purrr::map2_dbl(a, b, \(i, j) sam(spectra[, i], spectra[, j]))
    ) |>
    dplyr::arrange(angle)
}
