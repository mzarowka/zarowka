# COREGISTER -----------------------------------------------------------------
# Coregister SWIR reflectance to paired VNIR using GCPs
# Always open at the core level, rather than for example a site level
# Run VNIR reflectance script first — RGB preview must exist in vnir/spatial

# Setup ----------------------------------------------------------------------

library(here)
library(terra)
library(HSItools)
library(tidyverse)

# Identity -------------------------------------------------------------------
# Use bare folder names only, not full paths

sensor       <- "swir"
capture      <- "{{{capture}}}"
vnir_capture <- "{{{vnir_capture}}}"

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

x <- terra::rast(products(".tif"))

## GCPs ----------------------------------------------------------------------

# SWIR GCPs digitized in SWIR spatial
source_gcp <- terra::vect(spatials(".gpkg"), layer = "gcp")

# VNIR GCPs digitized in VNIR spatial — defines the target coordinate space
target_gcp <- terra::vect(vnir_spatials(".gpkg"), layer = "gcp")

# Coregister -----------------------------------------------------------------

# Match GCPs between SWIR and VNIR
matched <- HSItools::hsi_match_gcp(source_gcp, target_gcp)

# Check transformation quality before proceeding
HSItools::hsi_check_gcp(matched)

# Apply coregistration using VNIR RGB as spatial reference
HSItools::hsi_coregister(
  x,
  terra::rast(vnir_spatials("_RGB.tif")),
  matched_gcps = matched,
  filename = products("_coreg.tif"),
  overwrite = TRUE
)

# Cleanup --------------------------------------------------------------------

fs::dir_ls(tempdir()) |>
  fs::file_delete()

gc()
