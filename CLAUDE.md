# zarowka development conventions (CLAUDE.md)

> **Version 1.4.0 — 2026-09-24.** zarowka is the **scaffolding and experimental layer** on top
> of **HSItools**. This file carries only what is specific to zarowka. All shared house style —
> language baseline, function structure, roxygen, testing, calibration physics, unmixing
> restraints — is defined in HSItools' own `CLAUDE.md` and `.claude/rules/`, and applies here
> verbatim. On a conflict, HSItools wins for shared conventions and this file wins for the
> zarowka-specific rules below. Section numbers cited as "HSItools §n" refer to that file.
>
> **Loading HSItools' conventions.** Claude Code only auto-loads this repo's `CLAUDE.md`. With
> HSItools checked out alongside, put `@`-imports of its `CLAUDE.md` and `.claude/rules/*.md`
> in a `CLAUDE.local.md` here (gitignored, personal, never committed) so they load in every
> zarowka session. Without it, read HSItools' conventions before writing `hsi_*` code.
>
> Conventions only — no milestone state, session notes or TODOs. Personal workflow preferences
> belong in each developer's own Claude Code configuration, not here.

---

## 1. What zarowka is, and where it sits

| Package | Role |
|---|---|
| **HSItools** (`mzarowka/HSItools`) | Core package: processing, analysis, visualization of hyperspectral raster data. Stable, CRAN-quality, sensor-/manufacturer-/material-agnostic. |
| **zarowka** (this repo) | Scaffolding layer: workflow **templates** and **experimental functions**. Battle-tests new functionality before promotion to HSItools. |

**Promotion flow (the reason zarowka exists):** new functionality lands in zarowka first, proves
itself in real analyses, and is promoted to HSItools only once the pattern holds. zarowka is
therefore allowed to be less finished than HSItools — but its analysis functions (`hsi_*`) are
written *as if* they were already in HSItools, so promotion is a move, not a rewrite.

**zarowka may carry the domain specificity HSItools may not.** HSItools function contracts must
stay agnostic (no material-, vendor- or wavelength-range-specific assumptions; HSItools §1 is
imperative). Instrument- and material-specific knowledge lives *here*, concentrated in the
templates (`inst/templates/`): they name VNIR/SWIR sensors, the Lumo capture layout,
`.raw`/`.hdr` conventions, matched-dark fallback, the core directory structure. Keep that
specificity in templates and scaffolding, never in a function contract intended for promotion.

**Dependency positioning.** `DESCRIPTION` pulls HSItools and `unmixR` via `Remotes:`
(`mzarowka/HSItools@dev`, `r-hyperspec/unmixR`). This is deliberate: **`unmixR` is never a
dependency of HSItools** (HSItools §7) — endmember *search* is not core functionality, and
unmixR is GitHub-only. zarowka is where search (VCA/N-FINDR via unmixR) is allowed to live.
Guard every unmixR touch with `rlang::check_installed("unmixR")` (it is `Suggests`, not
`Imports`).

---

## 2. Repo map and mechanics

Standard R package. All commands run from the package root in R:

```r
devtools::load_all()          # load for interactive dev
devtools::test()              # full testthat 3e suite
devtools::test(filter = "hsi_check_signal")           # test files matching a regex
devtools::test_active_file("R/hsi_check_signal.R")    # tests for one source file (R/x.R -> tests/testthat/test-x.R)
devtools::test_active_file("R/hsi_check_signal.R", desc = "<exact test name>")  # a single test, no regex
devtools::document()          # regenerate NAMESPACE + man/*.Rd after any roxygen change
devtools::check()             # full R CMD check
```

Always pass an explicit path to `test_active_file()`: without one it targets the file open in
the IDE editor, which an agent session does not have. The Windows `Rscript -e` fallback in
HSItools' `CLAUDE.md` (Repo map → Commands) applies here.

Formatting is owned by **air** (`air.toml` at the repo root marks the project). Run
`air format` on any file you edit before handing work back. Never hand-format.

### Two layers of source, two levels of strictness

`R/` holds two distinct function families. **Read the prefix to know which rules apply.**

