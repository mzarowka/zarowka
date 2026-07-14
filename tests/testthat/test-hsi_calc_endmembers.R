# Test hsi_calc_endmembers ----
# Extracts endmembers from a pixel matrix via VCA-seeded N-FINDR, searching in
# the score space of a caller-fitted reduction.
# Key contracts:
#   - Takes a numeric matrix (pixels x bands) and a fitted reduction model
#   - Returns list(spectra, indices, locations)
#   - `spectra` is bands x endmembers, in the original band space
#   - Pure planted pixels are recovered as the simplex vertices
#   - `locations` carries source cell numbers from the matrix rownames, or is
#     NULL when there are none
#   - Bad n_endmembers errors

## Setup ----
skip_if_not_installed("unmixR")

# Three planted endmember spectra and a pool of pixels that are convex mixtures
# of them, with the three pure pixels included. VCA-seeded N-FINDR should pick
# the simplex vertices, i.e. the three pure pixels.
n_bands <- 40
set.seed(1)
planted <- matrix(stats::runif(n_bands * 3), nrow = 3) # endmembers in rows

n_mix <- 200
weights <- matrix(stats::runif(n_mix * 3), ncol = 3)
weights <- weights / rowSums(weights) # convex (interior) mixtures
mixed <- weights %*% planted

# Pure pixels first, then interior mixtures.
pixels <- rbind(planted, mixed)
band_names <- as.character(round(seq(1000, 2500, length.out = n_bands), 1))
colnames(pixels) <- band_names

# The pure pixels are rows 1:3.
pure_idx <- 1:3

# Cell numbers as rownames, the way hsi_extract_spectra() hands them over.
test_spectra <- pixels
rownames(test_spectra) <- seq_len(nrow(test_spectra))

# The caller fits the reduction and passes it in.
test_reduction <- stats::prcomp(test_spectra, center = TRUE, scale. = FALSE)

# ── Output structure ─────────────────────────────────────────────────────────

test_that("hsi_calc_endmembers returns the documented list components", {
  set.seed(1)
  em <- hsi_calc_endmembers(test_spectra, test_reduction, n_endmembers = 3)

  expect_type(em, "list")
  expect_named(em, c("spectra", "indices", "locations"))
})

test_that("hsi_calc_endmembers spectra are bands x endmembers", {
  set.seed(1)
  em <- hsi_calc_endmembers(test_spectra, test_reduction, n_endmembers = 3)

  expect_equal(nrow(em$spectra), n_bands)
  expect_equal(ncol(em$spectra), 3)
})

test_that("hsi_calc_endmembers spectra carry band rownames and EM colnames", {
  set.seed(1)
  em <- hsi_calc_endmembers(test_spectra, test_reduction, n_endmembers = 3)

  expect_equal(rownames(em$spectra), band_names)
  expect_equal(colnames(em$spectra), c("EM1", "EM2", "EM3"))
})

# ── Endmember recovery ───────────────────────────────────────────────────────

test_that("hsi_calc_endmembers recovers the planted pure pixels", {
  set.seed(1)
  em <- hsi_calc_endmembers(test_spectra, test_reduction, n_endmembers = 3)

  expect_setequal(em$indices, pure_idx)
})

test_that("hsi_calc_endmembers spectra match the planted spectra it selected", {
  set.seed(1)
  em <- hsi_calc_endmembers(test_spectra, test_reduction, n_endmembers = 3)

  # Columns come back in the search's order, so compare as unordered sets of
  # spectra: every returned endmember is one of the planted ones.
  returned <- unname(as.data.frame(em$spectra))
  expected <- unname(as.data.frame(t(planted)))

  expect_setequal(as.list(returned), as.list(expected))
})

# ── Locations ────────────────────────────────────────────────────────────────

test_that("hsi_calc_endmembers locations are cell numbers named by endmember", {
  set.seed(1)
  em <- hsi_calc_endmembers(test_spectra, test_reduction, n_endmembers = 3)

  expect_type(em$locations, "integer")
  expect_named(em$locations, c("EM1", "EM2", "EM3"))
  expect_equal(
    unname(em$locations),
    as.integer(rownames(test_spectra)[em$indices])
  )
})

test_that("hsi_calc_endmembers locations are NULL without cell rownames", {
  bare <- pixels
  rownames(bare) <- NULL

  set.seed(1)
  em <- hsi_calc_endmembers(bare, test_reduction, n_endmembers = 3)

  expect_null(em$locations)
})

# ── Input validation ─────────────────────────────────────────────────────────

test_that("hsi_calc_endmembers errors when spectra is not a numeric matrix", {
  expect_error(
    hsi_calc_endmembers(
      tibble::as_tibble(pixels),
      test_reduction,
      n_endmembers = 3
    ),
    "numeric matrix"
  )
})

test_that("hsi_calc_endmembers errors when n_endmembers is below 2", {
  expect_error(
    hsi_calc_endmembers(test_spectra, test_reduction, n_endmembers = 1),
    "at least 2"
  )
})

test_that("hsi_calc_endmembers errors when n_endmembers exceeds the components", {
  # The reduction of a 40-band matrix yields 40 components.
  expect_error(
    hsi_calc_endmembers(
      test_spectra,
      test_reduction,
      n_endmembers = n_bands + 1
    ),
    "must not exceed"
  )
})
