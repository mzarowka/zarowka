# zarowka Development Guidelines (CLAUDE.md)

> **Version 1.3.0 — 2026-09-11.** zarowka is the **front-end scaffolding and
> experimental layer** of the HSItools ecosystem. This file carries only what is
> specific to *this* repo. All shared house style — language baseline, function
> structure, roxygen, testing, calibration physics, unmixing restraints — is
> defined canonically in **`../HSItools/CLAUDE.md`** and applies here verbatim
> (its numbered sections repeatedly say "HSItools/zarowka source code"). On any
> conflict, that file wins for shared conventions; this file wins for the
> zarowka-specific rules below. Read both at session start.
>
> This file carries conventions only. Never add milestone state, session notes,
> TODOs, or roadmap items here — those live in dated `YYYY-MM-DD_*.md` documents
> in the private `hsi_development` repo (folder `zarowka/`), never in this repo.
> Never modify this file unless Maury explicitly asks.

---

## 0. How to work on this project (read first)

The behavioral rules in `../HSItools/CLAUDE.md` §0 apply here **unchanged** and
outrank everything below. In summary:

1. **Approach before code.** Talk contract and design first; never code immediately.
2. **One change at a time.** Propose one change, let Maury run tests, then continue.
3. **No speculative generalization / no hardcoding.** Simple, reusable, atomic functions.
4. **Do not settle open design questions unilaterally.** Ask.
5. **Verification runs where R lives.** If this session can execute in the repo:
   after each change run the focused tests for the touched file,
   `devtools::test_active_file("R/<name>.R")` (plus `devtools::document()` when a
   roxygen block or signature changed), show the output, wait for go/no-go; run the
   full `devtools::test()` before handing work back. Commands: §2.
   If it cannot execute R, hand off patches; Maury verifies locally. Never claim a
   verification step ran unless its output was shown or Maury reported it.
6. **Git belongs to Maury.** Read-only inspection (`git status`/`diff`/`log`) only;
   never `add`/`commit`/`checkout`/`branch`/`merge`/`push`/`stash`/`restore`.

---

## 1. What zarowka is, and where it sits

Three packages, one workflow (see `../HSItools/CLAUDE.md` §1 for the full ecosystem):

| Package | Role |
|---|---|
| **HSItools** (`mzarowka/HSItools`) | Core package: processing, analysis, visualization of hyperspectral raster data. Stable, CRAN-quality, sensor-/manufacturer-/material-agnostic. |
| **zarowka** (this repo) | Front-end scaffolding layer: workflow **templates** and **experimental functions**. Battle-tests new functionality before promotion to HSItools. |
| **hsical** | Standalone Shiny calibration/logger app. Never touches spectral data. |

**Promotion flow (the reason zarowka exists):** new functionality lands in zarowka
first, proves itself in real analyses, and is promoted to HSItools only once the
pattern holds. zarowka is therefore allowed to be less finished than HSItools — but
its analysis functions (`hsi_*`) are written *as if* they were already in HSItools,
so promotion is a move, not a rewrite.

**zarowka may carry the domain specificity HSItools may not.** HSItools function
contracts must stay agnostic (no Specim/Lumo/sediment/wavelength-range assumptions;
`../HSItools/CLAUDE.md` §1 is imperative). Instrument- and material-specific
knowledge lives *here*, concentrated in the templates (`inst/templates/`): they
name VNIR/SWIR sensors, Lumo capture layout, `.raw`/`.hdr` conventions, matched-dark
fallback, the core directory structure. Keep that specificity in templates and
scaffolding, never in a function contract intended for promotion.

**Dependency positioning.** `DESCRIPTION` pulls HSItools and `unmixR` via `Remotes:`
(`mzarowka/HSItools@dev`, `r-hyperspec/unmixR`). This is deliberate: **`unmixR` is
never a dependency of HSItools** (`../HSItools/CLAUDE.md` §7) — endmember *search*
is not core functionality, and unmixR is GitHub-only. zarowka is where search
(VCA/N-FINDR via unmixR) is allowed to live. Guard every unmixR touch with
`rlang::check_installed("unmixR")` (it is `Suggests`, not `Imports`).

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

