# REFLECTANCE ------------------------------------------------------------
# Calculate only reflectance, no postprocessing
# Always open at the core level, rather than for example a site level

# Setup ------------------------------------------------------------------

library(here)
library(terra)
library(HSItools)
library(tidyverse)

# Identity ---------------------------------------------------------------

sensor <- "swir"

capture <- "{{{capture}}}"

reference <- "{{{reference}}}"

# Path constructors ------------------------------------------------------

products <- \(suffix) {
  here::here(sensor, capture, "products", paste0(capture, suffix))
}

spatials <- \(suffix) {
  here::here(sensor, capture, "spatial", paste0(capture, suffix))
}

captures <- \(suffix) {
  here::here(sensor, capture, "capture", paste0(capture, suffix))
}

references <- \(type, suffix) {
  here::here(sensor, reference, "capture", paste0(type, "_", reference, suffix))
}

# Create dirs ------------------------------------------------------------

purrr::walk(
  c("products", "spatial"),
  \(dir) fs::dir_create(here::here(sensor, capture, dir))
)

# Tint reader ------------------------------------------------------------

hsi_tint <- \(x) {
  readr::read_lines(x) |>
    stringr::str_subset("^tint") |>
    stringr::str_extract("\\d+\\.\\d+") |>
    as.numeric()
}

# Data -------------------------------------------------------------------

## SpatRasters ------------------------------------------------------------

# Use darkreference from underexposed scan so no negative values are introduced
rasters <- list(
  x = terra::rast(
    captures(".raw"),
    noflip = TRUE
  ),
  whiteref = terra::rast(
    references("WHITEREF", ".raw"),
    noflip = TRUE
  ),
  darkref = terra::rast(
    references("DARKREF", ".raw"),
    noflip = TRUE
  )
)

## Integration times ----------------------------------------------------

tints <- list(
  white = hsi_tint(references("WHITEREF", ".hdr")),
  scan = hsi_tint(captures(".hdr"))
)

# Check integration times
if (tints$white > tints$scan) {
  cli::cli_abort(
    "Whiteref integration time is greater than the sample integration time."
  )
} else {
  cli::cli_alert_success(
    "Correct integration times of {tints$white} and {tints$scan}."
  )
}

# Calculate reflectance --------------------------------------------------

reflectance <- HSItools::hsi_calc_reflectance(
  x = rasters$x,
  whiteref = rasters$whiteref,
  darkref = rasters$darkref,
  tint = c(tints$white, tints$scan),
  in_memory = TRUE
) |>
  terra::flip(
    direction = "horizontal",
    filename = products(".tif"),
    overwrite = TRUE
  )

# Previews ---------------------------------------------------------------

# Create a combination of type and extension
tidyr::crossing(type = c("SWIR"), ext = c(".tif", ".png")) |>
  purrr::pwalk(
    purrr::in_parallel(
      \(type, ext) {
        # Load libraries
        library(HSItools)
        library(terra)

        # Read reflectance from drive
        reflectance <- terra::rast(reflectance_path)

        # Stretch raster by type and extension
        HSItools::hsi_calc_stretch(
          reflectance,
          type = type,
          filename = spatials(paste0("_", type, ext)),
          overwrite = TRUE
        )
      },
      # Specify all arguments and functions for crating
      reflectance_path = products(".tif"),
      products = products,
      spatials = spatials,
      capture = capture
    ),
    .progress = TRUE
  )

# Geopackage -------------------------------------------------------------

# Get extent of full reflectance and use as a template
extent <- terra::ext(reflectance) |>
  terra::vect()

# Write geopackage with full extent
terra::writeVector(
  extent,
  filename = spatials(".gpkg"),
  layer = "extent",
  overwrite = TRUE
)

# Cleanup ----------------------------------------------------------------

fs::dir_ls(tempdir()) |>
  fs::file_delete()

gc()
