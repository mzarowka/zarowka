# Test hsi_check_signal ----
# Marks pixels below the dark-current detection limit, returning a 0/1
# SpatRaster: one layer per band, or a single collapsed layer.
# Key contracts:
#   - Output is a SpatRaster of 0/1 values, NA preserved
#   - collapse = FALSE: one layer per band, band names of x preserved
#   - collapse = TRUE: a single layer named "no_signal"
#   - The floor is measured from darkref as mean + k * sd, per band
#   - The comparison is inclusive: a pixel at exactly the floor is flagged
#   - Collapsing flags a pixel below floor in at least `fraction` of bands
#   - NA propagates through the collapse rather than reading as having signal
#   - darkref must match the bands of x, but not its spatial dimensions
#   - Writes to file when filename is given

## Setup ----
# Raw digital numbers with the matched dark reference from the same session:
# the processing level this function is meant for.
test_capture <- terra::rast(
  system.file(
    package = "HSItools",
    "testdata/capture/testdata.tif"
  )
)

test_dark <- terra::rast(
  system.file(
    package = "HSItools",
    "testdata/capture/DARKREF_testdata.tif"
  )
)

# The floor the function computes internally, recomputed here so value tests can
# place synthetic pixels relative to it.
dark_stats <- terra::global(test_dark, c("mean", "sd"), na.rm = TRUE)

test_floor <- dark_stats$mean + 3 * dark_stats$sd

test_bands <- terra::nlyr(test_capture)

# Derived rasters are built with terra::setValues(), which returns a new raster.
# SpatRaster is not deep-copied by `<-`, so mutating in place would corrupt the
# shared fixture. The capture sits entirely above floor, so every below-floor
# case has to be constructed.

# Pixel 1 sitting at the dark mean: below floor in every band.
dark_mean_values <- terra::values(test_capture)
dark_mean_values[1, ] <- dark_stats$mean
test_dark_mean <- terra::setValues(test_capture, dark_mean_values)

# Pixel 1 sitting exactly on the detection limit in every band.
floor_values <- terra::values(test_capture)
floor_values[1, ] <- test_floor
test_at_floor <- terra::setValues(test_capture, floor_values)

# The collapse boundary at fraction = 0.9: ceiling(0.9 * 101) = 91 bands.
below_91 <- terra::values(test_capture)
below_91[1, seq_len(91)] <- 0
test_below_91 <- terra::setValues(test_capture, below_91)

below_90 <- terra::values(test_capture)
below_90[1, seq_len(90)] <- 0
test_below_90 <- terra::setValues(test_capture, below_90)

# Pixel 1 below floor everywhere except band 2, which is NA. Collapsing must not
# report it as flagged on incomplete evidence, nor as clean.
na_values <- terra::values(test_capture)
na_values[1, ] <- 0
na_values[1, 2] <- NA_real_
test_na <- terra::setValues(test_capture, na_values)

# A dark reference whose first band has no variance at all.
constant_dark_values <- terra::values(test_dark)
constant_dark_values[, 1] <- 5
test_dark_constant <- terra::setValues(test_dark, constant_dark_values)

# ── Output type ──────────────────────────────────────────────────────────────

test_that("hsi_check_signal returns a SpatRaster", {
  result <- hsi_check_signal(x = test_capture, darkref = test_dark)

  expect_s4_class(result, "SpatRaster")
})

test_that("hsi_check_signal returns only 0, 1 and NA", {
  result <- hsi_check_signal(x = test_dark_mean, darkref = test_dark)

  expect_true(all(terra::values(result) %in% c(0, 1, NA)))

  collapsed <- hsi_check_signal(
    x = test_dark_mean,
    darkref = test_dark,
    collapse = TRUE
  )

  expect_true(all(terra::values(collapsed) %in% c(0, 1, NA)))
})

# ── Output dimensions ────────────────────────────────────────────────────────

test_that("hsi_check_signal returns one layer per band by default", {
  result <- hsi_check_signal(x = test_capture, darkref = test_dark)

  expect_equal(terra::nlyr(result), terra::nlyr(test_capture))
  expect_equal(terra::nrow(result), terra::nrow(test_capture))
  expect_equal(terra::ncol(result), terra::ncol(test_capture))
})

test_that("hsi_check_signal collapse reduces the mask to a single layer", {
  result <- hsi_check_signal(
    x = test_capture,
    darkref = test_dark,
    collapse = TRUE
  )

  expect_equal(terra::nlyr(result), 1L)
  expect_equal(terra::nrow(result), terra::nrow(test_capture))
  expect_equal(terra::ncol(result), terra::ncol(test_capture))
})

