# Test hsi_extract_spectra ----
# Pulls pixels out of a hyperspectral raster as a plain numeric matrix, either by
# random sample (`n`) or by cell number (`cells`).
# Key contracts:
#   - Returns a matrix: pixels x bands, cell numbers as rownames, band names as
#     colnames
#   - Exactly one of `n` / `cells` must be given
#   - `n = Inf` takes every pixel; a finite `n` samples that many
#   - `cells` fetches the requested pixels in the caller's order
#   - Duplicate cells warn and are de-duplicated
#   - Fully-NA (background) pixels are dropped

## Setup ----
test_reflectance <- terra::rast(
  system.file(
    package = "HSItools",
    "testdata/products/REFLECTANCE_testdata.tif"
  )
)

n_cells <- terra::ncell(test_reflectance)
n_bands <- terra::nlyr(test_reflectance)

# ── Output type ──────────────────────────────────────────────────────────────

test_that("hsi_extract_spectra returns a numeric matrix", {
  spectra <- hsi_extract_spectra(test_reflectance, n = 10)

  expect_true(is.matrix(spectra))
  expect_true(is.numeric(spectra))
})

# ── Output structure ─────────────────────────────────────────────────────────

test_that("hsi_extract_spectra keeps one column per band", {
  spectra <- hsi_extract_spectra(test_reflectance, n = 10)

  expect_equal(ncol(spectra), n_bands)
})

test_that("hsi_extract_spectra column names are the band names of x", {
  spectra <- hsi_extract_spectra(test_reflectance, n = 10)

  expect_equal(colnames(spectra), terra::names(test_reflectance))
})

test_that("hsi_extract_spectra row names are cell numbers indexing back into x", {
  spectra <- hsi_extract_spectra(test_reflectance, n = 10)

  cells <- as.integer(rownames(spectra))

  expect_false(anyNA(cells))
  expect_true(all(cells >= 1 & cells <= n_cells))
})

# ── Selection modes ──────────────────────────────────────────────────────────

test_that("hsi_extract_spectra n samples that many pixels", {
  spectra <- hsi_extract_spectra(test_reflectance, n = 20)

  expect_equal(nrow(spectra), 20)
})

test_that("hsi_extract_spectra n = Inf takes every pixel", {
  spectra <- hsi_extract_spectra(test_reflectance, n = Inf)

  expect_equal(nrow(spectra), n_cells)
})

test_that("hsi_extract_spectra cells fetches the requested pixels in order", {
  requested <- c(5L, 1L, 9L)

  spectra <- hsi_extract_spectra(test_reflectance, cells = requested)

  expect_equal(nrow(spectra), length(requested))
  expect_equal(rownames(spectra), as.character(requested))
})

test_that("hsi_extract_spectra cells returns the values held at those cells", {
  requested <- c(5L, 1L, 9L)

  spectra <- hsi_extract_spectra(test_reflectance, cells = requested)

  expected <- as.matrix(test_reflectance[requested])

  expect_equal(unname(spectra), unname(expected))
})

test_that("hsi_extract_spectra warns and de-duplicates repeated cells", {
  expect_warning(
    spectra <- hsi_extract_spectra(test_reflectance, cells = c(1L, 1L, 2L)),
    regexp = "Duplicate"
  )

  expect_equal(rownames(spectra), c("1", "2"))
})

test_that("hsi_extract_spectra warns when n exceeds the cell count", {
  # terra clamps an oversized sample rather than erroring; n = Inf is the
  # supported way to ask for every pixel.
  expect_warning(
    hsi_extract_spectra(test_reflectance, n = n_cells + 1),
    regexp = "sample size"
  )
})

# ── Input validation ─────────────────────────────────────────────────────────

test_that("hsi_extract_spectra errors with non-SpatRaster input", {
  expect_error(
    hsi_extract_spectra("not a raster", n = 10),
    "SpatRaster"
  )
})

test_that("hsi_extract_spectra errors when neither n nor cells is given", {
  expect_error(
    hsi_extract_spectra(test_reflectance),
    "Choose which pixels"
  )
})

test_that("hsi_extract_spectra errors when both n and cells are given", {
  expect_error(
    hsi_extract_spectra(test_reflectance, n = 10, cells = 1:3),
    "mutually exclusive"
  )
})

test_that("hsi_extract_spectra errors when n is not a single positive number", {
  expect_error(
    hsi_extract_spectra(test_reflectance, n = 0),
    "single positive number"
  )

  expect_error(
    hsi_extract_spectra(test_reflectance, n = c(1, 2)),
    "single positive number"
  )
})

test_that("hsi_extract_spectra errors when cells fall outside x", {
  expect_error(
    hsi_extract_spectra(test_reflectance, cells = c(1L, n_cells + 1L)),
    "outside"
  )
})
