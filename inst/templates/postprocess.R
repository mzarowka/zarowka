# POSTPROCESS ----------------------------------------------------------------
# Smooth and prepare derivatives for spectral index calculation
# Always open at the core level, rather than for example a site level
# Run 02_reflectance.R first, and 03_coregister.R for a co-registered sensor

# Setup ----------------------------------------------------------------------

library(here)
library(terra)
library(HSItools)
library(tidyverse)
library(mirai)

# Identity -------------------------------------------------------------------
# Use bare folder names only, not full paths

sensor <- "{{{sensor}}}"

capture <- "{{{capture}}}"

cores <- 4

# Input product. A co-registered sensor postprocesses the warped product; a
# sensor that defines the target grid postprocesses its own reflectance.
source_suffix <- "{{{source_suffix}}}"

# Path constructors ----------------------------------------------------------

products <- \(suffix) {
  here::here(sensor, capture, "products", paste0(capture, suffix))
}

# Data -----------------------------------------------------------------------

# No crop here. Reflectance was already calibrated to the transect only, which
# is the whole point of digitising `ends` before calibrating rather than after.
x <- terra::rast(products(paste0(source_suffix, ".tif")))

# Processing -----------------------------------------------------------------

mirai::daemons(cores)

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

gc()
