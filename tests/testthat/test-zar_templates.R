# Test zar_template_* generators ----
# The generators copy a file from inst/templates/, render its {{{mustache}}}
# variables with whisker, and write it into a project directory.
#
# Key contracts, each of which has a test below:
#   - When `path` is a directory the capture is inferred from its basename and
#     the output filename is fixed by the stage.
#   - `sensor` selects both the template file and the rendered `sensor <-` line.
#   - Every placeholder is rendered, and the result is parseable R. air formats
#     inst/templates/, so an unquoted placeholder silently stops substituting.
#   - Path-like arguments are reduced to bare names before rendering.

## Setup ----

# Every generator, the filename it writes, and any arguments it alone needs.
generators <- list(
  preview = list(
    fn = zar_template_preview,
    file = "01_preview.R",
    args = list()
  ),
  reflectance = list(
    fn = zar_template_reflectance,
    file = "02_reflectance.R",
    args = list()
  ),
  coregister = list(
    fn = zar_template_coregister,
    file = "03_coregister.R",
    args = list(vnir_capture = "VNIR_CAP")
  ),
  postprocess = list(
    fn = zar_template_postprocess,
    file = "04_postprocess.R",
    args = list()
  ),
  features = list(
    fn = zar_template_features,
    file = "05_features.R",
    args = list()
  )
)

# Generate one stage into a fresh capture directory and return the written path.
# The temp directory is scoped to the caller, not to this helper: scoped here it
# would be deleted the moment the helper returned, taking the file with it.
generate <- function(
  spec,
  sensor = "swir",
  capture = "CAP_2026",
  ...,
  envir = parent.frame()
) {
  dir <- fs::path(withr::local_tempdir(.local_envir = envir), capture)

  fs::dir_create(dir)

  # The generators report progress with cli_alert_*; testthat 3e no longer
  # swallows it, and it is not what these tests assert on.
  suppressMessages(
    rlang::exec(spec$fn, path = dir, sensor = sensor, !!!spec$args, ...)
  )
}

# ── Output ───────────────────────────────────────────────────────────────────

test_that("zar_template generators write the expected filename", {
  purrr::iwalk(generators, \(spec, stage) {
    path <- generate(spec)

    expect_true(fs::file_exists(path), label = stage)
    expect_equal(fs::path_file(path), spec$file)
  })
})

test_that("zar_template generators infer capture from the directory name", {
  purrr::iwalk(generators, \(spec, stage) {
    lines <- readLines(generate(spec), warn = FALSE)

    expect_true(
      any(grepl('^capture <- "CAP_2026"$', lines)),
      label = stage
    )
  })
})

# ── Rendering ────────────────────────────────────────────────────────────────

test_that("zar_template generators leave no unrendered placeholders", {
  # Regression: `n_components` was once an unquoted {{{ }}}, which air parsed as
  # nested R blocks and rewrote, so substitution silently stopped happening
  # while the generator still reported success.
  purrr::iwalk(generators, \(spec, stage) {
    lines <- readLines(generate(spec), warn = FALSE)

    expect_false(any(grepl("{{", lines, fixed = TRUE)), label = stage)
  })
})

test_that("zar_template generators produce parseable R", {
  purrr::iwalk(generators, \(spec, stage) {
    expect_no_error(parse(generate(spec)))
  })
})

test_that("zar_template generators reduce path-like arguments to bare names", {
  reflectance <- generate(
    generators$reflectance,
    reference = "some/other/WREF_SESSION"
  )

  expect_true(
    any(grepl(
      '^reference <- "WREF_SESSION"$',
      readLines(reflectance, warn = FALSE)
    ))
  )

  coregister <- zar_template_coregister(
    path = fs::dir_create(fs::path(withr::local_tempdir(), "CAP_2026")),
    sensor = "swir",
    vnir_capture = "a/b/VNIR_CAP"
  )

  expect_true(
    any(grepl(
      '^vnir_capture <- "VNIR_CAP"$',
      readLines(coregister, warn = FALSE)
    ))
  )
})

# ── Sensor dispatch ──────────────────────────────────────────────────────────

