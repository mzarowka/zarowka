# REFLECTANCE ----------------------------------------------------------------
# Calibrate the cube, windowed to the transect digitised on the preview
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

# Pixels of overhang added to the window. Leave at 0 for a sensor that is not
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

# Window ---------------------------------------------------------------------

window_ext <- terra::ext(transect) + margin_px

# The region of interest is set with terra::window(), never terra::crop(). A
# crop of a raw capture may materialise to a temporary file, and terra writes
# that copy in the source integer datatype, reserving the datatype maximum as
# the NoData value. Every genuinely saturated reading is then read back as NA,
# and whether it happens at all depends on terra's memory budget, so the same
# script can produce different products on different machines. A window is
# lazy: nothing is read or written until a downstream function reads the ROI
# straight from the raw file. A physical raw subset, if one is ever needed,
# must be written with a float datatype (e.g. `datatype = "FLT4S"`).

# The specimen is windowed in both directions.
x_win <- rasters$x

terra::window(x_win) <- window_ext

# The references are windowed in the X DIRECTION ONLY. hsi_calc_reflectance()
# collapses each reference to a per-column mean and sweeps it across the
# specimen's columns, so the two column ranges must agree exactly or the sweep
# recycles and calibrates each column against the wrong reference. The reference
# rows are a separate scan and are averaged away regardless, so they are left
# alone.
window_columns <- \(r) {
  terra::window(r) <- terra::ext(
    window_ext$xmin,
    window_ext$xmax,
    terra::ymin(r),
    terra::ymax(r)
  )

  r
}

## Saturation in the transect ------------------------------------------------

# The frame-wide saturation fraction is dominated by whatever else is in shot —
# tray, support, labels — and so says little about the sample. The same mask
# read under the transect is the number that matters, and it only becomes
# available once the transect exists.
saturated_path <- products("_saturated.tif")

if (fs::file_exists(saturated_path)) {
  saturated_mask <- terra::rast(saturated_path)

  terra::window(saturated_mask) <- window_ext

  saturated_pct <- 100 *
    terra::global(
      saturated_mask,
      "mean",
      na.rm = TRUE
    )[[1]]

  if (saturated_pct > 1) {
    cli::cli_alert_warning(
      "{round(saturated_pct, 1)}% of transect pixels are saturated in at least one band. Band depths there are compressed toward the ceiling."
    )
  } else {
    cli::cli_alert_success(
      "Transect is essentially free of saturation ({round(saturated_pct, 2)}%)."
    )
  }
} else {
  saturated_mask <- NULL

  cli::cli_alert_info(
    "No saturation mask at {.path {saturated_path}}. Run 01_preview.R to create one."
  )
}

# Calculate reflectance ------------------------------------------------------

# Windowing first is what makes in_memory defensible: only the transect is read
# from the raw file, a small fraction of the swath, so the cube no longer has to
# be converted whole.
#
# The result is NOT flipped, whatever the sensor. Orientation is corrected by
# co-registration in 03_coregister.R, whose fitted polynomial carries the mirror
# as a negative x scale. Flipping here would leave the digitised geometry and
# the raster in different frames.
reflectance <- HSItools::hsi_calc_reflectance(
  x = x_win,
  whiteref = window_columns(rasters$whiteref),
  darkref = window_columns(rasters$darkref),
  darkspec = if (is.null(darkspec_rast)) {
    NULL
  } else {
    window_columns(darkspec_rast)
  },
  tint = c(tints$white, tints$scan),
  in_memory = TRUE
)

## Drop the clipped pixels -----------------------------------------------

# A clipped reading carries no information about the specimen. The digital
# number is pinned at the ceiling, so what survives calibration is the shape
# of the white reference rather than the sample: a smooth, plausible-looking
# curve that is pure instrument response.
#
# The screen is collapsed, so a pixel that clipped in any band goes entirely.
# That is the honest reading rather than a conservative one: detector response
# is already compressed in the bands either side of a clipped run, so the
# neighbours that sit below the threshold cannot be trusted either, and there
# is no way to draw the line between contaminated and clean.
#
# `inverse = TRUE` reads the screen as a bad-mask: nonzero cells are dropped.
# It was windowed to `window_ext` above, so its geometry already matches the
# product. Masking here, while both still sit on the raw pixel grid, is what
# makes that true — after 03_coregister.R the product is warped and the screen
# no longer corresponds to it.
if (!is.null(saturated_mask)) {
  reflectance <- HSItools::hsi_mask(
    reflectance,
    mask = saturated_mask,
    inverse = TRUE
  )
}

# Written as float. Reflectance legitimately runs negative where dark
# subtraction over-corrects at low signal, and an unsigned integer datatype
# would clamp those to zero, turning a calibration diagnostic into a
# plausible-looking value.
reflectance <- terra::writeRaster(
  reflectance,
  filename = products(".tif"),
  overwrite = TRUE
)

# Standalone SWIR ------------------------------------------------------------
# A SWIR capture with no paired VNIR never reaches co-registration, so nothing
# corrects its mirrored orientation. Un-comment to flip it here. This is safe
# only as the very last step: the transect window is already applied, and the one
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
