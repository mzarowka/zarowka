# Test hsi_calc_endmembers ----
# Extracts endmembers from a pooled pixel table via VCA-seeded N-FINDR on a
# PCA-reduced search space.
# Key contracts: returns the documented list shape; spectra are bands x
# endmembers in reflectance space; pure planted pixels are recovered as
# endmembers; provenance flows through to locations; bad n_endmembers and
# unimplemented reduction error.

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

# Fit table with provenance: the three pure pixels are rows 1:3.
test_fit <- tibble::as_tibble(pixels) |>
  tibble::add_column(
    scene = "scene_a",
    roi = 1L,
    cell = seq_len(nrow(pixels)),
    .before = 1
  )

pure_idx <- 1:3

# ── Output structure ─────────────────────────────────────────────────────────

test_that("hsi_calc_endmembers returns the documented list components", {
  set.seed(1)
  em <- hsi_calc_endmembers(test_fit, n_endmembers = 3)

  expect_named(
    em,
    c("spectra", "indices", "locations", "model", "diagnostics")
  )
})

test_that("hsi_calc_endmembers spectra are bands x endmembers", {
  set.seed(1)
  em <- hsi_calc_endmembers(test_fit, n_endmembers = 3)

  expect_equal(nrow(em$spectra), n_bands)
  expect_equal(ncol(em$spectra), 3)
})

test_that("hsi_calc_endmembers spectra carry wavelength rownames and EM colnames", {
  set.seed(1)
  em <- hsi_calc_endmembers(test_fit, n_endmembers = 3)

  expect_equal(rownames(em$spectra), band_names)
  expect_equal(colnames(em$spectra), c("EM1", "EM2", "EM3"))
})

# ── Column contracts ─────────────────────────────────────────────────────────

test_that("hsi_calc_endmembers locations carry provenance for each endmember", {
  set.seed(1)
  em <- hsi_calc_endmembers(test_fit, n_endmembers = 3)

  expect_named(em$locations, c("endmember", "scene", "roi", "cell"))
  expect_equal(nrow(em$locations), 3)
})

test_that("hsi_calc_endmembers returns NULL locations without provenance", {
  set.seed(1)
  bare <- tibble::as_tibble(pixels)

  em <- hsi_calc_endmembers(bare, n_endmembers = 3)

  expect_null(em$locations)
})

test_that("hsi_calc_endmembers diagnostics list all unique endmember pairs", {
  set.seed(1)
  em <- hsi_calc_endmembers(test_fit, n_endmembers = 3)

  # choose(3, 2) = 3 unordered pairs
  expect_equal(nrow(em$diagnostics), 3)
  expect_named(em$diagnostics, c("a", "b", "angle"))
})

# ── Value sanity ─────────────────────────────────────────────────────────────

test_that("hsi_calc_endmembers recovers the planted pure pixels", {
  set.seed(1)
  em <- hsi_calc_endmembers(test_fit, n_endmembers = 3)

  # The three pure pixels are the simplex vertices; their cells are 1:3.
  expect_setequal(em$indices, pure_idx)
})

test_that("hsi_calc_endmembers diagnostics angles are finite and non-negative", {
  set.seed(1)
  em <- hsi_calc_endmembers(test_fit, n_endmembers = 3)

  expect_true(all(is.finite(em$diagnostics$angle)))
  expect_true(all(em$diagnostics$angle >= 0))
})

# ── Input validation ─────────────────────────────────────────────────────────

test_that("hsi_calc_endmembers errors when n_endmembers exceeds band count", {
  expect_error(
    hsi_calc_endmembers(test_fit, n_endmembers = n_bands + 1),
    "between 2 and"
  )
})

test_that("hsi_calc_endmembers errors when n_endmembers is below 2", {
  expect_error(
    hsi_calc_endmembers(test_fit, n_endmembers = 1),
    "between 2 and"
  )
})

test_that("hsi_calc_endmembers errors for the unimplemented mnf reduction", {
  expect_error(
    hsi_calc_endmembers(test_fit, n_endmembers = 3, reduction = "mnf"),
    "not implemented"
  )
})

test_that("hsi_calc_endmembers errors for an unknown reduction", {
  expect_error(
    hsi_calc_endmembers(test_fit, n_endmembers = 3, reduction = "ica")
  )
})