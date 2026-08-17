# COREGISTER -----------------------------------------------------------------
# Warp this sensor's reflectance onto the paired VNIR grid using GCPs
# Always open at the core level, rather than for example a site level
# Run 02_reflectance.R for BOTH sensors, and digitise `gcp` on both previews

# Setup ----------------------------------------------------------------------

library(here)
library(terra)
library(HSItools)
library(tidyverse)

# Identity -------------------------------------------------------------------
# Use bare folder names only, not full paths

sensor <- "{{{sensor}}}"

capture <- "{{{capture}}}"

vnir_capture <- "{{{vnir_capture}}}"

# Path constructors ----------------------------------------------------------

products <- \(suffix) {
  here::here(sensor, capture, "products", paste0(capture, suffix))
}

vnir_products <- \(suffix) {
  here::here("vnir", vnir_capture, "products", paste0(vnir_capture, suffix))
}

# Data -----------------------------------------------------------------------

## GCPs ----------------------------------------------------------------------

# Registration pins, digitised on each sensor's own preview. Matching is a
# point-to-point problem: no raster is read to fit the transform, which is why
# the pins may sit anywhere in the frame rather than inside the transect.
source_gcp <- terra::vect(products(".gpkg"), layer = "gcp")

target_gcp <- terra::vect(vnir_products(".gpkg"), layer = "gcp")

# Coregister -----------------------------------------------------------------

matched <- HSItools::hsi_match_gcp(source_gcp, target_gcp)

# Check transformation quality before proceeding
HSItools::hsi_check_gcp(matched)

# hsi_coregister() converts each source coordinate to a pixel position using the
# extent of `x` itself, so the pins and `x` must be in the SAME frame. Both are
# unflipped here, and the fitted first-order polynomial carries the mirror as a
# negative x scale — orientation and alignment are corrected together. Flipping
# either one beforehand breaks this silently rather than loudly.
#
# The VNIR reflectance supplies the target grid, so the output lands on exactly
# its extent and dimensions. Nothing downstream needs to borrow VNIR geometry.
HSItools::hsi_coregister(
  terra::rast(products(".tif")),
  terra::rast(vnir_products(".tif")),
  gcp = matched,
  method = "lanczos",
  filename = products("_coreg.tif"),
  overwrite = TRUE
)

# Preview --------------------------------------------------------------------

# Co-registered, therefore in VNIR orientation: this one is worth looking at.
terra::rast(products("_coreg.tif")) |>
  HSItools::hsi_calc_stretch(
    type = "SWIR",
    filename = products("_coreg_SWIR.tif"),
    overwrite = TRUE
  )

# Cleanup --------------------------------------------------------------------

gc()
