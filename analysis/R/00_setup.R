# analysis/R/00_setup.R
# Shared setup for the pipeline: configuration, paths, logging, save helpers.
# Every script sources this file first. Nothing here touches patient data.
#
# Configuration sources (in order of precedence):
#   1. Environment variables MIMIC_IV_DIR and OUTPUT_DIR
#   2. config/paths.yml (local, ignored by git)
#   3. Defaults: outputs under <repo>/outputs
# Analytic parameters come only from config/params.yml.

suppressPackageStartupMessages({
  library(data.table)
  library(yaml)
  library(jsonlite)
  library(digest)
})

# -----------------------------------------------------------------------------
# Repository root detection
# -----------------------------------------------------------------------------
find_repo_root <- function(start = getwd()) {
  d <- normalizePath(start, mustWork = TRUE)
  for (i in 1:10) {
    if (file.exists(file.path(d, "config", "params.yml")) &&
        dir.exists(file.path(d, "analysis", "R"))) return(d)
    parent <- dirname(d)
    if (identical(parent, d)) break
    d <- parent
  }
  stop("Could not locate the repository root (config/params.yml and analysis/R expected).")
}

REPO_ROOT <- find_repo_root()

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
# PARAMS_FILE (relative to the repository root) selects an alternative parameter file, used for
# the development window sensitivity analysis; the default is config/params.yml
PARAMS_FILE <- Sys.getenv("PARAMS_FILE", unset = "config/params.yml")
params <- yaml::read_yaml(file.path(REPO_ROOT, PARAMS_FILE))

local_paths <- list()
paths_file <- file.path(REPO_ROOT, "config", "paths.yml")
if (file.exists(paths_file)) local_paths <- yaml::read_yaml(paths_file)
if (is.null(local_paths)) local_paths <- list()

first_nonempty <- function(...) {
  for (v in list(...)) {
    if (!is.null(v) && length(v) == 1 && !is.na(v) && nzchar(as.character(v))) return(as.character(v))
  }
  NULL
}

cfg <- list()
cfg$repo_root   <- REPO_ROOT
cfg$data_mode   <- Sys.getenv("DATA_MODE", unset = params$data$mode)
cfg$mimic_dir   <- first_nonempty(Sys.getenv("MIMIC_IV_DIR", unset = ""), local_paths$mimic_iv_dir)
cfg$output_dir  <- first_nonempty(Sys.getenv("OUTPUT_DIR", unset = ""), local_paths$output_dir,
                                  file.path(REPO_ROOT, "outputs"))
cfg$output_dir  <- normalizePath(cfg$output_dir, mustWork = FALSE)
cfg$duckdb_threads <- as.integer(first_nonempty(local_paths$duckdb_threads, "4"))
cfg$duckdb_memory  <- first_nonempty(local_paths$duckdb_memory_limit, "8GB")

cfg$dirs <- list(
  data    = file.path(cfg$output_dir, "data"),
  models  = file.path(cfg$output_dir, "models"),
  tables  = file.path(cfg$output_dir, "tables"),
  figures = file.path(cfg$output_dir, "figures"),
  results = file.path(cfg$output_dir, "results"),
  logs    = file.path(cfg$output_dir, "logs"),
  cache   = file.path(cfg$output_dir, "cache_raw")
)
for (d in cfg$dirs) dir.create(d, recursive = TRUE, showWarnings = FALSE)

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------
cfg$log_file <- file.path(cfg$dirs$logs, "run_all.log")