**`hsi_*` — the experimental analysis layer.** Follows the full HSItools house style verbatim
(HSItools §§2–5): `|>` not `%>%`, `\(i)` not `function(i)`, `purrr` not loops/apply, explicit
`pkg::fn()`, `cli::cli_abort()` for validation, the `# Validate inputs` / `# Return result`
structural comments, `@family` roxygen tags, and the Shape A / Shape B return contract. These
are the promotion candidates — hold them to HSItools standard.

Current inventory (all `@family HSI Unmixing` / extraction / QC): `hsi_extract_spectra()`,
`hsi_calc_endmembers()` (VCA-seeded N-FINDR via unmixR), `hsi_calc_abundance()` (nnls),
`hsi_calc_sam()`, `hsi_sam_dist()`, `hsi_apply_reduction()`, `hsi_plot_endmembers()`,
`hsi_calc_snr()`, `hsi_check_signal()`. These realize the unmixing/big-raster workflow whose
hard-won restraints are HSItools §7 — read §7 before touching any of them. The HSItools §3.2
dots-check **exemption** covers `hsi_apply_reduction()` and any function that hands
`filename`/`wopt` straight to a terra primitive.

**`zar_*` — the scaffolding layer.** User-facing project setup helpers, deliberately looser than
the analysis house style because they orchestrate the filesystem and package installs, not
spectral data:

