# Reproduce the results

## 1. Requirements

| Item | Requirement |
|---|---|
| R | 4.5.0 or later (the archived run used R 4.5.2, see `outputs/results/run_manifest.json`) |
| Packages | data.table, R.utils (gz reading), yaml, jsonlite, digest, glmnet, xgboost, ranger, pROC, ggplot2, scales, testthat, DBI, duckdb (versions in the run manifest) |
| Data | MIMIC-IV v3.1 csv.gz files from PhysioNet (credentialed access): hosp/patients, hosp/admissions, hosp/d_labitems, hosp/labevents, icu/icustays, icu/d_items, icu/chartevents |
| Hardware | 8 GB RAM is enough; the archived run used 12 threads and about 10 minutes end to end |

## 2. Configure

```bash
cp config/paths_template.yml config/paths.yml
# edit mimic_iv_dir; optionally output_dir, duckdb_threads, duckdb_memory_limit
```
`config/paths.yml` is ignored by git. All analytic parameters are in `config/params.yml`; do not edit them to reproduce the archived run.

## 3. Run

```bash
Rscript tests/run_tests.R          # should end with no failures
Rscript analysis/R/00_run_all.R    # cohort, features, arms, simulation, tables, figures
```
Individual steps can be re run in order with `Rscript -e 'source("analysis/R/00_setup.R"); source("analysis/R/0X_....R")'`.

## 4. Verify

| Check | Where |
|---|---|
| Step status and timings | `outputs/tables/Table00_RunManifest.csv` |
| Environment, commit, parameter hash, MIMIC file hashes | `outputs/results/run_manifest.json` (`VERIFY_MIMIC_SHA=1` recomputes the SHA256 of each MIMIC file and compares with PhysioNet's SHA256SUMS.txt) |
| Numbers in the manuscript | `outputs/tables/Table01` to `Table14`; every reported quantity is read from these files |
| Delayed feedback integrity | `leak_violations` column of `outputs/results/replicate_metrics.csv` must be 0 for every row (the simulator asserts it) |

Seeds are fixed in `config/params.yml`; a rerun on the same MIMIC-IV release with the same package versions reproduces the tables exactly. Small numerical differences can arise across xgboost or ranger versions; the run manifest records the versions used.

## 5. Without data access

`DATA_MODE=synthetic Rscript analysis/R/00_run_all.R` runs every step on a synthetic cohort with the same schema. The outputs demonstrate the pipeline mechanics only.