Always pass an explicit path to `test_active_file()`: without one it targets the
file open in the IDE editor, which an agent session does not have. The Windows
`Rscript -e` segfault fallback in `../HSItools/CLAUDE.md` (Repo map → Commands)
applies here.

Formatting is owned by **air** (`air.toml` at the repo root marks the project). Run
`air format` on any file you edit before handing work back. Never hand-format.

### Two layers of source, two levels of strictness

`R/` holds two distinct function families. **Read the prefix to know which rules apply.**

**`hsi_*` — the experimental analysis layer.** Follows the full HSItools house
style verbatim (`../HSItools/CLAUDE.md` §§2–5): `|>` not `%>%`, `\(i)` not
`function(i)`, `purrr` not loops/apply, explicit `pkg::fn()`, `cli::cli_abort()`
for validation, the `# Validate inputs` / `# Return result` structural comments,
`@family` roxygen tags, and the Shape A / Shape B return contract. These are the
promotion candidates — hold them to HSItools standard.

Current inventory (all `@family HSI Unmixing` / extraction / QC): `hsi_extract_spectra()`,
`hsi_calc_endmembers()` (VCA-seeded N-FINDR via unmixR), `hsi_calc_abundance()`
(nnls), `hsi_calc_sam()`, `hsi_sam_dist()`, `hsi_apply_reduction()`,
`hsi_plot_endmembers()`, `hsi_calc_snr()`, `hsi_check_signal()`. These realize
the unmixing/big-raster workflow whose hard-won restraints are documented in
`../HSItools/CLAUDE.md` §7 — read §7 before touching any of them. Note the §3.2
dots-check **exemption** covers `hsi_apply_reduction()` and any function that hands
`filename`/`wopt` straight to a terra primitive.

**`zar_*` — the scaffolding layer.** User-facing project setup helpers, deliberately
looser than the analysis house style because they orchestrate the filesystem and
package installs, not spectral data:

