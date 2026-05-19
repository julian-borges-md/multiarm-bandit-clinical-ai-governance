# analysis/R/00_setup.R
# Setup: packages, config, output directories, logging, save helpers
# MIMIC path is provided via environment variable: MIMIC_IV_DIR
# Output root can be overridden via environment variable: OUTPUT_DIR
#
# Key guarantees:
# - msg() supports sprintf style calls via ...
# - cfg$log_file is always length 1 character (or "")
# - paths object is defined (paths$dat, paths$tab, paths$fig, paths$log, paths$out, paths$cache)
# - ensure_unzipped() uses cfg$out_cache_dir by default
# - save_data/save_table/save_fig write deterministically into outputs/ subfolders

cfg <- list()

# -----------------------------
# Behavior toggles
# -----------------------------
cfg$auto_install_packages <- FALSE
cfg$enable_cache_raw <- FALSE

# -----------------------------
# Packages
# -----------------------------
pkgs_core  <- c("data.table", "ggplot2", "scales")
pkgs_tools <- c("R.utils", "yaml", "stringi", "stringr", "fastDummies", "pROC", "xgboost", "nnet")
pkgs_all   <- unique(c(pkgs_core, pkgs_tools))

pkg_check_install <- function(pkgs, auto_install = FALSE) {
  missing <- pkgs[!pkgs %in% rownames(installed.packages())]
  if (length(missing) > 0) {
    if (isTRUE(auto_install)) {
      install.packages(missing, dependencies = TRUE)
    } else {
      stop(
        paste0(
          "Missing R packages: ", paste(missing, collapse = ", "), "\n",
          "Install them or restore the renv environment.\n",
          "If you insist, set cfg$auto_install_packages <- TRUE."
        )
      )
    }
  }
  invisible(TRUE)
}

pkg_check_install(pkgs_all, auto_install = cfg$auto_install_packages)

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
  library(scales)
  library(R.utils)
})

# -----------------------------
# Logger (robust)
# -----------------------------
sanitize_scalar_chr <- function(x, default = "") {
  if (is.null(x)) return(as.character(default))
  if (length(x) == 0) return(as.character(default))
  if (length(x) > 1) x <- x[1]
  if (is.na(x)) return(as.character(default))
  as.character(x)
}

cfg$mimic_dir <- sanitize_scalar_chr(Sys.getenv("MIMIC_IV_DIR", unset = ""), default = "")

cfg_validate_mimic <- function(mustWork = TRUE) {
  md <- sanitize_scalar_chr(cfg$mimic_dir, default = "")
  if (!nzchar(md)) {
    if (isTRUE(mustWork)) {
      stop(
        paste0(
          "MIMIC_IV_DIR is not set.\n",
          "Set it before running cohort and feature scripts.\n",
          "Example (R): Sys.setenv(MIMIC_IV_DIR='/path/to/mimic-iv-3.1')\n"
        )
      )
    }
    return(FALSE)
  }
  
  md_norm <- normalizePath(md, mustWork = isTRUE(mustWork))
  
  hosp_dir <- normalizePath(file.path(md_norm, "hosp"), mustWork = isTRUE(mustWork))
  icu_dir  <- normalizePath(file.path(md_norm, "icu"),  mustWork = isTRUE(mustWork))
  
  if (isTRUE(mustWork)) {
    if (!dir.exists(hosp_dir)) stop(paste0("Missing directory: ", hosp_dir))
    if (!dir.exists(icu_dir))  stop(paste0("Missing directory: ", icu_dir))
  }
  
  cfg$mimic_dir <- md_norm
  cfg$mimic_hosp_dir <- hosp_dir
  cfg$mimic_icu_dir  <- icu_dir
  
  TRUE
}

invisible(cfg_validate_mimic(mustWork = FALSE))


# -----------------------------
# Global config
# -----------------------------
cfg$seed   <- 20250108
cfg$eval_n <- 3000

# Governance parameters (used by simulation scripts)
cfg$lambda_cost   <- as.numeric(Sys.getenv("LAMBDA_COST", unset = "0.15"))
cfg$lambda_safety <- as.numeric(Sys.getenv("LAMBDA_SAFETY", unset = "0.35"))
cfg$delayed_min_h <- as.numeric(Sys.getenv("DELAYED_MIN_H", unset = "0"))
cfg$delayed_max_h <- as.numeric(Sys.getenv("DELAYED_MAX_H", unset = "24"))