test_that("zar_template generators render the sensor into the script", {
  purrr::iwalk(generators, \(spec, stage) {
    lines <- readLines(generate(spec, sensor = "swir"), warn = FALSE)

    expect_true(any(grepl('^sensor <- "swir"$', lines)), label = stage)
  })
})

test_that("zar_template_preview selects the sensor-specific template", {
  vnir <- readLines(generate(generators$preview, sensor = "vnir"), warn = FALSE)
  swir <- readLines(generate(generators$preview, sensor = "swir"), warn = FALSE)

  # VNIR previews three visible-range composites; SWIR previews one and adds a
  # flipped copy for viewing only.
  expect_true(any(grepl('"RGB", "CIR", "NIR"', vnir, fixed = TRUE)))
  expect_false(any(grepl("_flipped", vnir, fixed = TRUE)))

  expect_true(any(grepl("_preview_SWIR_flipped.tif", swir, fixed = TRUE)))
})

test_that("zar_template_preview includes the raw-data screens", {
  # Saturation and detection-floor screening can only run before calibration, so
  # preview is the sole stage that can produce them. Losing them here would
  # silently reopen the masking gap rather than fail.
  purrr::walk(c("vnir", "swir"), \(sensor) {
    lines <- readLines(
      generate(generators$preview, sensor = sensor),
      warn = FALSE
    )

    expect_true(
      any(grepl("zarowka::hsi_check_saturation(", lines, fixed = TRUE)),
      label = sensor
    )

    expect_true(
      any(grepl("zarowka::hsi_check_signal(", lines, fixed = TRUE)),
      label = sensor
    )

    expect_true(
      any(grepl('products("_saturated.tif")', lines, fixed = TRUE)),
      label = sensor
    )

    expect_true(
      any(grepl('products("_no_signal.tif")', lines, fixed = TRUE)),
      label = sensor
    )
  })
})

# ── Stage arguments ──────────────────────────────────────────────────────────

test_that("zar_template_postprocess selects the source product", {
  own <- generate(generators$postprocess, coregistered = FALSE)
  warped <- generate(generators$postprocess, coregistered = TRUE)

  expect_true(
    any(grepl('^source_suffix <- ""$', readLines(own, warn = FALSE)))
  )

  expect_true(
    any(grepl('^source_suffix <- "_coreg"$', readLines(warped, warn = FALSE)))
  )
})

test_that("zar_template_features renders n_components as an integer", {
  lines <- readLines(
    generate(generators$features, n_components = 7L),
    warn = FALSE
  )

  expect_true(any(grepl(
    'n_components <- as.integer("7")',
    lines,
    fixed = TRUE
  )))
})

# ── Existing files ───────────────────────────────────────────────────────────

test_that("zar_template generators error when the target already exists", {
  dir <- fs::dir_create(fs::path(withr::local_tempdir(), "CAP_2026"))

  zar_template_preview(dir, sensor = "vnir")

  expect_error(
    zar_template_preview(dir, sensor = "vnir"),
    "already exists"
  )
})

test_that("zar_template generators honour skip and overwrite", {
  dir <- fs::dir_create(fs::path(withr::local_tempdir(), "CAP_2026"))

  path <- zar_template_preview(dir, sensor = "vnir")

  # Mark the file so it is clear whether it survived.
  writeLines("# sentinel", path)

  zar_template_preview(dir, sensor = "vnir", if_exists = "skip")

  expect_equal(readLines(path, warn = FALSE), "# sentinel")

  zar_template_preview(dir, sensor = "vnir", if_exists = "overwrite")

  expect_false(identical(readLines(path, warn = FALSE), "# sentinel"))
})

# ── Input validation ─────────────────────────────────────────────────────────

test_that("zar_template generators reject an unknown sensor", {
  purrr::iwalk(generators, \(spec, stage) {
    expect_error(generate(spec, sensor = "lidar"))
  })
})

test_that("zar_template generators require capture when path is a file", {
  file <- fs::path(withr::local_tempdir(), "somewhere.R")

  expect_error(
    zar_template_preview(file, sensor = "vnir"),
    "Must provide"
  )
})
