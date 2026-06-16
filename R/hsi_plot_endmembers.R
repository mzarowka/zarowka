#' Plot endmember spectra from a raster representation
#'
#' @family Plotting
#'
#' @param x A [`SpatRaster`][terra::SpatRaster-class] with hyperspectral data.
#'   Any representation (reflectance, continuum-removed, derivative, ...) sharing
#'   the geometry the endmembers were found on.
#' @param locations Integer vector. Cell numbers of the endmember pixels,
#'   indexing the same geometry as `x`. Optionally named to label the
#'   endmembers.
#'
#' @returns A [ggplot][ggplot2::ggplot] object with one line per endmember.
#'
#' @details
#' The function reads the spectrum at each endmember cell from whatever
#' representation it is handed, so the same `locations` plotted against
#' reflectance, continuum-removed reflectance, and a first-derivative raster
#' give three comparable panels. Composing those panels is deliberately left to
#' the caller: call the function once per representation and combine the results
#' with `patchwork`. Keeping a single panel per call is what makes the function
#' representation-agnostic.
#'
#' Cell numbers index the grid of `x`. Because the supported representations all
#' share the original reflectance geometry, the same cell numbers are valid
#' across them; a cell number outside `x` is treated as a geometry mismatch and
#' aborts. Wavelengths for the x-axis are read from the layer names of `x`,
#' falling back to band index if the names are not numeric.
#'
#' @seealso
#' [`hsi_calc_endmembers()`] returns the endmember cell numbers in the `cell`
#' column of its `locations` provenance table (`em$locations$cell`); in the
#' pooled multi-scene case, filter `locations` to one scene first, since cell
#' numbers are scene-relative. Combine multiple panels with
#' [`patchwork::wrap_plots()`].
#'
#' @examples
#' \dontrun{
#' x <- terra::rast("REFLECTANCE_testdata.tif")
#' spectra <- hsi_extract_spectra(x, n = 1000)
#' em <- hsi_calc_endmembers(spectra, n_endmembers = 4)
#'
#' # Cell numbers and labels come from the locations provenance table.
#' cells <- stats::setNames(em$locations$cell, em$locations$endmember)
#'
#' # One panel per representation, patched by hand.
#' x_cr <- hsi_remove_continuum(x)
#' p_reflectance <- hsi_plot_endmembers(x, cells)
#' p_continuum <- hsi_plot_endmembers(x_cr, cells)
#' p_reflectance / p_continuum
#' }
#'
#' @export
hsi_plot_endmembers <- function(x, locations) {
  # Validate inputs
  HSItools:::check_spatraster(x)
  HSItools:::check_numeric(locations)

  n_cells <- terra::ncell(x)
  if (any(locations < 1 | locations > n_cells)) {
    cli::cli_abort(c(
      "{.arg locations} contains cell numbers outside {.arg x}.",
      "i" = "{.arg x} has {n_cells} cell{?s}; endmember locations must index the same geometry.",
      "x" = "Got cell numbers up to {max(locations)}."
    ))
  }

  # Wavelengths from layer names (nm); fall back to band index if the names are
  # not numeric. Layer names of an HSItools raster are wavelengths.
  wavelengths <- suppressWarnings(as.numeric(names(x)))
  if (all(is.na(wavelengths))) {
    wavelengths <- seq_len(terra::nlyr(x))
  }
  names(wavelengths) <- names(x)

  # Endmember labels: names of locations, else EM1..EMn.
  em_labels <- names(locations)
  if (is.null(em_labels)) {
    em_labels <- paste0("EM", seq_along(locations))
  }

  # Extract endmember spectra. `[` reads only the requested cells (one row per
  # endmember), so this stays cheap on large rasters.
  spectra <- tibble::as_tibble(x[locations])

  # Reshape to one row per endmember-band for plotting.
  spectra_long <- spectra |>
    dplyr::mutate(
      endmember = factor(em_labels, levels = em_labels),
      .before = 1
    ) |>
    tidyr::pivot_longer(
      cols = -endmember,
      names_to = "band",
      values_to = "value"
    ) |>
    dplyr::mutate(wavelength = unname(wavelengths[band]))

  # Build plot: one line per endmember.
  ggplot2::ggplot(
    spectra_long,
    ggplot2::aes(
      x = wavelength,
      y = value,
      colour = endmember,
      group = endmember
    )
  ) +
    ggplot2::geom_line() +
    ggplot2::labs(x = "Wavelength (nm)", y = "Value", colour = "Endmember") +
    ggplot2::theme_minimal()
}
