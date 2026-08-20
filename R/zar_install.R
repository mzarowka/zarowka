#' Install Maury's choice of packages with pak
#'
#' @returns `NULL`, invisibly.
#'
#' @export
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
    "S7",
    "bundle",
    "vip",
    "plsmod",
    "svglite",
    "supercells",
    "glmnet",
    "leaflet",
    "withr",
    "carrier",
    "ggvegan",
    "automap",
    "fields",
    "rcartocolor",
    "spatialsample",
    "devtools",
    "targets",
    "tarchetypes"
  )

  # Install one at a time; a single vector install has conflicted historically.
  # Collect failures instead of swallowing them.
  results <- packages |>
    purrr::map(purrr::safely(\(pkg) {
      pak::pkg_install(pkg, ask = FALSE, upgrade = TRUE)
    }))

  failed <- packages[purrr::map_lgl(results, \(r) !is.null(r$error))]

  if (length(failed) > 0) {
    cli::cli_warn(c(
      "Failed to install {length(failed)} of {length(packages)} package{?s}:",
      "x" = "{.pkg {failed}}"
    ))
  } else {
    cli::cli_alert_success("Installed all {length(packages)} packages.")
  }

  invisible(NULL)
}