- `zar_set()` / `zar_install()` / `zar_hsitools()` / `zar_update()` — `pak`-based
  environment setup (install Maury's package set, install HSItools from a branch, update).
- `zar_create_core()` — create a `core/{vnir,swir}` directory scaffold with a `.here` anchor.
- `zar_template_*()` — copy and render a workflow template into a project directory.

The scaffolding layer uses `fs::` for path work, `cli::cli_alert_*()` for
interactive progress (not the analysis layer's `cli_inform`), `match.arg()` for the
`if_exists`/`branch` switches, and `whisker::` for templating. This is idiomatic
`usethis`-style scaffolding and is **intentionally not held to the analysis
function contract** (no Shape A/B return, no `check_*` block, no `@family`). Do not
"correct" a `zar_*` helper toward the strict style, and do not carry `match.arg()`
or `cli_alert_*` from here into an `hsi_*` function.

### Templates (`inst/templates/`)

The `zar_template_*()` functions copy these files, rendering `{{{var}}}` triple-mustache
placeholders via `whisker::whisker.render()` (`use_template()` internal helper in
`R/zar_templates.R`). Templates are **rendered analysis scripts, not package code**:
they use `library()`, RStudio `# ---- section ----` dividers, and lab-specific
paths freely — none of the `R/` source prohibitions apply inside a template.

Current templates and their generators:

| Template file | Generator | Output name |
|---|---|---|
| `preview_vnir.R` / `preview_swir.R` | `zar_template_preview(sensor =)` | `01_preview.R` |
| `reflectance.R` | `zar_template_reflectance()` | `02_reflectance.R` |
| `coregister.R` | `zar_template_coregister()` | `03_coregister.R` |
| `postprocess.R` | `zar_template_postprocess()` | `04_postprocess.R` |
| `features.R` | `zar_template_features()` | `05_features.R` |

Generator convention: when `path` is a directory, the capture name is inferred from
the directory and the output filename is fixed; when `path` is a file, `capture`
must be supplied. `if_exists` is `"error"` / `"skip"` / `"overwrite"`. Path-like
whisker variables (`capture`, `reference`, `darkspec`, `vnir_capture`) are sanitised
to bare names via `fs::path_file()` before rendering.

### Tests and fixtures

testthat 3e (`Config/testthat/edition: 3`); test files mirror `R/` as
`test-<function_name>.R`. Only the `hsi_*` analysis functions have tests — the
`zar_*` scaffolding is not unit-tested. Full testing standard: `../HSItools/CLAUDE.md` §5.

Test fixtures under `inst/testdata/` **mirror the HSItools fixture chain** exactly
(referenced via `system.file(package = "zarowka", "testdata/...")`):

- `capture/` — `testdata.tif`, `WHITEREF_testdata.tif`, `DARKREF_testdata.tif`
- `products/` — `REFLECTANCE_` → `MEDIAN_` → `SAVGOL_` → `CONREM_testdata.tif`

Same 517.58–772.19 nm wavelength constraint as HSItools; safe happy-path
wavelengths `c(700, 620, 540)` (`../HSItools/CLAUDE.md` §5.2).

---

## 3. zarowka-specific conventions

Everything not listed here defers to `../HSItools/CLAUDE.md`. The points below are
where zarowka genuinely differs or adds:

1. **Prefix decides the ruleset.** `hsi_*` → strict analysis house style (promotion
   candidates). `zar_*` → looser scaffolding style. Never mix the two.
2. **Domain specificity is welcome in templates, banned in `hsi_*` contracts.**
   A function that only makes sense for cores or for one vendor is a template
   detail, not a promotable function (`../HSItools/CLAUDE.md` §1).
3. **`unmixR` is `Suggests` + `Remotes` only.** Guard with
   `rlang::check_installed("unmixR")`; never move it to `Imports`; never assume it
   in HSItools.
4. **Reduction fits are passed in, not fitted inside.** `hsi_calc_endmembers()` and
   the reduction workflow take an already-fitted model (`stats::prcomp(...)`) so a
   single fit is reused across refits and survives a session restart via `saveRDS()`.
   PCA over MNF for pooled unmixing (`../HSItools/CLAUDE.md` §7).
5. **Over-specify then prune; never re-search at lower `n`.** N-FINDR sheds
   spectrally distinct low-abundance vertices when `n` drops. Subset columns of
   `em$spectra` instead (`../HSItools/CLAUDE.md` §7).
6. **Endmember container shape** matches the ecosystem convention: a named list
   with `$spectra` (bands × endmembers, reflectance space) and location/index
   companions. The S3 formalization of this lives in HSItools (`../HSItools/CLAUDE.md`
   §7, §10) — track it, don't fork it here.
7. **Masking precedes unmixing, always.** Background/tray pixels corrupt endmember
   search. `../HSItools/CLAUDE.md` §7.
8. **Dated docs live in the private `hsi_development` repo** (folder `zarowka/`),
   moved there 2026-07-18 — never in package source or this file. The `dev-notes/`
   entries in `.gitignore`/`.Rbuildignore` stay as a safety net; the folder itself
   no longer exists here.
9. **Templates cut a raw capture with `terra::window()`, never `terra::crop()`.**
   A crop that materialises reserves the datatype maximum as NoData and silently
   turns saturated readings into `NA`; a window is lazy and writes nothing.
   Reference rasters are windowed in the column direction only, since
   `hsi_calc_reflectance()` collapses them to per-column means and sweeps those
   across the specimen's columns. Reasoning and measurements in
   `../HSItools/CLAUDE.md` §2.
10. **The saturation screen is applied; the signal screen is not.**
    `02_reflectance.R` masks the calibrated product with the collapsed saturation
    screen, dropping any pixel that clipped in any band, on the raw pixel grid and
    before `03_coregister.R`. The signal screen is written and left alone: what
    counts as too dark is a judgement about the material, so the user applies it
    in the GIS. Physics and composition rule in `../HSItools/CLAUDE.md` §6.6.
11. **Enumerated strings use `rlang::arg_match()`.** The house validator
    `check_one_of()` is internal to HSItools and unreachable without `:::`, so the
    sanctioned rlang carve-out (`../HSItools/CLAUDE.md` §3.3) applies here.
    Never `match.arg()`, and never a house duplicate.
12. **Release-surface rules from HSItools do not apply here.** zarowka keeps no
    `NEWS.md` and no `_pkgdown.yml`, so the NEWS and pkgdown rules
    (`../HSItools/CLAUDE.md` §9, §4.8) are dormant until those files exist. The
    deprecation workflow (§3.12 there) does not apply either: zarowka functions are
    experimental, and promotion moves a function to HSItools without a deprecation
    cycle here.

---

## 4. Quick pre-flight checklist

Before proposing any zarowka code, confirm:

1. Approach discussed first? (No code before design agreement — §0.)
2. Which layer? `hsi_*` → hold to the full HSItools contract
   (`../HSItools/CLAUDE.md` §§2–5, §7); `zar_*` → scaffolding style, don't over-strictify.
3. For `hsi_*`: argument order §3.1, `check_*` + `cli::cli_abort()` validation block,
   `hsitools_error` umbrella, Shape A/B return, verbatim structural comments,
   `|>`/`\(i)`/`purrr`/`::`, roxygen §4 — all per `../HSItools/CLAUDE.md`.
4. Touching unmixing? Re-read `../HSItools/CLAUDE.md` §7 (bind-first, over-specify-then-prune,
   PCA-over-MNF, mask-first) and guard `unmixR` with `check_installed()`.
5. Domain/vendor specificity going into an `hsi_*` contract? Move it to a template instead.
6. Tests per `../HSItools/CLAUDE.md` §5 (no code outside `test_that()`, fixtures in
   `helper-*.R`, specific expectations); fixtures from the mirrored `inst/testdata/` chain.
7. Touching anything in `../HSItools/CLAUDE.md` §10 (open design questions)? Stop and ask.

---

## Changelog

- **1.3.0 (2026-09-11)** — Follows `../HSItools/CLAUDE.md` 1.12.0 (tidyverse agent
  guidance from usethis 3.2.2). §0 rule 5 runs focused tests per change and the full
  suite before handback; §2 gains the focused test commands, the path-less
  `test_active_file()` warning and a pointer to the Windows `Rscript -e` fallback.
  §3 gains rule 12: NEWS and pkgdown rules are dormant (no `NEWS.md`/`_pkgdown.yml`),
  and the deprecation workflow does not apply to experimental functions or
  promotion. §4 checklist item 6 picks up the new test rules.
- **1.2.0 (2026-09-10)** — `hsi_check_saturation()` promoted to HSItools
  (0.5.3.9003), so it leaves the §2 inventory and the templates call it through that
  namespace; `DESCRIPTION` gains the matching version floor. §3 gains rule 10 (the
  saturation screen is applied by `02_reflectance.R`, the signal screen is left to
  the user) and rule 11 (enumerated strings use `rlang::arg_match()`, since
  `check_one_of()` is internal to HSItools; the seven `match.arg()` calls were
  converted). Saturation physics lives in `../HSItools/CLAUDE.md` §6.6.
- **1.1.0 (2026-09-10)** — §3 gains rule 9: templates cut a raw capture with
  `terra::window()`, never `terra::crop()`, references in the column direction only
  (`../HSItools/CLAUDE.md` §2 carries the reasoning and the measurements). Applied in
  `inst/templates/reflectance.R` the same day; validation in
  `hsi_development/zarowka/2026-09-09_window-reflectance-gkut-validation-opus.md`.
  §2's template table corrected: it listed sensor-split `reflectance_*.R` /
  `postprocess_*.R` / `features_*.R` files and generators that no longer exist. The
  real inventory is six templates behind five `zar_template_*()` generators emitting
  `01_preview.R` through `05_features.R`.
- **1.0.0 (2026-07-15)** — Initial zarowka CLAUDE.md, derived from `../HSItools/CLAUDE.md`
  v1.8.0. Scopes this file to zarowka-specific facts (two-layer `hsi_*`/`zar_*` source,
  templates in `inst/templates/`, unmixR positioning, mirrored testdata) and defers all
  shared house style to the canonical HSItools file.
