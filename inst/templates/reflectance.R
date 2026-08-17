# REFLECTANCE ----------------------------------------------------------------
# Calibrate the cube, cropped to the transect digitised on the preview
# Always open at the core level, rather than for example a site level
# Run 01_preview.R and digitise `ends` before running this

# Setup ----------------------------------------------------------------------

library(here)
library(terra)
library(HSItools)
library(tidyverse)

# Identity -------------------------------------------------------------------
# Use bare folder names only, not full paths

sensor <- "{{{sensor}}}"

capture <- "{{{capture}}}"

reference <- "{{{reference}}}"

darkspec <- "{{{darkspec}}}"

# Transect width, in PIXELS. Pixel size differs between instruments, so a fixed
# pixel count is a fixed physical width only within one scanner. For a target in
# mm, compute round(width_mm / mm_per_pixel) for this capture.
width_px <- 100

# Pixels of overhang added to the crop. Leave at 0 for a sensor that is not
# co-registered. A sensor that will be warped onto another's grid needs a few
# pixels beyond the target edge, or resampling leaves NA borders.
margin_px <- 0

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

# Transect -------------------------------------------------------------------

# Core ends digitised on the preview, which shares the raw pixel grid, so the
# geometry needs no conversion before it is applied to the raw cube.
ends <- terra::vect(products(".gpkg"), layer = "ends")

transect <- HSItools::hsi_find_extent(
  rasters$x,
  points = ends,
  width = width_px,
  filename = products(".gpkg"),
  layer = "transect",
  insert = TRUE,
  overwrite = TRUE
)

# Crop -----------------------------------------------------------------------

crop_ext <- terra::ext(transect) + margin_px

# The specimen crops in both directions.
x_crop <- terra::crop(rasters$x, crop_ext)

# The references crop in the X DIRECTION ONLY. hsi_calc_reflectance() collapses
# each reference to a per-column mean and sweeps it across the specimen's
# columns, so the two column ranges must agree exactly or the sweep recycles and
# calibrates each column against the wrong reference. The reference rows are a
# separate scan and are averaged away regardless, so they are left alone.
crop_columns <- \(r) {
  terra::crop(
    r,
    terra::ext(crop_ext$xmin, crop_ext$xmax, terra::ymin(r), terra::ymax(r))
  )
}

# Calculate reflectance ------------------------------------------------------

# Cropping first is what makes in_memory defensible: the transect is a small
# fraction of the swath, so the cube no longer has to be converted whole.
#
# The result is NOT flipped, whatever the sensor. Orientation is corrected by
# co-registration in 03_coregister.R, whose fitted polynomial carries the mirror
# as a negative x scale. Flipping here would leave the digitised geometry and
# the raster in different frames.
reflectance <- HSItools::hsi_calc_reflectance(
  x = x_crop,
  whiteref = crop_columns(rasters$whiteref),
  darkref = crop_columns(rasters$darkref),
  darkspec = if (is.null(darkspec_rast)) NULL else crop_columns(darkspec_rast),
  tint = c(tints$white, tints$scan),
  in_memory = TRUE
) |>
  # Written as float. Reflectance legitimately runs negative where dark
  # subtraction over-corrects at low signal, and an unsigned integer datatype
  # would clamp those to zero, turning a calibration diagnostic into a
  # plausible-looking value.
  terra::writeRaster(
    filename = products(".tif"),
    overwrite = TRUE
  )

# Standalone SWIR ------------------------------------------------------------
# A SWIR capture with no paired VNIR never reaches co-registration, so nothing
# corrects its mirrored orientation. Un-comment to flip it here. This is safe
# only as the very last step: the transect crop is already applied, and the one
# remaining consumer of `ends` is hsi_set_extent(), which reads y alone.
#
# reflectance |>
#   terra::flip(
#     direction = "horizontal",
#     filename = products("_flipped.tif"),
#     overwrite = TRUE
#   )

# Cleanup --------------------------------------------------------------------

gc()
