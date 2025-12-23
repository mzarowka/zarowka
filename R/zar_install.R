#' Install Maury's choince of packages with pak
#'
#' @returns
#'
#' @export
#' @examples
zar_install <- function() {
  # Define packages
  packages <- c(
    "tidyverse",
    "tidymodels",
    "padr",
    "zoo",
    "terra",
    "tidyterra",
    "readxl",
    "writexl",
    "xgboost",
    "ranger",
    "sf",
    "quarto",
    "tidypaleo",
    "vegan",
    "analogue",
    "patchwork",
    "ggfortify",
    "palinsol",
    "rbacon",
    "rplum",
    "arrow",
    "duckdb",
    "here",
    "gt",
    "EMMAgeo",
    "robCompositions",
    "zCompositions",
    "pcaPP",
    "torch",
    "luz",
    "viridis",
    "cols4all",
    "stars",
    "spacetime",
    "Bchron",
    "oxcAAR",
    "gratia",
    "janitor",
    "styler",
    "paletteer",
    "FactoMineR",
    "factoextra",
    "corrr",
    "ggrepel",
    "dbscan",
    "adespatial",
    "align",
    "datapasta",
    "plotly",
    "cmocean",
    "changepoint",
    "era",
    "imager",
    "rgugik",
    "climate",
    "rLakeAnalyzer",
    "BINCOR",
    "tictoc",
    "keras",
    "smoother",
    "spatialEco",
    "gapminder",
    "ggforce",
    "gh",
    "globals",
    "shiny",
    "shinycssloaders",
    "shinythemes",
    "bslib",
    "thematic",
    "xml2",
    "zeallot",
    "ggspatial",
    "gstat",
    "ggcorrplot",
    "pangear",
    "rnaturalearth",
    "ggtern",
    "S7"
  )

  # Install packages
  # Do not install as one vector passed to function
  # - will fail due to dependencies conflict
  # Instead walk
  packages |>
    purrr::walk(purrr::possibly(\(i) {
      pak::pkg_install(i, ask = FALSE, upgrade = TRUE)
    }))
}
