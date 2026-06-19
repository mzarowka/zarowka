#' Find endmembers in a hyperspectral pixel matrix
#'
#' @family HSI Unmixing
#'
#' @param spectra A numeric matrix of pixel spectra, pixels in rows and
#'   wavelength-named bands in columns, as returned by [`hsi_extract_spectra()`].
#'   Source cell numbers are read from the row names when present.
#' @param reduction A fitted dimensionality-reduction model, such as a `prcomp`
#'   object, defining the search space.
#' @param n_endmembers Positive integer. Number of endmembers to find.
#'
#' @returns A named list with components:
#'   \item{spectra}{Numeric matrix of endmember spectra, bands in rows and
#'     endmembers in columns, in reflectance space. Ready for
#'     [`hsi_calc_abundance()`].}
#'   \item{indices}{Integer vector. Rows of `spectra` chosen as endmembers.}
#'   \item{locations}{Integer vector of the source cell numbers at those rows,
#'     named by endmember, or `NULL` when `spectra` carries no row names.}
#'
#' @details
#' Endmembers are found by VCA-seeded N-FINDR: VCA supplies a fast, robust set of
#' extreme pixels, and N-FINDR refines them by maximising simplex volume jointly.
#' Neither half is exposed as an option. VCA alone never re-evaluates its greedy,
#' seed-sensitive picks; N-FINDR alone needs a starting simplex, and `unmixR`'s
#' built-in initialisers fail on real data. The pairing is the only path that is
#' both robust and volume-optimal.
#'
#' VCA and N-FINDR require different search dimensionalities. VCA needs `p`
#' projection directions, so it runs in `n_endmembers` reduced components;
#' N-FINDR's volume search lives in the `p - 1` dimensions a `p`-vertex simplex
#' spans, so it runs in `n_endmembers - 1`. Both stay below `unmixR`'s internal
#' SNR step, which builds an O(N^2) pixel cross-product and exhausts memory on
#' large sets. Endmember spectra are re-read from the original bands at the
#' selected pixels, so the reported spectra are reduction-invariant.
#'
#' Fit the reduction separately and pass it in, for example
#' `stats::prcomp(spectra, center = TRUE, scale. = FALSE)`. Keeping it out lets a
#' single fit be reused across refits at different `n_endmembers` and saved with
#' [`saveRDS()`] to survive a session restart. Inspect separation between the
#' returned spectra with [`hsi_calc_sam()`].
#'
#' VCA has a stochastic projection step; call [`set.seed()`] before this function
#' for reproducible results.
#'
#' @references
#' Nascimento, J. M. P., Bioucas-Dias, J. M. (2005). Vertex component analysis: a
#' fast algorithm to unmix hyperspectral data. \emph{IEEE Transactions on
#' Geoscience and Remote Sensing} 43(4), 898–910.
#' \doi{10.1109/TGRS.2005.844293}
#'
#' Winter, M. E. (1999). N-FINDR: an algorithm for fast autonomous spectral
#' end-member determination in hyperspectral data. In M. R. Descour, S. S. Shen
#' (Eds.), \emph{Imaging Spectrometry V}, Proc. SPIE 3753, 266–275.
#' \doi{10.1117/12.366289}
#'
#' @examples
#' \dontrun{
#' spectra <- hsi_extract_spectra(x, n = 5000)
#' red <- stats::prcomp(spectra, center = TRUE, scale. = FALSE)
#' em <- hsi_calc_endmembers(spectra, reduction = red, n_endmembers = 5)
#'
#' hsi_calc_sam(em$spectra)
#' x_abundance <- hsi_calc_abundance(x, endmembers = em$spectra)
#' }
#'
#' @export
hsi_calc_endmembers <- function(spectra, reduction, n_endmembers) {
  # Validate inputs
  rlang::check_installed("unmixR")

  if (!is.matrix(spectra) || !is.numeric(spectra)) {
    cli::cli_abort("{.arg spectra} must be a numeric matrix.")
  }

  if (n_endmembers < 2) {
    cli::cli_abort(c(
      "{.arg n_endmembers} must be at least 2.",
      "i" = "Got {n_endmembers}."
    ))
  }

  # Project into the reduction's score space (the search space only)
  scores <- stats::predict(reduction, spectra)

  if (n_endmembers > ncol(scores)) {
    cli::cli_abort(c(
      "{.arg n_endmembers} must not exceed the number of components.",
      "i" = "Got {n_endmembers} with {ncol(scores)} component{?s}."
    ))
  }

  # VCA and N-FINDR want different dimensionalities. VCA needs p projection
  # directions, so it takes p components. N-FINDR's volume search lives in the
  # p - 1 dimensions a p-vertex simplex spans, so it takes p - 1. Both stay
  # below unmixR's internal SNR branch (the O(N^2) pixel cross-product that
  # exhausts memory on large sets).
  scores_vca <- scores[, seq_len(n_endmembers), drop = FALSE]
  scores_nfindr <- scores[, seq_len(n_endmembers - 1), drop = FALSE]

  # VCA-seeded N-FINDR
  vca_fit <- unmixR::vca(scores_vca, p = n_endmembers)
  nfindr_fit <- unmixR::nfindr(
    scores_nfindr,
    p = n_endmembers,
    indices = vca_fit$indices
  )
  indices <- nfindr_fit$indices

  # Re-read endmember spectra from the original bands (reduction-invariant)
  em_spectra <- t(spectra[indices, , drop = FALSE])
  colnames(em_spectra) <- paste0("EM", seq_len(n_endmembers))

  # Source cells of the selected pixels, when row names carry them
  locations <- if (is.null(rownames(spectra))) {
    NULL
  } else {
    stats::setNames(
      as.integer(rownames(spectra)[indices]),
      colnames(em_spectra)
    )
  }

  # Return result
  list(
    spectra = em_spectra,
    indices = indices,
    locations = locations
  )
}
