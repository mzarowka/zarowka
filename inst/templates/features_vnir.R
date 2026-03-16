# FEATURES -------------------------------------------------------------------
# PCA and MNF on smoothed and continuum-removed reflectance
# Always open at the core level, rather than for example a site level
# Run postprocess before this script

# Setup ----------------------------------------------------------------------

library(here)
library(terra)
library(HSItools)
library(tidyverse)
library(mirai)

# Identity -------------------------------------------------------------------
# Use bare folder names only, not full paths

sensor <- "vnir"
capture <- "{{{capture}}}"
cores <- 4

# Set to TRUE to recompute outputs that already exist on disk
force_recompute <- FALSE

n_components <- {{{n_components}}}

# Path constructors ----------------------------------------------------------

products <- \(suffix) {
  here::here(sensor, capture, "products", paste0(capture, suffix))
}

# Processing -----------------------------------------------------------------

mirai::daemons(cores)

# PCA on sg0 -----------------------------------------------------------------

if (force_recompute || !fs::file_exists(products("_pca_sg0.tif"))) {
  if (!fs::file_exists(products("_sg0.tif"))) {
    cli::cli_warn("Source file {.file {products('_sg0.tif')}} not found. Skipping PCA on sg0.")
  } else {
    x <- terra::rast(products("_sg0.tif"))

    # Band names like 397.5nm are not valid R names — required before prcomp and predict
    names(x) <- make.names(names(x))

    pca_model <- terra::prcomp(x, center = TRUE, scale. = TRUE, retx = FALSE)

    pca_sg0 <- terra::predict(x, pca_model, index = seq_len(n_components))

    names(pca_sg0) <- paste0("PC", seq_len(n_components))

    terra::writeRaster(
      pca_sg0,
      filename = products("_pca_sg0.tif"),
      overwrite = TRUE
    )

    cli::cli_inform("PCA on sg0 written to {.file {products('_pca_sg0.tif')}}.")
  }
}

# PCA on sg1 -----------------------------------------------------------------

if (force_recompute || !fs::file_exists(products("_pca_sg1.tif"))) {
  if (!fs::file_exists(products("_sg1.tif"))) {
    cli::cli_warn("Source file {.file {products('_sg1.tif')}} not found. Skipping PCA on sg1.")
  } else {
    x <- terra::rast(products("_sg1.tif"))

    names(x) <- make.names(names(x))

    pca_model <- terra::prcomp(x, center = TRUE, scale. = TRUE, retx = FALSE)

    pca_sg1 <- terra::predict(x, pca_model, index = seq_len(n_components))

    names(pca_sg1) <- paste0("PC", seq_len(n_components))

    terra::writeRaster(
      pca_sg1,
      filename = products("_pca_sg1.tif"),
      overwrite = TRUE
    )

    cli::cli_inform("PCA on sg1 written to {.file {products('_pca_sg1.tif')}}.")
  }
}

# PCA on cr ------------------------------------------------------------------

if (force_recompute || !fs::file_exists(products("_pca_cr.tif"))) {
  if (!fs::file_exists(products("_cr.tif"))) {
    cli::cli_warn("Source file {.file {products('_cr.tif')}} not found. Skipping PCA on cr.")
  } else {
    x <- terra::rast(products("_cr.tif"))

    names(x) <- make.names(names(x))

    pca_model <- terra::prcomp(x, center = TRUE, scale. = TRUE, retx = FALSE)

    pca_cr <- terra::predict(x, pca_model, index = seq_len(n_components))

    names(pca_cr) <- paste0("PC", seq_len(n_components))

    terra::writeRaster(
      pca_cr,
      filename = products("_pca_cr.tif"),
      overwrite = TRUE
    )

    cli::cli_inform("PCA on cr written to {.file {products('_pca_cr.tif')}}.")
  }
}

# MNF ------------------------------------------------------------------------
# Requires the spacetime package — skipped silently if not installed

if (!requireNamespace("spacetime", quietly = TRUE)) {
  cli::cli_warn("Package {.pkg spacetime} is not installed. Skipping MNF.")
} else if (force_recompute || !fs::file_exists(products("_mnf.tif"))) {
  if (!fs::file_exists(products("_sg0.tif"))) {
    cli::cli_warn("Source file {.file {products('_sg0.tif')}} not found. Skipping MNF.")
  } else {
    x <- terra::rast(products("_sg0.tif"))

    mnf <- HSItools::hsi_calc_mnf(
      x,
      n_components = n_components,
      filename = products("_mnf.tif"),
      overwrite = TRUE
    )

    cli::cli_inform("MNF written to {.file {products('_mnf.tif')}}.")
  }
}

mirai::daemons(0)

gc()
