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

sensor <- "swir"

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
# (the specimen's own session by default). Matched darks matter most for SWIR,
# where unsubtracted dark current dominates. When the dark comes from the same
# session as the white reference it is already `rasters$darkref`, so nothing
# extra is loaded and calibration falls back to integration time scaling.
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

# Reference screening --------------------------------------------------------

# A saturated white reference corrupts the denominator of every reflectance
# calculation in the session, and the damage is invisible once calibration has
# been applied. Catch it here, while re-scanning is still an option.
whiteref_saturated <- HSItools::hsi_check_saturation(
  rasters$whiteref,
  limit = saturation_limit
) |>
  terra::global("sum", na.rm = TRUE) |>
  sum(na.rm = TRUE)

if (whiteref_saturated > 0) {
  cli::cli_alert_danger(
    "White reference has {whiteref_saturated} saturated pixel-band{?s}. Re-scan the reference before trusting anything downstream."
  )
} else {
  cli::cli_alert_success("White reference is not saturated.")
}

# Preview --------------------------------------------------------------------

# Calibration is identical to the full cube in every respect except size: same
# references, same matched dark, same integration times. Only three bands are
# converted, and the result keeps the raw pixel grid, so anything digitised on
# the preview applies to the full cube without conversion.
preview <- HSItools::hsi_calc_preview(
  x = rasters$x,
  whiteref = rasters$whiteref,
  darkref = rasters$darkref,
  darkspec = darkspec_rast,
  tint = c(tints$white, tints$scan),
  type = "SWIR"
) |>
  HSItools::hsi_calc_stretch(
    type = "SWIR",
    filename = products("_preview_SWIR.tif"),
    overwrite = TRUE
  )

## Flipped view --------------------------------------------------------------

# SWIR sees the specimen mirrored relative to VNIR. Nothing in this workflow
# flips the data: co-registration fits a first-order polynomial, which carries
# the mirror as a negative x scale, so the transform corrects orientation and
# alignment in one step. Introducing a separate flip would put the digitised
# geometry and the raster into different frames, silently.
#
# DIGITISE ON THE UNFLIPPED PREVIEW ABOVE. This copy exists only so the
# specimen can be looked at the right way round.
preview |>
  terra::flip(
    direction = "horizontal",
    filename = products("_preview_SWIR_flipped.tif"),
    overwrite = TRUE
  )

# Masks ----------------------------------------------------------------------

# Both screens need raw digital numbers, so this is the only stage that can run
# them — everything downstream is calibrated. Each costs one streaming pass and
# writes a single collapsed layer on the raw grid, so they overlay the UNFLIPPED
# preview exactly and can guide where `ends` and `mask` are digitised.
#
# They are written, never applied. Masking is a decision: load them in the GIS,
# and apply with HSItools::hsi_mask() once you have decided what to remove.

HSItools::hsi_check_saturation(
  rasters$x,
  limit = saturation_limit,
  collapse = TRUE,
  filename = products("_saturated.tif"),
  overwrite = TRUE
)

zarowka::hsi_check_signal(
  rasters$x,
  # Prefer the matched specimen dark; fall back to the reference session's.
  darkref = if (is.null(darkspec_rast)) rasters$darkref else darkspec_rast,
  k = signal_k,
  fraction = signal_fraction,
  collapse = TRUE,
  filename = products("_no_signal.tif"),
  overwrite = TRUE
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
# Open in a GIS, on the same pixel grid. Use the UNFLIPPED preview:
#
#   <capture>_preview_SWIR.tif   the composite to digitise on
#   <capture>_saturated.tif      1 = clipped in at least one band
#   <capture>_no_signal.tif      1 = below the detection floor, e.g. cracks
#   <capture>.gpkg               where the geometry goes
#
# The _flipped copy is for viewing only — geometry digitised on it would be
# mirrored relative to the data.
#
# Then digitise into the geopackage:
#
#   ends  - two points, core top first, defining the transect axis
#   gcp   - registration pins, matching the ids used on the paired VNIR
#   mask  - optional polygons over cracks, gaps or tray
#
# Then run 02_reflectance.R.

# Cleanup --------------------------------------------------------------------

gc()
