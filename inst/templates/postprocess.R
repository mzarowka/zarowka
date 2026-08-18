# POSTPROCESS ----------------------------------------------------------------
# Smooth and prepare derivatives for spectral index calculation
# Always open at the core level, rather than for example a site level
# Run 02_reflectance.R first, and 03_coregister.R for a co-registered sensor

# Setup ----------------------------------------------------------------------

library(here)
library(terra)
library(HSItools)
library(tidyverse)

# Identity -------------------------------------------------------------------
# Use bare folder names only, not full paths

sensor <- "{{{sensor}}}"

capture <- "{{{capture}}}"

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

# Every step below streams internally through terra::app(), reading and writing
# once with bounded memory. They are deliberately NOT wrapped in hsi_tiled():
# on a cropped transect that wrapper adds a serial makeTiles() copy in front and
# a serial vrt() + writeRaster() copy behind, which cost about twice the compute
# they parallelise. Measured on a 17474 x 100 x 271 transect (2026-08-18):
#
#   savgol   tiled 4 workers 19.6 min | tiled 60 workers 17.6 min | direct 10.0 min
#   conrem   tiled 4 workers 20.6 min |                           | direct 13.4 min
#
# That balance is specific to a narrow transect, where terra's row-blocks are
# already large. On a full-width cube, where blocks are shallow and numerous,
# tiling may well win again — measure before assuming either way.

# Median smooth. Focal, so it has a spatial neighbourhood and could not be
# tiled by rows without leaving seams at the tile boundaries.
x <- HSItools::hsi_smooth_median(
  x,
  filename = products("_med.tif"),
  overwrite = TRUE
)

# Savitzky-Golay smooth
sg <- HSItools::hsi_smooth_savgol(
  x,
  filename = products("_sg0.tif"),
  overwrite = TRUE
)

# Savitzky-Golay 1st derivative
dr <- HSItools::hsi_smooth_savgol(
  x,
  m = 1,
  filename = products("_sg1.tif"),
  overwrite = TRUE
)

# Continuum removal
cr <- HSItools::hsi_remove_continuum(
  sg,
  filename = products("_cr.tif"),
  overwrite = TRUE
)

# Cleanup --------------------------------------------------------------------

gc()
