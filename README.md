# Multi armed bandit governance for clinical AI deployment

Simulation framework for adaptive selection among frozen, independently validated ICU mortality prediction models under delayed outcome feedback, explicit cost and safety weights, and fixed confidence action elimination. Evaluated on MIMIC-IV v3.1 with a temporally external deployment stream.

[![CI](https://github.com/julian-borges-md/multiarm-bandit-clinical-ai-governance/actions/workflows/ci.yml/badge.svg)](https://github.com/julian-borges-md/multiarm-bandit-clinical-ai-governance/actions/workflows/ci.yml)
[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Zenodo (all versions)](https://img.shields.io/badge/Zenodo-10.5281%2Fzenodo.18248285-blue)](https://doi.org/10.5281/zenodo.18248285)
[![Data: MIMIC-IV v3.1](https://img.shields.io/badge/data-MIMIC--IV%20v3.1-orange.svg)](https://doi.org/10.13026/kpb9-mt58)

Version 2.0.0 supersedes the January 2026 release in every analytic respect. See [CHANGELOG.md](CHANGELOG.md) for the full record of what changed and why.

## What the software does

| Stage | Script | Content |
|---|---|---|
| Cohort | `analysis/R/01_build_cohort.R` | Adult index ICU stays with a fully observed 24 hour window; subject level development set (anchor year groups 2008 to 2019) and a temporally external deployment stream (2020 to 2022) |
| Features | `analysis/R/02_extract_features.R` | First 24 hour vital signs (8 concepts) and laboratory tests (13 concepts) extracted with DuckDB directly from the PhysioNet csv.gz files; item identifiers verified against the dictionaries at run time |
| Arms | `analysis/R/03_train_models.R` | Three frozen models with distinct operational footprints: ridge logistic regression on demographics and vitals (cost 0.25), gradient boosted trees adding a core laboratory panel (cost 0.60), random forest adding extended laboratory tests (cost 1.00); Platt calibration and operating thresholds at 80 percent sensitivity set on a validation split never used for training |
| Governance simulation | `analysis/R/04_run_bandit_simulation.R` | Policies: fixed confidence action elimination with Hoeffding and empirical Bernstein bounds, a stratified variant, Thompson sampling, UCB1, uniform random, static deployment, ensemble averaging and heuristic escalation; delayed feedback queue; 100 replicates; paired bootstrap comparisons; sensitivity grids over reward weights, confidence level and delay |
| Reporting | `analysis/R/05_make_tables_figures.R` | Every table and figure in the manuscript, generated only from `outputs/results` |

The composite reward for arm a on patient t is

```
r_raw = (1 - (p - y)^2) - lambda_c * cost_a - lambda_s * 1[y = 1 and p < threshold_a]
r     = (r_raw + lambda_c + lambda_s) / (1 + lambda_c + lambda_s)        in [0, 1]
```

where p is the calibrated mortality probability, y the in hospital mortality label, cost_a the normalised operational cost of the arm and threshold_a its operating threshold. The governance weights lambda_c and lambda_s are policy parameters set in `config/params.yml`, not tuned quantities.

Fixed confidence action elimination keeps an active set of arms, cycles through it, updates each arm's estimate only when delayed feedback arrives, and removes an arm when its upper confidence bound falls below the highest lower confidence bound of another active arm. The confidence radii are valid simultaneously for every sample size and every arm, so the probability that the best arm is ever eliminated is at most delta. The formulas are documented in `analysis/R/lib/policies.R` and in `docs/analysis-specification.md`.

## Reproduce

Requirements: R 4.5 or later and credentialed access to MIMIC-IV v3.1 (PhysioNet). Nothing in this repository contains patient data.

```bash
git clone https://github.com/julian-borges-md/multiarm-bandit-clinical-ai-governance.git
cd multiarm-bandit-clinical-ai-governance
Rscript -e 'install.packages(c("data.table","yaml","jsonlite","digest","glmnet","xgboost","ranger","pROC","ggplot2","scales","testthat","DBI","duckdb"))'
cp config/paths_template.yml config/paths.yml      # set mimic_iv_dir to your local MIMIC-IV v3.1 root
Rscript tests/run_tests.R                           # unit tests (no data needed)
Rscript analysis/R/00_run_all.R                     # full run, about 10 minutes on a laptop
```

Without data access, the identical pipeline runs on a synthetic cohort with the same schema (values are not clinically meaningful and must not be reported as results):

```bash
DATA_MODE=synthetic Rscript analysis/R/00_run_all.R
```

Every run writes `outputs/results/run_manifest.json` with the commit, R and package versions, the SHA256 hash of `config/params.yml`, step timings and, in MIMIC mode, the PhysioNet published SHA256 of every file read (`VERIFY_MIMIC_SHA=1` recomputes them). Patient level derived files under `outputs/data`, `outputs/models` and `outputs/cache_raw` are ignored by git; aggregate tables, results and figures are committed.

## Repository layout

```
analysis/R/            pipeline scripts and lib/ (reward, policies, metrics, synthetic generator)
config/                params.yml (all analytic parameters), paths_template.yml
tests/                 testthat suite: reward bounds, confidence radius coverage, elimination behaviour, delayed feedback integrity, metric identities
docs/                  analysis specification and governance design rationale
docker/                container recipe
outputs/               tables/, results/, figures/ committed; data/, models/, cache_raw/, logs/ ignored
.github/workflows/     CI: unit tests plus a synthetic end to end run
```

## Data access and ethics

MIMIC-IV v3.1 (Johnson et al., PhysioNet, https://doi.org/10.13026/kpb9-mt58) is available to credentialed users under the PhysioNet Credentialed Health Data Use Agreement. The study is a secondary analysis of de identified data and did not require ethics review. Users of this software are responsible for their own credentialing, training and data use obligations.

## Citation

Cite the archived software through its concept DOI, which always resolves to the latest version: https://doi.org/10.5281/zenodo.18248285. Version specific DOIs are listed on Zenodo. Citation metadata is in `CITATION.cff`. Please also cite MIMIC-IV (Johnson et al. 2023, Scientific Data) and PhysioNet (Goldberger et al. 2000).

## License

Apache License 2.0 (see `LICENSE`).

## Author

Julian Borges, MD, MS  
Department of Computer Science, Boston University Metropolitan College  
jyborges@bu.edu