if (!is.finite(cfg$lambda_cost))   cfg$lambda_cost <- 0.15
if (!is.finite(cfg$lambda_safety)) cfg$lambda_safety <- 0.35
if (!is.finite(cfg$delayed_min_h)) cfg$delayed_min_h <- 0
if (!is.finite(cfg$delayed_max_h)) cfg$delayed_max_h <- 24
if (cfg$delayed_min_h < 0) cfg$delayed_min_h <- 0
if (cfg$delayed_max_h < cfg$delayed_min_h) cfg$delayed_max_h <- cfg$delayed_min_h

set.seed(cfg$seed)

# -----------------------------
# Output directories
# -----------------------------
default_out    <- normalizePath(file.path(getwd(), "outputs"), mustWork = FALSE)
cfg$output_dir <- normalizePath(Sys.getenv("OUTPUT_DIR", unset = default_out), mustWork = FALSE)

cfg$out_data_dir   <- file.path(cfg$output_dir, "data")
cfg$out_tables_dir <- file.path(cfg$output_dir, "tables")
cfg$out_fig_dir    <- file.path(cfg$output_dir, "figures")
cfg$out_cache_dir  <- file.path(cfg$output_dir, "cache_raw")
cfg$out_logs_dir   <- file.path(cfg$output_dir, "logs")

dir.create(cfg$output_dir,     recursive = TRUE, showWarnings = FALSE)
dir.create(cfg$out_data_dir,   recursive = TRUE, showWarnings = FALSE)
dir.create(cfg$out_tables_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(cfg$out_fig_dir,    recursive = TRUE, showWarnings = FALSE)
dir.create(cfg$out_cache_dir,  recursive = TRUE, showWarnings = FALSE)
dir.create(cfg$out_logs_dir,   recursive = TRUE, showWarnings = FALSE)

# Backward compatible paths object
paths <- list(
  out   = cfg$output_dir,
  dat   = cfg$out_data_dir,
  tab   = cfg$out_tables_dir,
  fig   = cfg$out_fig_dir,
  log   = cfg$out_logs_dir,
  cache = cfg$out_cache_dir
)

# -----------------------------
# MIMIC config helpers
# -----------------------------
cfg$mimic_dir <- sanitize_scalar_chr(Sys.getenv("MIMIC_IV_DIR", unset = ""))

cfg_validate_mimic <- function(mustWork = TRUE) {
  md <- sanitize_scalar_chr(cfg$mimic_dir, default = "")
  
  if (!nzchar(md)) {
    if (isTRUE(mustWork)) {
      stop(
        paste0(
          "MIMIC_IV_DIR is not set.\n",
          "Set it before running cohort and feature scripts.\n",
          "Example (R): Sys.setenv(MIMIC_IV_DIR='/path/to/mimic-iv-3.1')\n"
        )
      )
    }
    return(FALSE)
  }
  
  md_norm <- normalizePath(md, mustWork = TRUE)
  hosp_dir <- file.path(md_norm, "hosp")
  icu_dir  <- file.path(md_norm, "icu")
  
  if (!dir.exists(hosp_dir) || !dir.exists(icu_dir)) {
    if (isTRUE(mustWork)) {
      stop(
        paste0(
          "Invalid MIMIC-IV root: ", md_norm, "\n",
          "Expected subfolders: hosp/ and icu/\n",
          "Found hosp exists: ", dir.exists(hosp_dir), ", icu exists: ", dir.exists(icu_dir)
        )
      )
    }
    return(FALSE)
  }
  
  # guarantee scalar strings
  cfg$mimic_dir <- md_norm
  cfg$mimic_hosp_dir <- hosp_dir
  cfg$mimic_icu_dir  <- icu_dir
  
  TRUE
}


invisible(cfg_validate_mimic(mustWork = FALSE))

cfg_mimic_paths <- function() {
  if (!cfg_validate_mimic(mustWork = FALSE)) return(NULL)
  list(
    chartevents = file.path(cfg$mimic_icu_dir,  "chartevents.csv.gz"),
    labevents   = file.path(cfg$mimic_hosp_dir, "labevents.csv.gz")
  )
}

# -----------------------------
# Cache helpers
# -----------------------------
ensure_unzipped <- function(path_gz, cache_dir = NULL) {
  stopifnot(length(path_gz) == 1, nzchar(path_gz))
  if (!file.exists(path_gz)) stop(paste0("Missing file: ", path_gz))

  if (is.null(cache_dir)) cache_dir <- cfg$out_cache_dir
  cache_dir <- sanitize_scalar_chr(cache_dir)
  if (!nzchar(cache_dir)) stop("Invalid cache_dir in ensure_unzipped().")

  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)

  if (!grepl("\\.gz$", path_gz, ignore.case = TRUE)) {
    return(normalizePath(path_gz))
  }

  out_name <- sub("\\.gz$", "", basename(path_gz), ignore.case = TRUE)
  out_path <- file.path(cache_dir, out_name)

  if (!file.exists(out_path)) {
    msg("Decompressing to cache: %s", out_path)
    R.utils::gunzip(path_gz, destname = out_path, overwrite = TRUE, remove = FALSE)
  }

  normalizePath(out_path)
}

