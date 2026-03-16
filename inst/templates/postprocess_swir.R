# POSTPROCESS ----------------------------------------------------------------
# Crop, smooth, and prepare derivatives for spectral index calculation
# Always open at the core level, rather than for example a site level
# Transect is read from paired VNIR spatial — run VNIR postprocess first

# Setup ----------------------------------------------------------------------

library(here)
library(terra)
library(HSItools)
library(tidyverse)
library(mirai)

# Identity -------------------------------------------------------------------
# Use bare folder names only, not full paths

sensor <- "swir"
capture <- "{{{capture}}}"
vnir_capture <- "{{{vnir_capture}}}"
cores <- 4

# Path constructors ----------------------------------------------------------

products <- \(suffix) {
  here::here(sensor, capture, "products", paste0(capture, suffix))
}

spatials <- \(suffix) {
  here::here(sensor, capture, "spatial", paste0(capture, suffix))
}

vnir_spatials <- \(suffix) {
  here::here("vnir", vnir_capture, "spatial", paste0(vnir_capture, suffix))
}

# Data -----------------------------------------------------------------------

## SpatRaster ----------------------------------------------------------------

# Read co-registered reflectance
x <- terra::rast(products("_coreg.tif"))

## SpatVector ----------------------------------------------------------------

# Borrow transect computed by VNIR postprocess
transect <- terra::vect(vnir_spatials(".gpkg"), layer = "transect")

# Processing -----------------------------------------------------------------

mirai::daemons(cores)

# Crop to transect
x <- terra::crop(
  x,
  transect,
  filename = products("_100.tif"),
  overwrite = TRUE
)

# Median smooth
x <- HSItools::hsi_smooth_median(
  x,
  filename = products("_med.tif"),
  overwrite = TRUE
)

# Savitzky-Golay smooth
sg <- HSItools::hsi_tiled(
  x,
  fun = \(tile) HSItools::hsi_smooth_savgol(tile),
  n_tiles = cores,
  filename = products("_sg0.tif"),
  overwrite = TRUE
)

# Savitzky-Golay 1st derivative
dr <- HSItools::hsi_tiled(
  x,
  fun = \(tile) HSItools::hsi_smooth_savgol(tile, m = 1),
  n_tiles = cores,
  filename = products("_sg1.tif"),
  overwrite = TRUE
)

# Continuum removal
cr <- HSItools::hsi_tiled(
  sg,
  fun = \(tile) HSItools::hsi_remove_continuum(tile),
  n_tiles = cores,
  filename = products("_cr.tif"),
  overwrite = TRUE
)

mirai::daemons(0)

# Physical coordinate raster -------------------------------------------------
# Scan length must be read from the scan log — it is not in any output file.
# Enter the value recorded by the operator (Target stop - Target start).
# Use the SWIR scan length, not the VNIR scan length.

um <- HSItools::hsi_calibration_from_dims(
  pixels = terra::nrow(sg),
  distance = ..., # USER FILLS IN: scan length from scan log in mm
  units = "mm"
)

# Or
um <- HSItools::hsi_calibration_from_scale(
  x = HSItools:::hsi_drop_crs(terra::vect(spatials(".gpkg"), layer = "scale"))
)

coords <- HSItools::hsi_calc_coords(
  sg,
  um_per_pixel = um,
  filename = products("_coords.tif"),
  overwrite = TRUE
)

# Shift coordinate raster to top of core (first ends point = true zero depth)
# Ends layer is borrowed from VNIR — SWIR is co-registered to VNIR spatial framing.
top <- terra::vect(vnir_spatials(".gpkg"), layer = "ends")[1, ]

# Or
top <- top <- terra::xyFromCell(coords, 1) |>
  matrix(ncol = 2) |>
  terra::vect(type = "points") |>
  HSItools:::hsi_drop_crs()

coords_shifted <- HSItools::hsi_shift_coords(
  coords,
  reference = top,
  origin = 0,
  filename = products("_coords_shifted.tif"),
  overwrite = TRUE
)

gc()