test_that("hsi_check_signal accepts a darkref with different spatial dimensions", {
  # A DARKREF capture has its own row count; only the bands have to match.
  expect_false(terra::nrow(test_dark) == terra::nrow(test_capture))

  expect_s4_class(
    hsi_check_signal(x = test_capture, darkref = test_dark),
    "SpatRaster"
  )
})

# ── Band names ───────────────────────────────────────────────────────────────

test_that("hsi_check_signal preserves the band names of x", {
  result <- hsi_check_signal(x = test_capture, darkref = test_dark)

  expect_equal(terra::names(result), terra::names(test_capture))
})

test_that("hsi_check_signal names the collapsed layer no_signal", {
  result <- hsi_check_signal(
    x = test_capture,
    darkref = test_dark,
    collapse = TRUE
  )

  expect_equal(terra::names(result), "no_signal")
})

# ── Value sanity ─────────────────────────────────────────────────────────────

test_that("hsi_check_signal marks nothing when every pixel clears the floor", {
  result <- hsi_check_signal(x = test_capture, darkref = test_dark)

  expect_equal(sum(terra::values(result)), 0)
})

test_that("hsi_check_signal flags a pixel sitting at the dark mean", {
  result <- hsi_check_signal(x = test_dark_mean, darkref = test_dark)

  expect_true(all(terra::values(result)[1, ] == 1))

  collapsed <- hsi_check_signal(
    x = test_dark_mean,
    darkref = test_dark,
    collapse = TRUE
  )

  expect_true(as.vector(terra::values(collapsed)[1]) == 1)
})

test_that("hsi_check_signal treats a pixel at exactly the floor as below it", {
  # The comparison is inclusive: a value at the detection limit has not
  # demonstrably cleared it.
  result <- hsi_check_signal(x = test_at_floor, darkref = test_dark)

  expect_true(all(terra::values(result)[1, ] == 1))
})

test_that("hsi_check_signal flags no fewer cells as k rises", {
  # A larger noise multiplier raises the floor, so the mask can only grow.
  strict <- hsi_check_signal(x = test_capture, darkref = test_dark, k = 3)

  loose <- hsi_check_signal(x = test_capture, darkref = test_dark, k = 1e6)

  expect_gte(sum(terra::values(loose)), sum(terra::values(strict)))
})

# ── Collapse fraction ────────────────────────────────────────────────────────

test_that("hsi_check_signal collapses a pixel meeting the fraction threshold", {
  # 91 of 101 bands is 0.901, which clears the 0.9 default.
  result <- hsi_check_signal(
    x = test_below_91,
    darkref = test_dark,
    collapse = TRUE
  )

  expect_true(as.vector(terra::values(result)[1]) == 1)
})

test_that("hsi_check_signal leaves a pixel below the fraction threshold clean", {
  # 90 of 101 bands is 0.891, which does not.
  result <- hsi_check_signal(
    x = test_below_90,
    darkref = test_dark,
    collapse = TRUE
  )

  expect_true(as.vector(terra::values(result)[1]) == 0)
})

# ── NA handling ──────────────────────────────────────────────────────────────

test_that("hsi_check_signal collapse does not resolve a pixel with an NA band", {
  # na.rm = FALSE throughout: an unknown band cannot settle a pixel either way.
  result <- hsi_check_signal(
    x = test_na,
    darkref = test_dark,
    collapse = TRUE
  )

  expect_true(is.na(terra::values(result)[1]))
})

# ── Warnings ─────────────────────────────────────────────────────────────────

test_that("hsi_check_signal warns when a darkref band has zero variance", {
  # The k-sigma margin vanishes there and the floor degenerates to the mean.
  expect_warning(
    hsi_check_signal(x = test_capture, darkref = test_dark_constant),
    class = "hsitools_warning"
  )
})

test_that("hsi_check_signal warns rather than errors on mismatched band names", {
  # Same stance as hsi_calc_reflectance(): band count is fatal, naming is not.
  # terra::deepcopy() is required: set.names() mutates through the reference, so
  # renaming an alias would corrupt the shared fixture for every later test.
  renamed_dark <- terra::deepcopy(test_dark)
  terra::set.names(renamed_dark, paste0("band_", seq_len(test_bands)))

  expect_warning(
    hsi_check_signal(x = test_capture, darkref = renamed_dark),
    class = "hsitools_warning"
  )
})

test_that("hsi_check_signal warns when a darkref band has no valid dark data", {
  # An all-NA dark band leaves the floor undefined; with na.rm = FALSE the whole
  # collapsed mask goes NA, so silence would read as a blank result.
  missing_dark_values <- terra::values(test_dark)
  missing_dark_values[, 1] <- NA_real_
  test_dark_missing <- terra::setValues(test_dark, missing_dark_values)

  expect_warning(
    hsi_check_signal(x = test_capture, darkref = test_dark_missing),
    "no valid dark data",
    class = "hsitools_warning"
  )
})

