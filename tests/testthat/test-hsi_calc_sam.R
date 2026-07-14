# Test hsi_calc_sam ----
# Computes the spectral angle between every unordered pair of spectra in a
# matrix, returning a tibble of pairs and their angle in degrees.
# Key contracts:
#   - Output is a tibble with columns `a`, `b`, `angle`
#   - One row per unordered pair, no self-pairs, ascending by angle
#   - Collinear spectra give 0 degrees; orthogonal spectra give 90
#   - The angle is invariant to multiplicative scaling of a spectrum
#   - Errors when spectra is not a matrix with named columns

## Setup ----
# Spectra with known geometry: A and B are orthogonal (90 degrees apart), and
# A_scaled is A multiplied by a constant, so it is collinear with A (0 degrees).
# C is arbitrary. Bands in rows, named spectra in columns.
n_bands <- 10

set.seed(1)
test_spectra <- cbind(
  A = c(1, 0, rep(0, n_bands - 2)),
  A_scaled = c(5, 0, rep(0, n_bands - 2)),
  B = c(0, 1, rep(0, n_bands - 2)),
  C = stats::runif(n_bands)
)
rownames(test_spectra) <- as.character(seq_len(n_bands))

n_pairs <- choose(ncol(test_spectra), 2)

# Pull the angle for one named pair out of the result.
pair_angle <- function(result, first, second) {
  result$angle[result$a == first & result$b == second]
}

# ── Output structure ─────────────────────────────────────────────────────────

test_that("hsi_calc_sam returns a tibble with pair and angle columns", {
  result <- hsi_calc_sam(test_spectra)

  expect_s3_class(result, "tbl_df")
  expect_equal(names(result), c("a", "b", "angle"))
})

test_that("hsi_calc_sam returns one row per unordered pair", {
  result <- hsi_calc_sam(test_spectra)

  expect_equal(nrow(result), n_pairs)
})

test_that("hsi_calc_sam pairs a spectrum with itself never appear", {
  result <- hsi_calc_sam(test_spectra)

  expect_false(any(result$a == result$b))
})

# ── Column contracts ─────────────────────────────────────────────────────────

test_that("hsi_calc_sam orders pairs ascending by angle", {
  result <- hsi_calc_sam(test_spectra)

  expect_equal(result$angle, sort(result$angle))
})

# ── Value sanity ─────────────────────────────────────────────────────────────

test_that("hsi_calc_sam angles are finite and lie on a 0-90 degree scale", {
  # Non-negative spectra cannot be more than a right angle apart.
  result <- hsi_calc_sam(test_spectra)

  expect_true(all(is.finite(result$angle)))
  expect_true(all(result$angle >= 0 & result$angle <= 90))
})

test_that("hsi_calc_sam gives a zero angle for collinear spectra", {
  result <- hsi_calc_sam(test_spectra)

  expect_equal(pair_angle(result, "A", "A_scaled"), 0)
})

test_that("hsi_calc_sam gives a right angle for orthogonal spectra", {
  result <- hsi_calc_sam(test_spectra)

  expect_equal(pair_angle(result, "A", "B"), 90)
})

test_that("hsi_calc_sam is invariant to multiplicative scaling", {
  # The defining property: only vector direction enters, so scaling a spectrum
  # by a constant (illumination, albedo) must not move any angle.
  scaled <- test_spectra
  scaled[, "C"] <- scaled[, "C"] * 7

  expect_equal(hsi_calc_sam(scaled), hsi_calc_sam(test_spectra))
})

# ── Input validation ─────────────────────────────────────────────────────────

test_that("hsi_calc_sam errors when spectra is not a matrix", {
  expect_error(
    hsi_calc_sam(tibble::as_tibble(test_spectra)),
    "matrix with named columns"
  )
})

test_that("hsi_calc_sam errors when spectra columns are unnamed", {
  unnamed <- test_spectra
  colnames(unnamed) <- NULL

  expect_error(
    hsi_calc_sam(unnamed),
    "matrix with named columns"
  )
})
