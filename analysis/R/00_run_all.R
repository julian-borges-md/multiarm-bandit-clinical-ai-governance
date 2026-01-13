# 00_run_all.R
# Orchestrates the full end to end governance simulation pipeline

source("analysis/R/00_setup.R")

source("analysis/R/01_build_cohort.R")
source("analysis/R/02_extract_features.R")
source("analysis/R/03_train_models.R")
source("analysis/R/04_run_bandit_simulation.R")
source("analysis/R/05_make_tables_figures.R")
