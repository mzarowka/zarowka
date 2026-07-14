# Test hsi_calc_snr ----
# Computes per-band mean, standard deviation and their ratio over the full
# raster, returning a four-column tibble with one row per band.
# Key contracts:
#   - Output is a tibble with exactly `wavelength`, `mean`, `sd` and `snr`
#   - One row per band (nlyr rows)
#   - `wavelength` matches input band names; `snr` is `mean / sd`
#   - A zero-variance band yields Inf or NaN and warns, naming the wavelengths
#   - `na.rm` is passed through to the band statistics
#   - Errors when band names are not parseable as numeric wavelengths

## Setup ----
test_reflectance <- terra::rast(
  system.file(
    package = "HSItools",
    "testdata/products/REFLECTANCE_testdata.tif"
  )
)

# Degenerate rasters are derived with terra::setValues(), which returns a new
# raster. SpatRaster is not deep-copied by `<-`, so mutating a band in place
# would corrupt the shared fixture.

# Band 3 constant and non-zero: sd 0, mean 5, so snr is Inf.
constant_values <- terra::values(test_reflectance)
constant_values[, 3] <- 5
test_constant <- terra::setValues(test_reflectance, constant_values)

# Band 5 constant and zero: sd 0, mean 0, so snr is NaN.
zero_values <- terra::values(test_reflectance)
zero_values[, 5] <- 0
test_zero <- terra::setValues(test_reflectance, zero_values)

# A single NA cell in band 1, for the na.rm contract.
na_values <- terra::values(test_reflectance)
na_values[1, 1] <- NA_real_
test_na <- terra::setValues(test_reflectance, na_values)

# ── Output type ──────────────────────────────────────────────────────────────

test_that("hsi_calc_snr returns a tibble", {
  result <- hsi_calc_snr(x = test_reflectance)

  expect_s3_class(result, "tbl_df")
})

# ── Output structure ─────────────────────────────────────────────────────────

test_that("hsi_calc_snr output columns are named wavelength, mean, sd and snr", {
  result <- hsi_calc_snr(x = test_reflectance)

  expect_equal(names(result), c("wavelength", "mean", "sd", "snr"))
})

test_that("hsi_calc_snr output has one row per band", {
  result <- hsi_calc_snr(x = test_reflectance)

  expect_equal(nrow(result), terra::nlyr(test_reflectance))
})

# ── Column contracts ─────────────────────────────────────────────────────────

test_that("hsi_calc_snr wavelength values match input band names", {
  result <- hsi_calc_snr(x = test_reflectance)

  expected_wavelengths <- as.numeric(terra::names(test_reflectance))

  expect_equal(result$wavelength, expected_wavelengths)
})

test_that("hsi_calc_snr computes snr as mean divided by sd", {
  result <- hsi_calc_snr(x = test_reflectance)

  expect_equal(result$snr, result$mean / result$sd)
})

# ── Value sanity ─────────────────────────────────────────────────────────────

test_that("hsi_calc_snr returns finite statistics for a well-behaved raster", {
  result <- hsi_calc_snr(x = test_reflectance)

  expect_false(any(is.infinite(result$snr)))
  expect_false(any(is.nan(result$snr)))
  expect_true(all(result$sd > 0))
})

# ── Zero-variance bands ──────────────────────────────────────────────────────

test_that("hsi_calc_snr returns Inf or NaN for a zero-variance band", {
  # Non-zero mean divides by zero; zero mean is 0 / 0.
  result_constant <- suppressWarnings(hsi_calc_snr(x = test_constant))
  result_zero <- suppressWarnings(hsi_calc_snr(x = test_zero))

  expect_true(is.infinite(result_constant$snr[3]))
  expect_true(is.nan(result_zero$snr[5]))
})

test_that("hsi_calc_snr warns only when a band has zero variance", {
  expect_warning(
    hsi_calc_snr(x = test_constant),
    regexp = "zero variance",
    class = "hsitools_warning"
  )

  expect_no_warning(hsi_calc_snr(x = test_reflectance))
})

test_that("hsi_calc_snr names the wavelengths of zero-variance bands", {
  expected_wavelength <- as.numeric(terra::names(test_constant))[3]

  expect_warning(
    hsi_calc_snr(x = test_constant),
    regexp = as.character(expected_wavelength),
    class = "hsitools_warning"
  )
})

# ── na.rm argument ───────────────────────────────────────────────────────────

test_that("hsi_calc_snr na.rm is passed through to the band statistics", {
  result_kept <- hsi_calc_snr(x = test_na, na.rm = FALSE)
  result_removed <- hsi_calc_snr(x = test_na, na.rm = TRUE)

  # The NA cell poisons its band's statistics when NA values are kept.
  expect_true(is.na(result_kept$mean[1]))
  expect_true(is.na(result_kept$sd[1]))
  expect_true(is.na(result_kept$snr[1]))

  expect_true(all(is.finite(result_removed$snr)))
})

# ── Input validation ─────────────────────────────────────────────────────────

test_that("hsi_calc_snr errors with non-SpatRaster input", {
  expect_error(
    hsi_calc_snr(x = "not a raster")
  )
})

test_that("hsi_calc_snr errors when band names are not numeric wavelengths", {
  non_numeric <- terra::deepcopy(test_reflectance)
  names(non_numeric) <- paste0("band_", seq_len(terra::nlyr(non_numeric)))

  expect_error(
    hsi_calc_snr(x = non_numeric),
    "numeric wavelengths",
    class = "hsitools_error"
  )
})

test_that("hsi_calc_snr errors when na.rm is not a logical scalar", {
  expect_error(
    hsi_calc_snr(x = test_reflectance, na.rm = "yes"),
    class = "rlang_error"
  )
})
