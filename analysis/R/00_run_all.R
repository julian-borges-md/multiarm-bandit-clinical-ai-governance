# analysis/R/00_run_all.R
# Orchestrates the full pipeline in a deterministic order and writes a run manifest.
# Produces:
#   outputs/tables/Table00_RunManifest.csv
#   outputs/figures/Figure00_OutputFileSizes.png
#   outputs/logs/run_all.log
#
# Key guarantees:
# - Requires analysis/R/00_setup.R and uses its msg(), cfg, paths, save_* helpers
# - Sets cfg$log_file to outputs/logs/run_all.log and also sinks console output there
# - Hard fails at the end if any step failed (CI friendly)

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
  library(scales)
})

# Always run from repo root (assumes user setwd() to repo root before sourcing)
repo_root <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)

# -----------------------------
# 0) Load shared setup
# -----------------------------
setup_fp <- file.path(repo_root, "analysis", "R", "00_setup.R")
if (!file.exists(setup_fp)) {
  stop("Missing analysis/R/00_setup.R. Set working directory to repo root and re-run.")
}
source(setup_fp)

# -----------------------------
# 1) Configure run-level logging
# -----------------------------
# Ensure logs dir exists (00_setup creates it, but keep robust)
if (!dir.exists(cfg$out_logs_dir)) dir.create(cfg$out_logs_dir, recursive = TRUE, showWarnings = FALSE)

cfg$log_file <- file.path(cfg$out_logs_dir, "run_all.log")

# Also capture all console output to the same file (in addition to msg() logging)
sink(cfg$log_file, split = TRUE)
on.exit({
  try(sink(), silent = TRUE)
}, add = TRUE)

msg("Starting 00_run_all.R")
msg("Repo root: %s", repo_root)
msg("Outputs root: %s", cfg$output_dir)
msg("MIMIC configured: %s", ifelse(cfg_validate_mimic(mustWork = FALSE), "TRUE", "FALSE"))

set.seed(cfg$seed)

# -----------------------------
# 2) Script registry
# -----------------------------
scripts <- data.table(
  step = c(1, 2, 3, 4, 5),
  script = c(
    "01_build_cohort.R",
    "02_extract_features.R",
    "03_train_models.R",
    "04_run_bandit_simulation.R",
    "05_make_tables_figures.R"
  )
)
scripts[, path := file.path(repo_root, "analysis", "R", script)]
scripts[, exists := file.exists(path)]

if (any(!scripts$exists)) {
  missing <- scripts[exists == FALSE, .(script, path)]
  msg("Missing required scripts:\n%s", paste(capture.output(print(missing)), collapse = "\n"), level = "ERROR")
  stop("Cannot continue. Missing scripts in analysis/R.")
}

# -----------------------------
# 3) Runner
# -----------------------------
run_one <- function(script_path) {
  start <- Sys.time()
  ok <- TRUE
  err <- ""
  
  msg("Running: %s", basename(script_path))
  
  tryCatch(
    {
      # isolate each script in its own environment, inheriting from globalenv
      source(script_path, local = new.env(parent = globalenv()))
    },
    error = function(e) {
      ok <<- FALSE
      err <<- conditionMessage(e)
    }
  )
  
  end <- Sys.time()
  
  list(
    ok = ok,
    err = err,
    started = start,
    ended = end,
    elapsed_sec = as.numeric(difftime(end, start, units = "secs"))
  )
}

manifest <- data.table()

for (i in 1:nrow(scripts)) {
  s <- scripts[i]
  res <- run_one(s$path)
  
  manifest <- rbind(
    manifest,
    data.table(
      step = s$step,
      script = s$script,
      started = res$started,
      ended = res$ended,
      elapsed_sec = res$elapsed_sec,
      status = ifelse(res$ok, "success", "failure"),
      error = ifelse(nzchar(res$err), res$err, "")
    )
  )
  
  if (!res$ok) {
    msg("Pipeline failed at step %d: %s", s$step, s$script, level = "ERROR")
    msg("Error: %s", res$err, level = "ERROR")
    break
  }
}

# -----------------------------
# 4) Save manifest
# -----------------------------
save_table(manifest, 0, "RunManifest")

# -----------------------------
# 5) Output inventory and size plot
# -----------------------------
list_files <- function(dir_path) {
  if (length(dir_path) != 1 || !nzchar(dir_path) || !dir.exists(dir_path)) return(data.table())
  files <- list.files(dir_path, recursive = TRUE, full.names = TRUE)
  if (length(files) == 0) return(data.table())
  info <- file.info(files)
  dt <- data.table(
    file = files,
    size_bytes = info$size,
    modified = info$mtime
  )
  dt[, relpath := sub(paste0("^", gsub("\\\\", "/", repo_root), "/"), "", gsub("\\\\", "/", file))]
  dt[, folder := sub("/.*$", "", relpath)]
  dt
}

inv <- rbindlist(list(
  list_files(paths$tab),
  list_files(paths$fig),
  list_files(paths$dat),
  list_files(paths$log)
), fill = TRUE)

if (nrow(inv) == 0) {
  inv <- data.table(
    relpath = character(),
    size_bytes = numeric(),
    folder = character(),
    modified = as.POSIXct(character())
  )
}

inv[, size_mb := size_bytes / (1024^2)]
inv_sum <- inv[, .(
  n_files = .N,
  total_mb = sum(size_mb, na.rm = TRUE)
), by = folder][order(-total_mb)]

save_table(inv_sum, 0, "OutputInventorySummary")
save_table(inv[order(-size_mb)][1:min(200, .N)], 0, "OutputInventoryTop200")

p0 <- ggplot(inv_sum, aes(x = reorder(folder, total_mb), y = total_mb)) +
  geom_col() +
  coord_flip() +
  scale_y_continuous(labels = comma) +
  labs(
    title = "Output size by folder",
    x = NULL,
    y = "Total size (MB)"
  )

save_fig(p0, 0, "OutputFileSizes", width = 10, height = 6, dpi = 320)

# -----------------------------
# 6) Final messages and hard fail if needed
# -----------------------------
msg("00_run_all.R finished")
msg("Run manifest: %s", file.path(paths$tab, "Table00_RunManifest.csv"))
msg("Output inventory summary: %s", file.path(paths$tab, "Table00_OutputInventorySummary.csv"))
msg("Output sizes figure: %s", file.path(paths$fig, "Figure00_OutputFileSizes.png"))
msg("Log file: %s", cfg$log_file)

if (any(manifest$status == "failure")) {
  stop("Pipeline failed. See outputs/logs/run_all.log and the RunManifest table.")
}
