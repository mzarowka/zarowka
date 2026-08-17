# PREVIEW --------------------------------------------------------------------
# Calibrate three bands only, cheaply, for markup in a GIS
# Always open at the core level, rather than for example a site level
# Run this first: every later script consumes geometry digitised on its output

# Setup ----------------------------------------------------------------------

library(here)
library(terra)
library(HSItools)
library(tidyverse)

# Identity -------------------------------------------------------------------
# Use bare folder names only, not full paths

sensor <- "vnir"

capture <- "{{{capture}}}"

reference <- "{{{reference}}}"

darkspec <- "{{{darkspec}}}"

# Sensor clipping level, in raw DN. USER VERIFY against the instrument: this is
# instrument knowledge and is never inferred from the data. Too low condemns a
# clean capture, too high hides real clipping.
saturation_limit <- 4095

# Detection floor is mean + k * sd of the dark reference in each band. A pixel
# is flagged when it falls below that floor in `signal_fraction` of its bands.
signal_k <- 3

signal_fraction <- 0.9

# Path constructors ----------------------------------------------------------

products <- \(suffix) {
  here::here(sensor, capture, "products", paste0(capture, suffix))
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

# Create dirs ----------------------------------------------------------------

fs::dir_create(here::here(sensor, capture, "products"))

# Tint reader ----------------------------------------------------------------

hsi_tint <- \(x) {
  readr::read_lines(x) |>
    stringr::str_subset("^tint") |>
    stringr::str_extract("\\d+\\.\\d+") |>
    as.numeric()
}

# Data -----------------------------------------------------------------------

## SpatRasters ---------------------------------------------------------------

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

## Matched specimen dark -----------------------------------------------------

# Specimen-side dark reference, taken from the session named by `darkspec`
# (the specimen's own session by default). Matched darks are preferred: they
# remove striping and negative-reflectance artifacts. When the dark comes from
# the same session as the white reference it is already `rasters$darkref`, so
# nothing extra is loaded and calibration falls back to integration time scaling.
darkspec_path <- darkrefs(".raw")

darkspec_rast <- if (darkspec != reference && fs::file_exists(darkspec_path)) {
  cli::cli_alert_success(
    "Using matched specimen dark reference from {.path {darkspec}}."
  )
  terra::rast(darkspec_path, noflip = TRUE)
} else {
  if (darkspec != reference) {
    cli::cli_alert_warning(
      "No specimen dark reference found at {.path {darkspec_path}}. Falling back to integration time scaling."
    )
  }
  NULL
}

## Integration times ---------------------------------------------------------

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

# Previews -------------------------------------------------------------------

# Calibration is identical to the full cube in every respect except size: same
# references, same matched dark, same integration times. Only three bands are
# converted, and the result keeps the raw pixel grid, so anything digitised on
# a preview applies to the full cube without conversion.
purrr::walk(
  c("RGB", "CIR", "NIR"),
  \(type) {
    HSItools::hsi_calc_preview(
      x = rasters$x,
      whiteref = rasters$whiteref,
      darkref = rasters$darkref,
      darkspec = darkspec_rast,
      tint = c(tints$white, tints$scan),
      type = type
    ) |>
      HSItools::hsi_calc_stretch(
        type = type,
        filename = products(paste0("_preview_", type, ".tif")),
        overwrite = TRUE
      )
  },
  .progress = TRUE
)

# Geopackage -----------------------------------------------------------------

# The raw grid's extent, written as the frame everything else is digitised in.
terra::ext(rasters$x) |>
  terra::vect() |>
  terra::writeVector(
    filename = products(".gpkg"),
    layer = "extent",
    overwrite = TRUE,
    insert = TRUE
  )

# Markup ---------------------------------------------------------------------
# Open products/<capture>_preview_RGB.tif and the geopackage in a GIS, then
# digitise into the geopackage:
#
#   ends  - two points, core top first, defining the transect axis
#   gcp   - registration pins, only when this capture will be co-registered
#   mask  - optional polygons over cracks, gaps or tray
#
# Then run 02_reflectance.R.

# Cleanup --------------------------------------------------------------------

gc()
