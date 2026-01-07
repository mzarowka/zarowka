# REFLECTANCE #################################################################
# Calculate only "raw" reflectance without any postprocessing
# Setup ----
library(HSItools)
library(tidyverse)
library(mirai)

# Names and paths
# Constructors
products <- \(suffix) fs::path(paste0(capture, "/products/", capture, suffix))

spatials <- \(suffix) fs::path(paste0(capture, "/spatial/", capture, suffix))

captures <- \(suffix) fs::path(paste0(capture, "/capture/", capture, suffix))

references <- \(type, suffix) {
  fs::path(paste0(reference, "/capture/", type, "_", reference, suffix))
}

# Drive name and captured data
capture <- fs::path("{{{capture}}}")

# References
reference <- fs::path("{{{reference}}}")

# Create dirs
fs::dir_create(paste0(capture, c("/products/", "/spatial/")))

# Data ----
## SpatRaster ----
# Use darkreference from underexposed scan
# darkreference from capture scan migh lead to negative values
data <- list(
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

## Integration times ----
# Whiteref
tintw <- readr::read_lines(
  references("WHITEREF", ".hdr")
) |>
  stringr::str_subset("^tint") |>
  stringr::str_extract("\\d+\\.\\d+") |>
  as.numeric()

# Data
tints <- readr::read_lines(
  captures(".hdr")
) |>
  stringr::str_subset("^tint") |>
  stringr::str_extract("\\d+\\.\\d+") |>
  as.numeric()

# Check integration times
if (tintw > tints) {
  cli::cli_abort(
    "Whiteref integration time is greater than the sample integration time."
  )
} else {
  cli::cli_alert_success("Correct integration times of {tintw} and {tints}.")
}

# Calculate reflectance ----
reflectance <- HSItools::hsi_calc_reflectance(
  x = data$x,
  whiteref = data$whiteref,
  darkref = data$darkref,
  tint = c(tintw, tints),
  in_memory = TRUE,
  filename = products(".tif")
)

# Previews ----
# Set daemons
mirai::daemons(0)

# Generate all previews
# Create a combination of type and extension
tidyr::crossing(type = c("RGB", "CIR", "NIR"), ext = c(".tif", ".png")) |>
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

# Geopackage ----
# Get extent of full reflectance and use as a template
extent <- terra::ext(reflectance) |>
  # Convert to SpatVector
  terra::vect()

# Write geopackage with full extent
terra::writeVector(
  extent,
  filename = spatials(".gpkg"),
  layer = "extent",
  overwrite = TRUE
)

# Cleanup ----
fs::dir_ls(tempdir()) |>
  fs::file_delete()
