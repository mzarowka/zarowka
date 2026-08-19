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

# Parallel workers for the per-pixel steps below. Physical cores, on the
# assumption that a scanning workstation is dedicated to this; lower it if you
# need headroom. Set once here and passed to every call — never per call site.
cores <- max(1, parallel::detectCores(logical = FALSE), na.rm = TRUE)

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
# once with bounded memory. The per-pixel steps take `cores` and spread the
# spectral work across a worker cluster without giving that streaming up.
# Measured on a 17474 x 100 x 271 transect at cores = 32 (2026-08-19), against
# the same code at cores = 1: savgol 10.0 -> 1.3 min, continuum removal
# 13.4 -> 1.3 min, output bit-identical in both cases.
#
# Returns flatten well below the core count because the output write stays
# serial (~31% parallel efficiency at 32 cores), so lowering `cores` costs much
# less than the ratio suggests. hsi_tiled() is deliberately not used here: it
# adds a serial makeTiles() copy in front and a serial vrt() + writeRaster()
# copy behind, which on this shape cost about twice the compute they
# parallelise (2026-08-18).

# Median smooth. Focal rather than per-pixel, so it takes no `cores` and stays
# single-threaded — which now makes it the largest step in the chain.
x <- HSItools::hsi_smooth_median(
  x,
  filename = products("_med.tif"),
  overwrite = TRUE
)

# Savitzky-Golay smooth
sg <- HSItools::hsi_smooth_savgol(
  x,
  cores = cores,
  filename = products("_sg0.tif"),
  overwrite = TRUE
)

# Savitzky-Golay 1st derivative
dr <- HSItools::hsi_smooth_savgol(
  x,
  m = 1,
  cores = cores,
  filename = products("_sg1.tif"),
  overwrite = TRUE
)

# Continuum removal
cr <- HSItools::hsi_remove_continuum(
  sg,
  cores = cores,
  filename = products("_cr.tif"),
  overwrite = TRUE
)

# Cleanup --------------------------------------------------------------------

gc()