- `zar_set()` / `zar_install()` / `zar_hsitools()` / `zar_update()` — `pak`-based environment
  setup (install the lab's package set, install HSItools from a branch, update).
- `zar_create_core()` — create a `core/{vnir,swir}` directory scaffold with a `.here` anchor.
- `zar_template_*()` — copy and render a workflow template into a project directory.

The scaffolding layer uses `fs::` for path work, `cli::cli_alert_*()` for interactive progress
(not the analysis layer's `cli_inform`), `match.arg()` for the `if_exists`/`branch` switches,
and `whisker::` for templating. This is idiomatic `usethis`-style scaffolding and is
**intentionally not held to the analysis function contract** (no Shape A/B return, no `check_*`
block, no `@family`). Do not "correct" a `zar_*` helper toward the strict style, and do not
carry `match.arg()` or `cli_alert_*` from here into an `hsi_*` function.

### Templates (`inst/templates/`)

The `zar_template_*()` functions copy these files, rendering `{{{var}}}` triple-mustache
placeholders via `whisker::whisker.render()` (`use_template()` internal helper in
`R/zar_templates.R`). Templates are **rendered analysis scripts, not package code**: they use
`library()`, RStudio `# ---- section ----` dividers, and lab-specific paths freely — none of the
`R/` source prohibitions apply inside a template.

| Template file | Generator | Output name |
|---|---|---|
| `preview_vnir.R` / `preview_swir.R` | `zar_template_preview(sensor =)` | `01_preview.R` |
| `reflectance.R` | `zar_template_reflectance()` | `02_reflectance.R` |
| `coregister.R` | `zar_template_coregister()` | `03_coregister.R` |
| `postprocess.R` | `zar_template_postprocess()` | `04_postprocess.R` |
| `features.R` | `zar_template_features()` | `05_features.R` |

Generator convention: when `path` is a directory, the capture name is inferred from the
directory and the output filename is fixed; when `path` is a file, `capture` must be supplied.
`if_exists` is `"error"` / `"skip"` / `"overwrite"`. Path-like whisker variables (`capture`,
`reference`, `darkspec`, `vnir_capture`) are sanitised to bare names via `fs::path_file()`
before rendering.

### Tests and fixtures

testthat 3e (`Config/testthat/edition: 3`); test files mirror `R/` as `test-<function_name>.R`.
Only the `hsi_*` analysis functions have tests — the `zar_*` scaffolding is not unit-tested.
Full testing standard: HSItools §5.

Test fixtures under `inst/testdata/` **mirror the HSItools fixture chain** exactly (referenced
via `system.file(package = "zarowka", "testdata/...")`):

- `capture/` — `testdata.tif`, `WHITEREF_testdata.tif`, `DARKREF_testdata.tif`
- `products/` — `REFLECTANCE_` → `MEDIAN_` → `SAVGOL_` → `CONREM_testdata.tif`

Same 517.58–772.19 nm wavelength constraint as HSItools; safe happy-path wavelengths
`c(700, 620, 540)` (HSItools §5.2).

---

## 3. zarowka-specific conventions

Everything not listed here defers to HSItools' conventions. The points below are where zarowka
genuinely differs or adds:

1. **Prefix decides the ruleset.** `hsi_*` → strict analysis house style (promotion
   candidates). `zar_*` → looser scaffolding style. Never mix the two.
2. **Domain specificity is welcome in templates, banned in `hsi_*` contracts.** A function that
   only makes sense for cores or for one vendor is a template detail, not a promotable function
   (HSItools §1).
3. **`unmixR` is `Suggests` + `Remotes` only.** Guard with `rlang::check_installed("unmixR")`;
   never move it to `Imports`; never assume it in HSItools.
4. **Reduction fits are passed in, not fitted inside.** `hsi_calc_endmembers()` and the
   reduction workflow take an already-fitted model (`stats::prcomp(...)`) so a single fit is
   reused across refits and survives a session restart via `saveRDS()`. PCA over MNF for pooled
   unmixing (HSItools §7).
5. **Over-specify then prune; never re-search at lower `n`.** N-FINDR sheds spectrally distinct
   low-abundance vertices when `n` drops. Subset columns of `em$spectra` instead (HSItools §7).
6. **Endmember container shape** matches the HSItools convention: a named list with `$spectra`
   (bands × endmembers, reflectance space) and location/index companions. The S3 formalization
   of this lives in HSItools (§7, §10) — track it, don't fork it here.
7. **Masking precedes unmixing, always.** Background/tray pixels corrupt endmember search
   (HSItools §7).
8. **No dated documents in this repo.** Planning notes, handoffs and roadmaps live outside the
   package repository. The `dev-notes/` entries in `.gitignore`/`.Rbuildignore` stay as a
   safety net.
9. **Templates cut a raw capture with `terra::window()`, never `terra::crop()`.** A crop that
   materialises reserves the datatype maximum as NoData and silently turns saturated readings
   into `NA`; a window is lazy and writes nothing. Reference rasters are windowed in the column
   direction only, since `hsi_calc_reflectance()` collapses them to per-column means and sweeps
   those across the specimen's columns. Reasoning and measurements: HSItools §2.
10. **The saturation screen is applied; the signal screen is not.** `02_reflectance.R` masks the
    calibrated product with the collapsed saturation screen, dropping any pixel that clipped in
    any band, on the raw pixel grid and before `03_coregister.R`. The signal screen is written
    and left alone: what counts as too dark is a judgement about the material, so the user
    applies it in the GIS. Physics and composition rule: HSItools §6.6.
11. **Enumerated strings use `rlang::arg_match()`.** The house validator `check_one_of()` is
    internal to HSItools and unreachable without `:::`, so the sanctioned rlang carve-out
    (HSItools §3.3) applies here. Never `match.arg()`, and never a house duplicate.
12. **Release-surface rules from HSItools do not apply here.** zarowka keeps no `NEWS.md` and no
    `_pkgdown.yml`, so the NEWS and pkgdown rules (HSItools §9, §4.8) are dormant until those
    files exist. The deprecation workflow (HSItools §3.12) does not apply either: zarowka
    functions are experimental, and promotion moves a function to HSItools without a
    deprecation cycle here.

---

## 4. Quick pre-flight checklist

Before proposing any zarowka code, confirm:

1. Which layer? `hsi_*` → hold to the full HSItools contract (HSItools §§2–5, §7); `zar_*` →
   scaffolding style, don't over-strictify.
2. For `hsi_*`: argument order §3.1, `check_*` + `cli::cli_abort()` validation block,
   `hsitools_error` umbrella, Shape A/B return, verbatim structural comments,
   `|>`/`\(i)`/`purrr`/`::`, roxygen §4 — all per HSItools.
3. Touching unmixing? Re-read HSItools §7 (bind-first, over-specify-then-prune, PCA-over-MNF,
   mask-first) and guard `unmixR` with `check_installed()`.
4. Domain/vendor specificity going into an `hsi_*` contract? Move it to a template instead.
5. Tests per HSItools §5 (no code outside `test_that()`, fixtures in `helper-*.R`, specific
   expectations); fixtures from the mirrored `inst/testdata/` chain.
6. Touching anything in HSItools §10 (open design questions)? Stop and ask.
