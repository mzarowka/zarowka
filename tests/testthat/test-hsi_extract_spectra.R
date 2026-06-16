# Test hsi_extract_spectra ----
# Extracts a pixel-by-band fit table from a hyperspectral raster, optionally
# restricted to ROI polygons and/or randomly sampled.
# Key contracts: reserved provenance columns lead the table; cell numbers map
# back to x; the four roi/n modes behave as documented; band columns are
# preserved; bad n errors.

## Setup ----
test_reflectance <- terra::rast(
  system.file(
    package = "HSItools",
    "testdata/products/REFLECTANCE_testdata.tif"
  )
)

# A single ROI polygon covering the centre of the 9x9 scene.
test_roi <- terra::as.polygons(terra::ext(test_reflectance) * 0.5)
terra::crs(test_roi) <- terra::crs(test_reflectance)

n_cells <- terra::ncell(test_reflectance)
n_bands <- terra::nlyr(test_reflectance)

# ── Output structure ─────────────────────────────────────────────────────────

test_that("hsi_extract_spectra leads with reserved provenance columns", {
  fit <- hsi_extract_spectra(test_reflectance, scene = "s")

  expect_equal(names(fit)[1:3], c("scene", "roi", "cell"))
})

test_that("hsi_extract_spectra keeps one column per band", {
  fit <- hsi_extract_spectra(test_reflectance, scene = "s")

  band_cols <- setdiff(names(fit), c("scene", "roi", "cell"))
  expect_equal(length(band_cols), n_bands)
})

test_that("hsi_extract_spectra band columns keep wavelength names", {
  fit <- hsi_extract_spectra(test_reflectance, scene = "s")

  band_cols <- setdiff(names(fit), c("scene", "roi", "cell"))
  expect_equal(band_cols, names(test_reflectance))
})

# ── Column contracts ─────────────────────────────────────────────────────────

test_that("hsi_extract_spectra stamps the scene identifier", {
  fit <- hsi_extract_spectra(test_reflectance, scene = "scene_a")

  expect_true(all(fit$scene == "scene_a"))
})

test_that("hsi_extract_spectra cell numbers index back into x", {
  fit <- hsi_extract_spectra(test_reflectance, scene = "s")

  # Re-reading x at the reported cells must reproduce the band values.
  reread <- as.matrix(test_reflectance[fit$cell])
  extracted <- as.matrix(fit[setdiff(names(fit), c("scene", "roi", "cell"))])

  expect_equal(unname(extracted), unname(reread))
})

# ── Extraction modes ─────────────────────────────────────────────────────────

test_that("hsi_extract_spectra with neither roi nor n returns all pixels", {
  expect_message(
    fit <- hsi_extract_spectra(test_reflectance, scene = "s"),
    "all"
  )

  expect_equal(nrow(fit), n_cells)
  expect_true(all(is.na(fit$roi)))
})

test_that("hsi_extract_spectra with n only samples that many whole-scene pixels", {
  set.seed(1)
  fit <- hsi_extract_spectra(test_reflectance, n = 20, scene = "s")

  expect_equal(nrow(fit), 20)
  expect_true(all(is.na(fit$roi)))
})

test_that("hsi_extract_spectra with roi only returns pixels carrying a polygon id", {
  fit <- hsi_extract_spectra(test_reflectance, roi = test_roi, scene = "s")

  expect_true(nrow(fit) > 0)
  expect_true(all(!is.na(fit$roi)))
  expect_true(nrow(fit) < n_cells) # the ROI covers part of the scene
})

test_that("hsi_extract_spectra with roi and n samples within the ROI", {
  set.seed(1)
  full <- hsi_extract_spectra(test_reflectance, roi = test_roi, scene = "s")
  sampled <- hsi_extract_spectra(
    test_reflectance,
    roi = test_roi,
    n = 3,
    scene = "s"
  )

  expect_equal(nrow(sampled), 3)
  expect_true(all(sampled$cell %in% full$cell))
})

# ── Input validation ─────────────────────────────────────────────────────────

test_that("hsi_extract_spectra errors with non-SpatRaster input", {
  expect_error(hsi_extract_spectra("not a raster"))
})

test_that("hsi_extract_spectra errors when n exceeds the cell count", {
  expect_error(
    hsi_extract_spectra(test_reflectance, n = n_cells + 1),
    "between 1 and"
  )
})

test_that("hsi_extract_spectra errors with a non-SpatVector roi", {
  expect_error(hsi_extract_spectra(test_reflectance, roi = "not a vector"))
})