msg <- function(fmt, ...) {
  txt <- if (length(list(...)) > 0) sprintf(fmt, ...) else fmt
  line <- sprintf("[%s] [INFO] %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), txt)
  cat(line, "\n")
  cat(line, "\n", file = cfg$log_file, append = TRUE)
  invisible(line)
}

stop_log <- function(fmt, ...) {
  txt <- if (length(list(...)) > 0) sprintf(fmt, ...) else fmt
  line <- sprintf("[%s] [ERROR] %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), txt)
  cat(line, "\n", file = cfg$log_file, append = TRUE)
  stop(txt, call. = FALSE)
}

# -----------------------------------------------------------------------------
# MIMIC-IV path validation (only in mimic mode)
# -----------------------------------------------------------------------------
cfg_validate_mimic <- function(mustWork = TRUE) {
  if (is.null(cfg$mimic_dir) || !nzchar(cfg$mimic_dir)) {
    if (mustWork) stop_log("MIMIC_IV_DIR is not set. Copy config/paths_template.yml to config/paths.yml or export MIMIC_IV_DIR.")
    return(FALSE)
  }
  root <- normalizePath(cfg$mimic_dir, mustWork = FALSE)
  hosp <- file.path(root, "hosp"); icu <- file.path(root, "icu")
  if (!dir.exists(hosp) || !dir.exists(icu)) {
    if (mustWork) stop_log("Invalid MIMIC-IV root %s (expected hosp/ and icu/).", root)
    return(FALSE)
  }
  cfg$mimic_dir <<- root
  cfg$mimic_hosp <<- hosp
  cfg$mimic_icu  <<- icu
  TRUE
}

mimic_file <- function(module, name) {
  f <- file.path(cfg$mimic_dir, module, name)
  if (!file.exists(f)) stop_log("Missing MIMIC-IV file: %s", f)
  f
}

# -----------------------------------------------------------------------------
# Save helpers (deterministic locations)
# -----------------------------------------------------------------------------
save_data <- function(dt, name) {
  path <- file.path(cfg$dirs$data, paste0(name, ".csv.gz"))
  data.table::fwrite(dt, path, compress = "gzip")
  msg("Saved data: %s (%d rows)", path, nrow(dt))
  invisible(path)
}

load_data <- function(name) {
  path <- file.path(cfg$dirs$data, paste0(name, ".csv.gz"))
  if (!file.exists(path)) stop_log("Missing upstream artifact: %s", path)
  data.table::fread(path, showProgress = FALSE)
}

.as_md <- function(dt) {
  df <- as.data.frame(dt, stringsAsFactors = FALSE)
  for (j in seq_len(ncol(df))) {
    v <- df[[j]]
    if (is.numeric(v)) v <- ifelse(is.na(v), "", sub("\\.$", "", formatC(v, digits = 4, format = "fg", flag = "#")))
    df[[j]] <- as.character(v)
  }
  header <- paste0("| ", paste(names(df), collapse = " | "), " |")
  sep    <- paste0("| ", paste(rep("---", ncol(df)), collapse = " | "), " |")
  rows   <- apply(df, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |"))
  c(header, sep, rows)
}

save_table <- function(dt, number, name) {
  csv <- file.path(cfg$dirs$tables, sprintf("Table%02d_%s.csv", number, name))
  md  <- file.path(cfg$dirs$tables, sprintf("Table%02d_%s.md", number, name))
  data.table::fwrite(dt, csv)
  writeLines(c(sprintf("# Table %d: %s", number, name), "", .as_md(dt)), md)
  msg("Saved table: %s", csv)
  invisible(csv)
}

save_result <- function(dt, name) {
  path <- file.path(cfg$dirs$results, paste0(name, ".csv"))
  data.table::fwrite(dt, path)
  msg("Saved result: %s (%d rows)", path, nrow(dt))
  invisible(path)
}

load_result <- function(name) {
  path <- file.path(cfg$dirs$results, paste0(name, ".csv"))
  if (!file.exists(path)) stop_log("Missing result: %s", path)
  data.table::fread(path, showProgress = FALSE)
}

save_fig <- function(p, number, name, width = 8, height = 5, dpi = 300) {
  png <- file.path(cfg$dirs$figures, sprintf("Figure%02d_%s.png", number, name))
  pdf <- file.path(cfg$dirs$figures, sprintf("Figure%02d_%s.pdf", number, name))
  ggplot2::ggsave(png, plot = p, width = width, height = height, dpi = dpi, bg = "white")
  ggplot2::ggsave(pdf, plot = p, width = width, height = height, bg = "white")
  msg("Saved figure: %s", png)
  invisible(png)
}

# -----------------------------------------------------------------------------
# Manifest helpers
# -----------------------------------------------------------------------------
git_sha <- function() {
  out <- tryCatch(system2("git", c("-C", shQuote(REPO_ROOT), "rev-parse", "HEAD"), stdout = TRUE, stderr = FALSE),
                  error = function(e) NA_character_)
  if (length(out) == 0) NA_character_ else out[1]
}

params_hash <- function() digest::digest(params, algo = "sha256")
params_file <- function() PARAMS_FILE

write_json_result <- function(x, name) {
  path <- file.path(cfg$dirs$results, paste0(name, ".json"))
  jsonlite::write_json(x, path, auto_unbox = TRUE, pretty = TRUE, digits = NA)
  msg("Saved json: %s", path)
  invisible(path)
}

# -----------------------------------------------------------------------------
# Arm metadata (ordered as in params)
# -----------------------------------------------------------------------------
arm_table <- function() {
  data.table::rbindlist(lapply(params$arms, function(a) {
    data.table::data.table(arm = a$key, label = a$label, learner = a$learner,
                           feature_set = a$feature_set, cost = as.numeric(a$cost))
  }))
}

msg("00_setup.R loaded (mode=%s, repo=%s)", cfg$data_mode, REPO_ROOT)
msg("Outputs: %s", cfg$output_dir)
if (identical(cfg$data_mode, "mimic")) {
  if (cfg_validate_mimic(mustWork = FALSE)) msg("MIMIC-IV root: %s", cfg$mimic_dir) else
    msg("MIMIC-IV root not configured; cohort and feature steps will stop until it is")
}
