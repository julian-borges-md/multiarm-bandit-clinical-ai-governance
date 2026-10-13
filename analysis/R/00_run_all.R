# analysis/R/00_run_all.R
# End to end orchestrator. Run from the repository root:
#   Rscript analysis/R/00_run_all.R                # mode from config/params.yml (mimic)
#   DATA_MODE=synthetic Rscript analysis/R/00_run_all.R
# Writes a run manifest (results/run_manifest.json and tables/Table00_RunManifest.csv)
# with the commit, R and package versions, parameter hash, step timings and,
# in mimic mode, the SHA256 of every MIMIC-IV file read (VERIFY_MIMIC_SHA=1 to recompute).

source(file.path("analysis", "R", "00_setup.R"))
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

t_run <- Sys.time()
msg("Starting 00_run_all.R (mode=%s)", cfg$data_mode)
steps <- c("01_build_cohort.R", "02_extract_features.R", "03_train_models.R", "04_run_bandit_simulation.R", "05_make_tables_figures.R")
manifest <- data.table(step = seq_along(steps), script = steps, started = as.character(NA), ended = as.character(NA),
                       elapsed_sec = NA_real_, status = "pending", error = "")

# each step runs in its own environment (child of the global environment, so cfg and params are
# visible) so that step scripts cannot overwrite the orchestrator's variables
for (step_i in seq_along(steps)) {
  s <- steps[step_i]
  manifest[step_i, started := format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")]
  t0 <- Sys.time()
  msg("Running: %s", s)
  step_env <- new.env(parent = globalenv())
  res <- tryCatch({ source(file.path(cfg$repo_root, "analysis", "R", s), local = step_env); "success" },
                  error = function(e) { msg("ERROR in %s: %s", s, conditionMessage(e)); paste("error:", conditionMessage(e)) })
  manifest[step_i, `:=`(ended = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
                        elapsed_sec = as.numeric(difftime(Sys.time(), t0, units = "secs")),
                        status = if (res == "success") "success" else "error",
                        error = if (res == "success") "" else res)]
  if (res != "success") break
}
save_table(manifest, 0, "RunManifest")

# environment capture
pkgs <- c("data.table", "R.utils", "duckdb", "glmnet", "xgboost", "ranger", "pROC", "ggplot2", "yaml", "jsonlite", "digest")
pkg_versions <- sapply(pkgs, function(p) tryCatch(as.character(packageVersion(p)), error = function(e) NA_character_))
mimic_sha <- NULL
if (identical(cfg$data_mode, "mimic") && cfg_validate_mimic(mustWork = FALSE)) {
  used <- c("hosp/patients.csv.gz", "hosp/admissions.csv.gz", "icu/icustays.csv.gz", "icu/d_items.csv.gz",
            "hosp/d_labitems.csv.gz", "icu/chartevents.csv.gz", "hosp/labevents.csv.gz")
  sums_file <- file.path(cfg$mimic_dir, "SHA256SUMS.txt")
  published <- if (file.exists(sums_file)) fread(sums_file, header = FALSE, col.names = c("sha256", "file")) else NULL
  mimic_sha <- lapply(used, function(f) {
    pub <- if (!is.null(published)) published[file == f, sha256] else NA_character_
    computed <- if (identical(Sys.getenv("VERIFY_MIMIC_SHA"), "1")) digest::digest(file.path(cfg$mimic_dir, f), algo = "sha256", file = TRUE) else NA_character_
    list(file = f, published_sha256 = if (length(pub)) pub[1] else NA_character_, computed_sha256 = computed,
         verified = if (!is.na(computed) && length(pub)) identical(computed, pub[1]) else NA)
  })
}
run_manifest <- list(
  project = params$project$name, version = params$project$version, mode = cfg$data_mode,
  git_commit = git_sha(), params_file = params_file(), params_sha256 = params_hash(), r_version = R.version.string, platform = R.version$platform,
  hostname = Sys.info()[["nodename"]], run_started_utc = format(t_run, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  elapsed_min = as.numeric(difftime(Sys.time(), t_run, units = "mins")),
  packages = as.list(pkg_versions), steps = manifest, mimic_files = mimic_sha,
  mimic_version = params$data$mimic_version, mimic_doi = params$data$mimic_doi
)
write_json_result(run_manifest, "run_manifest")
if (any(manifest$status != "success")) stop("Pipeline stopped with an error; see outputs/logs/run_all.log")
msg("00_run_all.R finished in %.1f min", as.numeric(difftime(Sys.time(), t_run, units = "mins")))