# ── File writing ─────────────────────────────────────────────────────────────

test_that("hsi_check_signal writes to file when filename provided", {
  temp_file <- file.path(tempdir(), "test_signal.tif")
  on.exit(unlink(temp_file), add = TRUE)

  result <- hsi_check_signal(
    x = test_capture,
    darkref = test_dark,
    collapse = TRUE,
    filename = temp_file,
    overwrite = TRUE
  )

  expect_true(file.exists(temp_file))
  expect_s4_class(result, "SpatRaster")
  expect_equal(terra::names(terra::rast(temp_file)), "no_signal")
})

test_that("hsi_check_signal errors when file exists and overwrite is FALSE", {
  temp_file <- file.path(tempdir(), "test_signal_overwrite.tif")
  on.exit(unlink(temp_file), add = TRUE)

  hsi_check_signal(
    x = test_capture,
    darkref = test_dark,
    filename = temp_file,
    overwrite = TRUE
  )

  expect_error(
    hsi_check_signal(
      x = test_capture,
      darkref = test_dark,
      filename = temp_file,
      overwrite = FALSE
    )
  )
})

# ── Input validation ─────────────────────────────────────────────────────────

test_that("hsi_check_signal validates filename and overwrite", {
  expect_write_tail_validated(
    hsi_check_signal,
    list(x = test_capture, darkref = test_dark)
  )
})

test_that("hsi_check_signal errors with non-SpatRaster input", {
  expect_error(
    hsi_check_signal(x = "not a raster", darkref = test_dark),
    class = "hsitools_error"
  )

  expect_error(
    hsi_check_signal(x = test_capture, darkref = "not a raster"),
    class = "hsitools_error"
  )
})

test_that("hsi_check_signal errors when darkref is absent", {
  # The floor is measured, never assumed, so there is nothing to fall back on.
  expect_error(
    hsi_check_signal(x = test_capture),
    "absent",
    class = "rlang_error"
  )
})

test_that("hsi_check_signal errors when darkref has a different band count", {
  expect_error(
    hsi_check_signal(x = test_capture, darkref = test_dark[[1:50]]),
    "same number of bands",
    class = "hsitools_error"
  )
})

test_that("hsi_check_signal errors when k is not a positive finite number", {
  expect_error(
    hsi_check_signal(x = test_capture, darkref = test_dark, k = "three"),
    class = "hsitools_error"
  )

  expect_error(
    hsi_check_signal(x = test_capture, darkref = test_dark, k = -1),
    class = "hsitools_error"
  )

  expect_error(
    hsi_check_signal(x = test_capture, darkref = test_dark, k = Inf),
    "finite",
    class = "hsitools_error"
  )

  # NaN slips past a plain sign test (NaN <= 0 is NA), so it gets its own
  # assertion: the abort must stay a hsitools_error, never a bare condition
  # error. Guarded upstream by HSItools check_numeric(positive = TRUE).
  expect_error(
    hsi_check_signal(x = test_capture, darkref = test_dark, k = NaN),
    class = "hsitools_error"
  )
})

test_that("hsi_check_signal errors when fraction is outside (0, 1]", {
  expect_error(
    hsi_check_signal(x = test_capture, darkref = test_dark, fraction = 0),
    class = "hsitools_error"
  )

  expect_error(
    hsi_check_signal(x = test_capture, darkref = test_dark, fraction = 1.5),
    class = "hsitools_error"
  )

  expect_error(
    hsi_check_signal(x = test_capture, darkref = test_dark, fraction = NaN),
    class = "hsitools_error"
  )
})

test_that("hsi_check_signal errors when collapse is not a logical scalar", {
  expect_error(
    hsi_check_signal(
      x = test_capture,
      darkref = test_dark,
      collapse = "yes"
    ),
    class = "rlang_error"
  )
})

test_that("hsi_check_signal errors when an unused argument is passed without filename", {
  expect_error(
    hsi_check_signal(
      x = test_capture,
      darkref = test_dark,
      bogus_arg = 1
    ),
    "not used",
    class = "hsitools_error"
  )
})

test_that("hsi_check_signal aborts with informative messages", {
  expect_snapshot(
    hsi_check_signal(x = test_capture, darkref = test_dark[[1:50]]),
    error = TRUE
  )

  expect_snapshot(
    hsi_check_signal(x = test_capture, darkref = test_dark, k = Inf),
    error = TRUE
  )

  expect_snapshot(
    hsi_check_signal(x = test_capture, darkref = test_dark, fraction = 1.5),
    error = TRUE
  )
})
