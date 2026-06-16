# Test hsi_apply_reduction ----
# Projects a SpatRaster through a fitted reduction model (currently PCA) to a
# score raster, one layer per component, via terra::predict.
# Key contracts: nlyr(out) == ncomp(model); scores equal a direct
# stats::predict on the same model; band-count mismatch and unsupported model
# classes abort.

## Setup ----
test_reflectance <- terra::rast(
  system.file(
    package = "HSItools",
    "testdata/products/REFLECTANCE_testdata.tif"
  )
)

# Build a clean, NA-free synthetic scene on the fixture geometry. The
# REFLECTANCE fixture carries NA-prone edge bands (>= 1 NA per pixel across the
# full stack), which prcomp cannot be fit on directly; a synthetic clean stack
# keeps the recovery test exact and independent of edge-trim band positions.
template <- terra::subset(test_reflectance, 1:20)
set.seed(1)
clean_values <- matrix(
  stats::runif(terra::ncell(template) * terra::nlyr(template)),
  ncol = terra::nlyr(template)
)
test_clean <- terra::setValues(template, clean_values)
names(test_clean) <- paste0("b", seq_len(terra::nlyr(test_clean)))

train <- terra::values(test_clean)
pca_model <- stats::prcomp(train, center = TRUE, scale. = FALSE)

# ── Output type ──────────────────────────────────────────────────────────────

test_that("hsi_apply_reduction returns a SpatRaster", {
  result <- hsi_apply_reduction(x = test_clean, model = pca_model)

  expect_s4_class(result, "SpatRaster")
})

# ── Output dimensions ────────────────────────────────────────────────────────

test_that("hsi_apply_reduction returns one layer per component", {
  result <- hsi_apply_reduction(x = test_clean, model = pca_model)

  expect_equal(terra::nlyr(result), ncol(pca_model$rotation))
})

test_that("hsi_apply_reduction preserves spatial dimensions", {
  result <- hsi_apply_reduction(x = test_clean, model = pca_model)

  expect_equal(terra::nrow(result), terra::nrow(test_clean))
  expect_equal(terra::ncol(result), terra::ncol(test_clean))
})

# ── Band names ───────────────────────────────────────────────────────────────

test_that("hsi_apply_reduction names layers after model components", {
  result <- hsi_apply_reduction(x = test_clean, model = pca_model)

  expect_equal(names(result), colnames(pca_model$rotation))
})

# ── Value sanity ─────────────────────────────────────────────────────────────

test_that("hsi_apply_reduction produces only finite values", {
  result <- hsi_apply_reduction(x = test_clean, model = pca_model)
  values <- terra::values(result, na.rm = TRUE)

  expect_false(any(is.infinite(values)))
  expect_false(any(is.nan(values)))
})

test_that("hsi_apply_reduction scores match a direct predict on the model", {
  result <- hsi_apply_reduction(x = test_clean, model = pca_model)

  expected <- stats::predict(pca_model, train)
  max_abs_error <- max(abs(terra::values(result) - expected))

  expect_lte(max_abs_error, 1e-6)
})

test_that("hsi_apply_reduction passes background NA through as NA scores", {
  # Blank one cell across all bands; that cell must be NA in every score layer.
  na_scene <- test_clean
  na_scene[1] <- NA

  result <- hsi_apply_reduction(x = na_scene, model = pca_model)
  first_cell <- terra::values(result)[1, ]

  expect_true(all(is.na(first_cell)))
})

# ── File writing ─────────────────────────────────────────────────────────────

test_that("hsi_apply_reduction writes to file when filename provided", {
  temp_file <- tempfile(fileext = ".tif")

  result <- hsi_apply_reduction(
    x = test_clean,
    model = pca_model,
    filename = temp_file,
    overwrite = TRUE
  )

  expect_true(file.exists(temp_file))
  expect_s4_class(result, "SpatRaster")

  unlink(temp_file)
})

test_that("hsi_apply_reduction errors when file exists and overwrite = FALSE", {
  temp_file <- tempfile(fileext = ".tif")

  hsi_apply_reduction(
    x = test_clean,
    model = pca_model,
    filename = temp_file,
    overwrite = TRUE
  )

  expect_error(
    hsi_apply_reduction(
      x = test_clean,
      model = pca_model,
      filename = temp_file,
      overwrite = FALSE
    )
  )

  unlink(temp_file)
})

# ── Input validation ─────────────────────────────────────────────────────────

test_that("hsi_apply_reduction errors with non-SpatRaster input", {
  expect_error(hsi_apply_reduction(x = "not a raster", model = pca_model))
})

test_that("hsi_apply_reduction errors when layer count differs from model", {
  wrong_bands <- terra::subset(test_clean, 1:19)

  expect_error(
    hsi_apply_reduction(x = wrong_bands, model = pca_model),
    "wrong number of layers"
  )
})

test_that("hsi_apply_reduction errors for an unsupported model class", {
  expect_error(
    hsi_apply_reduction(x = test_clean, model = list(a = 1)),
    "not a supported reduction model"
  )
})
