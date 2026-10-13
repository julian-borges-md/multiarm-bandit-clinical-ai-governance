# Changelog

All notable changes to this repository are recorded here. The format follows Keep a Changelog; versions follow semantic versioning.

## [2.1.0] - 2026-10-13

Pre review strengthening. Results of version 2.0.0 are unchanged; the primary analysis is identical.

### Added
- Utility functional sensitivity: `reward.utility` in `config/params.yml` selects one minus the Brier loss (primary) or binary correctness at the operating threshold; the primary scenario is repeated under the alternative utility (`outputs/results/sensitivity_utility.csv`, `implied_sample_complexity_utility.csv`, Table 16 and Table 18)
- Patient level percentile bootstrap of the arm means, reward gaps and implied sample sizes on the deployment stream (`gap_bootstrap()` in `analysis/R/lib/policies.R`; `outputs/results/gap_bootstrap.csv`, Table 17)
- Unit tests for the accuracy utility and for the bootstrap (determinism, dimensions, recovery of the full sample gaps)

### Changed
- `composite_reward()`, `reward_matrix()` and `make_extra()` take a `utility` argument (default `"brier"`); `04_run_bandit_simulation.R` passes it through every scenario and records it in `simulation_meta.json`
- Static comparators are chosen on validation under each scenario's utility as well as its weights

## [2.0.0] - 2026-10-13

Complete re analysis. Version 1.0.0 is superseded; its results must not be cited.

### Why
An audit on 2026-10-12 found that the version 1.0.0 pipeline (a) trained and evaluated the three models on the same 3,000 stays (in sample AUROC 1.000 and 0.9999), (b) used an epsilon greedy placeholder instead of the fixed confidence elimination policy described in the manuscript, with no delayed feedback and no safety term, (c) selected comparator strategies in hindsight on the evaluation stream, and (d) reported quantities in the preprint that the code never computed. The posted preprint (Research Square, 10.21203/rs.3.rs-8651972/v1) therefore reports results that could not be reproduced from the archived code. Version 2.0.0 rebuilds the analysis so that every reported number is produced by one run of the pipeline.

### Added
- Subject level development set (anchor year groups 2008 to 2019) and a temporally external deployment stream (2020 to 2022); ICU length of stay of at least 24 hours so that the feature window is fully observed
- DuckDB based extraction with explicit, dictionary verified item identifiers; blood pressure and Glasgow Coma Scale concepts that version 1.0.0 silently failed to map
- Three frozen arms with distinct operational footprints, Platt calibration and operating thresholds fixed on a validation split
- Composite reward with cost and safety penalties, rescaled to [0, 1]
- Fixed confidence action elimination with Hoeffding and empirical Bernstein anytime bounds, a context stratified variant, Thompson sampling, UCB1, uniform random, static deployment, ensemble averaging and heuristic escalation
- Delayed feedback queue with Poisson arrivals and uniform 6 to 72 hour delays; leakage assertion
- 100 replicate simulation with paired percentile bootstrap comparisons; sensitivity grids over reward weights, confidence level and delay; implied sample complexity table
- Synthetic data mode, testthat suite, GitHub Actions CI, run manifest with environment capture and MIMIC-IV file hashes, Docker recipe

### Changed
- Repository layout: `analysis/R/lib`, `config/params.yml`, `tests/`, `docs/`; all parameters moved out of scripts
- README, CITATION.cff (concept DOI, ORCID, version, release date), REPRODUCE.md and docs rewritten

### Removed
- `06_make_comparator_results` (hindsight comparators), `activate.R` at the repository root, the 0.1.0 version string

### Note on the archived run
The run manifest in `outputs/results/run_manifest.json` records commit a99b646, the analysis code of this release; the only later change before the tag adds the R.utils dependency to the installation instructions and CI.

### Provenance note
The GitHub history before this release consists of a single commit dated 2026-05-19. The Zenodo 1.0.0 archive (md5 96e6d441a3d1b48a75113c7662ffa9f2) corresponds to the January 2026 working copy and cannot be mapped to a commit; from 2.0.0 onward every archived version is a tagged commit.

## [1.0.0] - 2026-01-14

Initial archive on Zenodo (10.5281/zenodo.18248286). Superseded.
