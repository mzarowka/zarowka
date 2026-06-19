#' Plot endmember spectra
#'
#' @family Plotting
#'
#' @param x A numeric matrix of endmember spectra with wavelengths (nm) as row
#'   names and endmember labels as column names, as produced by
#'   [`hsi_calc_endmembers()`] (`em$spectra`).
#'
#' @returns A [`ggplot2::ggplot`] object. Extend with `+` to add labels,
#'   themes, or colour scales.
#'
#' @details
#' Produces a minimal multi-line plot of reflectance against wavelength, one
#' coloured line per endmember. Internally the wide matrix is reshaped to the
#' same long form used by [`hsi_plot_spectrum()`] (`wavelength`, `value`, plus
#' an `endmember` grouping column), so the two plotters share a single data
#' contract. Endmember order in the legend follows column order in `x`.
#'
#' The returned ggplot carries no theme or axis labels — add these with `+`
#' using standard ggplot2 conventions.
#'
#' @seealso
#' [`hsi_calc_endmembers()`] to produce the input matrix.
#' [`hsi_calc_sam()`] for the pairwise redundancy diagnostic.
#' [`hsi_plot_spectrum()`] for a single spectrum.
#'
#' @examples
#' \dontrun{
#' x <- terra::rast("REFLECTANCE_testdata.tif")
#' spectra <- hsi_extract_spectra(x, n = 5000)
#' red <- stats::prcomp(spectra, center = TRUE, scale. = FALSE)
#' em <- hsi_calc_endmembers(spectra, reduction = red, n_endmembers = 6)
#'
#' # Quick plot
#' x_plot <- hsi_plot_endmembers(em$spectra)
#'
#' # Add labels and theme with ggplot2
#' x_plot +
#'   ggplot2::labs(x = "Wavelength (nm)", y = "Reflectance", colour = "Endmember") +
#'   ggplot2::theme_minimal()
#' }
#'
#' @importFrom rlang .data
#'
#' @export
hsi_plot_endmembers <- function(x) {
  # Validate inputs
  if (!is.matrix(x)) {
    cli::cli_abort(
      "{.arg x} is a {.class {class(x)}} not a matrix."
    )
  }

  if (is.null(rownames(x)) || is.null(colnames(x))) {
    cli::cli_abort(
      c(
        "{.arg x} must carry dimnames.",
        "i" = "Row names are wavelengths in nm; column names are endmember labels."
      )
    )
  }

  if (anyNA(suppressWarnings(as.numeric(rownames(x))))) {
    cli::cli_abort(
      "{.arg x} row names must be numeric wavelengths in nm."
    )
  }

  # Reshape to long (shared shape with hsi_plot_spectrum)
  spectra_long <- x |>
    tibble::as_tibble(rownames = "wavelength") |>
    tidyr::pivot_longer(
      cols = -"wavelength",
      names_to = "endmember",
      values_to = "value"
    ) |>
    dplyr::mutate(
      wavelength = as.numeric(.data$wavelength),
      endmember = factor(.data$endmember, levels = colnames(x))
    )

  # Create ggplot object
  result <- ggplot2::ggplot(data = spectra_long) +
    ggplot2::aes(
      x = .data$wavelength,
      y = .data$value,
      colour = .data$endmember
    ) +
    ggplot2::geom_line()

  # Return result
  result
}