# -----------------------------
# Save helpers
# -----------------------------
save_data <- function(dt, name) {
  stopifnot(is.data.table(dt) || is.data.frame(dt))
  name <- sanitize_scalar_chr(name)
  if (!nzchar(name)) stop("save_data() requires a non-empty name.")

  csv_path <- file.path(cfg$out_data_dir, paste0(name, ".csv"))
  gz_path  <- paste0(csv_path, ".gz")

  data.table::fwrite(dt, csv_path)
  R.utils::gzip(csv_path, destname = gz_path, overwrite = TRUE, remove = TRUE)

  msg("Saved data: %s", gz_path)
  invisible(gz_path)
}

.as_md <- function(dt) {
  dt <- as.data.frame(dt, stringsAsFactors = FALSE)
  for (j in seq_len(ncol(dt))) dt[[j]] <- as.character(dt[[j]])
  header <- paste0("| ", paste(names(dt), collapse = " | "), " |")
  sep    <- paste0("| ", paste(rep("---", ncol(dt)), collapse = " | "), " |")
  rows   <- apply(dt, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |"))
  c(header, sep, rows)
}

save_table <- function(dt, table_number, name) {
  stopifnot(is.data.table(dt) || is.data.frame(dt))
  name <- sanitize_scalar_chr(name)
  if (!nzchar(name)) stop("save_table() requires a non-empty name.")

  csv_path <- file.path(cfg$out_tables_dir, sprintf("Table%02d_%s.csv", table_number, name))
  md_path  <- file.path(cfg$out_tables_dir, sprintf("Table%02d_%s.md", table_number, name))

  data.table::fwrite(dt, csv_path)
  writeLines(c(sprintf("# Table %d: %s", table_number, name), "", .as_md(dt)), md_path)

  msg("Saved table: %s", csv_path)
  msg("Saved table preview: %s", md_path)
  invisible(list(csv = csv_path, md = md_path))
}

save_fig <- function(p, fig_number, name, width = 8, height = 5, dpi = 300) {
  name <- sanitize_scalar_chr(name)
  if (!nzchar(name)) stop("save_fig() requires a non-empty name.")

  png_path <- file.path(cfg$out_fig_dir, sprintf("Figure%02d_%s.png", fig_number, name))
  pdf_path <- file.path(cfg$out_fig_dir, sprintf("Figure%02d_%s.pdf", fig_number, name))

  ggplot2::ggsave(filename = png_path, plot = p, width = width, height = height, dpi = dpi)
  ggplot2::ggsave(filename = pdf_path, plot = p, width = width, height = height)

  msg("Saved figure: %s", png_path)
  msg("Saved figure: %s", pdf_path)
  invisible(list(png = png_path, pdf = pdf_path))
}

# -----------------------------
# Optional cache warmup
# -----------------------------
if (isTRUE(cfg$enable_cache_raw) && cfg_validate_mimic(mustWork = FALSE)) {
  mm <- cfg_mimic_paths()
  if (!is.null(mm)) {
    chartevents_csv <- ensure_unzipped(mm$chartevents, cache_dir = cfg$out_cache_dir)
    labevents_csv   <- ensure_unzipped(mm$labevents,   cache_dir = cfg$out_cache_dir)
    msg("chartevents cached: %s", chartevents_csv)
    msg("labevents cached: %s", labevents_csv)
  }
}

# -----------------------------
# Startup messages
# -----------------------------
msg("00_setup.R loaded")
msg("Outputs root: %s", cfg$output_dir)
msg("Logs root: %s", cfg$out_logs_dir)
msg("Cache root: %s", cfg$out_cache_dir)

if (cfg_validate_mimic(mustWork = FALSE)) {
  msg("MIMIC IV root: %s", cfg$mimic_dir)
  msg("MIMIC hosp: %s", cfg$mimic_hosp_dir)
  msg("MIMIC icu:  %s", cfg$mimic_icu_dir)
} else {
  msg("MIMIC_IV_DIR is not set. Cohort and feature scripts will fail until it is set.")
  msg("Example (R): Sys.setenv(MIMIC_IV_DIR='/path/to/mimic-iv-3.1')")
}

msg("Seed: %s", cfg$seed)
msg("Evaluation cohort size: %s", cfg$eval_n)
msg(
  "Governance params: lambda_cost=%s, lambda_safety=%s, delay_h=[%s,%s]",
  cfg$lambda_cost, cfg$lambda_safety, cfg$delayed_min_h, cfg$delayed_max_h
)
