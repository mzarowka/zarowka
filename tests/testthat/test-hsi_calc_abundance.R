# Test hsi_calc_abundance ----
# Unmixes a hyperspectral raster into per-endmember abundance layers via
# per-pixel non-negative least squares.
# Key contracts: one output layer per endmember; layer names come from the
# endmember columns; abundances recover exactly for noiseless linear mixtures
# and are never negative; band-count mismatch errors.

## Setup ----
test_reflectance <- terra::rast(
  system.file(
    package = "HSItools",
    "testdata/products/REFLECTANCE_testdata.tif"
  )
)

# Three synthetic endmembers spanning the fixture's band count. Distinct,
# well-conditioned spectra so the linear system is solvable.
n_bands <- terra::nlyr(test_reflectance)
set.seed(1)
test_endmembers <- matrix(
  stats::runif(n_bands * 3),
  nrow = n_bands,
  ncol = 3,
  dimnames = list(NULL, c("EM1", "EM2", "EM3"))
)

# A raster built as a KNOWN linear mixture of those endmembers, so the true
# abundances are recoverable exactly. Each pixel gets a random non-negative
# abundance vector; the spectrum is endmembers %*% abundance.
true_abundance <- matrix(
  stats::runif(terra::ncell(test_reflectance) * 3),
  ncol = 3
)
mixed_values <- true_abundance %*% t(test_endmembers)
test_mixture <- terra::setValues(
  terra::rast(test_reflectance, nlyrs = n_bands),
  mixed_values
)

# ── Output type ──────────────────────────────────────────────────────────────

test_that("hsi_calc_abundance returns a SpatRaster", {
  result <- hsi_calc_abundance(test_reflectance, test_endmembers)

  expect_s4_class(result, "SpatRaster")
})

# ── Output dimensions ────────────────────────────────────────────────────────

test_that("hsi_calc_abundance returns one layer per endmember", {
  result <- hsi_calc_abundance(test_reflectance, test_endmembers)

  expect_equal(terra::nlyr(result), ncol(test_endmembers))
})

test_that("hsi_calc_abundance preserves spatial dimensions", {
  result <- hsi_calc_abundance(test_reflectance, test_endmembers)

  expect_equal(terra::nrow(result), terra::nrow(test_reflectance))
  expect_equal(terra::ncol(result), terra::ncol(test_reflectance))
})

# ── Band names ───────────────────────────────────────────────────────────────

test_that("hsi_calc_abundance takes layer names from endmember columns", {
  result <- hsi_calc_abundance(test_reflectance, test_endmembers)

  expect_equal(names(result), colnames(test_endmembers))
})

test_that("hsi_calc_abundance falls back to EM names for unnamed endmembers", {
  unnamed <- test_endmembers
  colnames(unnamed) <- NULL

  result <- hsi_calc_abundance(test_reflectance, unnamed)

  expect_equal(names(result), c("EM1", "EM2", "EM3"))
})

# ── Value sanity ─────────────────────────────────────────────────────────────

test_that("hsi_calc_abundance recovers known abundances for a noiseless mixture", {
  result <- hsi_calc_abundance(test_mixture, test_endmembers)

  recovered <- terra::values(result)
  max_abs_error <- max(abs(recovered - true_abundance))

  # Exact linear system, and the planted abundances are non-negative, so NNLS
  # is unconstrained here: only floating-point error should remain.
  expect_lte(max_abs_error, 1e-6)
})

test_that("hsi_calc_abundance produces only non-negative abundances", {
  result <- hsi_calc_abundance(test_reflectance, test_endmembers)
  values <- terra::values(result, na.rm = TRUE)

  expect_true(all(values >= 0))
})

test_that("hsi_calc_abundance produces only finite values", {
  result <- hsi_calc_abundance(test_reflectance, test_endmembers)
  values <- terra::values(result, na.rm = TRUE)

  expect_false(any(is.infinite(values)))
  expect_false(any(is.nan(values)))
})

# ── File writing ─────────────────────────────────────────────────────────────

test_that("hsi_calc_abundance writes to file when filename provided", {
  temp_file <- tempfile(fileext = ".tif")

  result <- hsi_calc_abundance(
    test_reflectance,
    test_endmembers,
    filename = temp_file,
    overwrite = TRUE
  )

  expect_true(file.exists(temp_file))
  expect_s4_class(result, "SpatRaster")

  unlink(temp_file)
})

test_that("hsi_calc_abundance errors when file exists and overwrite = FALSE", {
  temp_file <- tempfile(fileext = ".tif")

  hsi_calc_abundance(
    test_reflectance,
    test_endmembers,
    filename = temp_file,
    overwrite = TRUE
  )

  expect_error(
    hsi_calc_abundance(
      test_reflectance,
      test_endmembers,
      filename = temp_file,
      overwrite = FALSE
    )
  )

  unlink(temp_file)
})

# ── Input validation ─────────────────────────────────────────────────────────

test_that("hsi_calc_abundance errors with non-SpatRaster input", {
  expect_error(hsi_calc_abundance("not a raster", test_endmembers))
})

test_that("hsi_calc_abundance errors when endmember rows do not match layers", {
  short_endmembers <- test_endmembers[1:(n_bands - 1), , drop = FALSE]

  expect_error(
    hsi_calc_abundance(test_reflectance, short_endmembers),
    "one row per layer"
  )
})

test_that("hsi_calc_abundance errors when an unused argument is passed without filename", {
  expect_error(
    hsi_calc_abundance(test_reflectance, test_endmembers, method = "fcls"),
    "not used",
    class = "hsitools_error"
  )
})
