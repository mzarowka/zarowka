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

darkspec <- "{{{darkspec}}}"

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

darkrefs <- \(suffix) {
  here::here(sensor, darkspec, "capture", paste0("DARKREF_", darkspec, suffix))
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
  ),
  darkspec = terra::rast(
    darkrefs(".raw"),
    noflip = TRUE
  )
)

## Matched specimen dark --------------------------------------------------

# When using an external reference session, load the specimen-session dark
# reference for matched dark subtraction (recommended for SWIR)
darkspec_path <- here::here(
  sensor,
  capture,
  "capture",
  paste0("DARKREF_", capture, ".raw")
)

darkspec <- if (capture != reference && fs::file_exists(darkspec_path)) {
  cli::cli_alert_success("Using matched specimen dark reference.")
  terra::rast(darkspec_path, noflip = TRUE)
} else {
  if (capture != reference) {
    cli::cli_alert_warning(
      "No specimen dark reference found at {.path {darkspec_path}}. Falling back to integration time scaling."
    )
  }
  NULL
}

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
  darkspec = darkspec,
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
  overwrite = TRUE,
  insert = TRUE
)

# Cleanup ----------------------------------------------------------------

gc()
