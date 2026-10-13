# Changelog

All notable changes to this repository are recorded here. The format follows Keep a Changelog; versions follow semantic versioning.

## Repository history note (2026-10-13)

The commit history was rewritten on 2026-10-13 to remove trailer lines from commit messages. No file changed: every rewritten commit carries the same tree, author, dates and tag message as before, and the Zenodo archives are unaffected. Commit identifiers changed, so the `git_commit` field of the archived run manifests records the pre rewrite identifier of the tree that produced the outputs. The correspondence is:

| Run manifest identifier | Public commit (same tree) | Role |
|---|---|---|
| a99b646fdf39 | 5f6ed3fbf609 | analysis code of 2.0.0 |
| 1c98635417ce | 8efff08421c5 | archived outputs of 2.0.0 |
| 8e6ac302bdea | 0acaa0b5b8f1 | tag v2.0.0 |
| 29fb27e80281 | f9875be71307 | analysis code of 2.1.0 |
| 536d6e9eecac | 7c652090455d | tag v2.1.0 |
| 7b5703a7ede8 | ec6e3820a0a7 | pipeline 3.0.0 code |
| 6c7a0f160db5 | a7742eee9c0f | analysis code of 3.0.0 (recorded in both 3.0.0 run manifests) |
| 75331dc4b8ec | 3beebaf2d5b9 | tag v3.0.0 |

Tree identity can be checked with `git rev-parse <commit>^{tree}` on both sides of a pair; the pre rewrite history is retained offline by the author.

## [3.0.0] - 2026-10-13

Revision after independent technical review of the version 2 manuscript. The analysis changes in ways that alter the printed numbers, so this release supersedes 2.x; the direction of every finding is unchanged.

### Changed (results affected)
- Development stays are restricted to those whose real calendar window ends before 2020, so that every development stay precedes every deployment stay in calendar time; version 2 retained one random stay per patient regardless of the years elapsed since the anchor year, and 11 percent of its development stays could have occurred in 2020 or later (`cohort.development_stay_rule`, `01_build_cohort.R`)
- The deployment stream is drawn with its own seed (`seed_split + 1`), independent of the development sampling
- Arm C is tuned by the same protocol as arms A and B (candidate variables per split and minimum node size selected by log loss on the early stopping half of the validation set)
- `implied_sample_size()` finds the exact smallest sample by bisection; the 5 percent geometric grid of version 2 overstated the implied samples by up to 5 percent (arm C: 7,859 printed against 7,621 exact at the version 2 gaps)
- Stratification for the stratified variant uses availability of all three extended laboratory tests (version 2 used any of the three, which left two strata with 229 and 260 stays)

### Added
- False positive (alert burden) term `lambda_false_positive` in the composite reward, 0 in the primary analysis, with a sensitivity grid and the break even weight at which the preferred arm changes (`false_positive_break_even.csv`)
- Per decision cost matrices; acquisition conditional costing scenario in which arm C is charged at arm B's cost when the extended panel is absent (`sensitivity_acquisition_cost.csv`)
- Cost vector sensitivity (compressed, expanded, equal) with implied sample complexity under each (`sensitivity_cost_vector.csv`, `implied_sample_complexity_scenarios.csv`)
- Drift scenarios in which the validation chosen arm becomes inferior on the stream (Gaussian noise on the logit of arm A, standard deviation 1.5 or 4.0, from the start or from one third of the stream), each under three delay settings (`sensitivity_drift.csv`, `drift_scenario_description.csv`)
- Thompson sampling with a Gaussian posterior on the reward moments (`thompson_gauss`), alongside the Bernoulli reduction variant
- Signed sensitivity gaps by age and sex, the share weighted disparity a patient experiences under a mixing policy, and the sensitivity range across race groups; per arm subgroup sensitivities with Wilson intervals (`arm_subgroup_sensitivity.csv`)
- Outcomes available per arm, shortfall factors and the confidence level at which the available sample would suffice (`required_delta()`) in the implied sample complexity tables
- Three arrival rates (database, stream own, guaranteed recent) in `stream_meta.json`; distribution of years between anchor year and stay by split (`stay_offset_distribution.csv`); race distribution and the share of stays within the anchor year in the cohort characteristics
- DeLong intervals and sensitivities in the stratum performance table; Figure 1 shows the analysis sets; Figure 3 panels follow the legend order
- `PARAMS_FILE` environment variable and `config/params_recent_window.yml` for the development window sensitivity analysis (development pool restricted to patients anchored in 2017 to 2019); the run manifest records the parameter file
- Unit tests for the false positive term, cost matrices, the exact search, `required_delta()`, the Gaussian variant and the signed disparity metrics (25 test blocks)

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
The run manifest in `outputs/results/run_manifest.json` records commit a99b646 (public commit 5f6ed3f after the history note above), the analysis code of this release; the only later change before the tag adds the R.utils dependency to the installation instructions and CI.

### Provenance note
The GitHub history before this release consists of a single commit dated 2026-05-19. The Zenodo 1.0.0 archive (md5 96e6d441a3d1b48a75113c7662ffa9f2) corresponds to the January 2026 working copy and cannot be mapped to a commit; from 2.0.0 onward every archived version is a tagged commit.

## [1.0.0] - 2026-01-14

Initial archive on Zenodo (10.5281/zenodo.18248286). Superseded.
