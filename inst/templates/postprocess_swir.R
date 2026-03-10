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

# Cleanup --------------------------------------------------------------------

fs::dir_ls(tempdir()) |>
  fs::file_delete()

gc()
