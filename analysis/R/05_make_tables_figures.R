# analysis/R/05_make_tables_figures.R
# Final assembly of manuscript ready tables and figures from upstream artifacts
# Designed to run both standalone and via 00_run_all.R

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
  library(scales)
})

# -----------------------------
# 0) Load setup once
# -----------------------------
if (!exists("cfg", inherits = TRUE) || !is.list(cfg) || is.null(cfg$output_dir)) {
  source("analysis/R/00_setup.R")
}
msg("05_make_tables_figures.R starting")
set.seed(cfg$seed)

# -----------------------------
# 1) Validate required upstream artifacts
# -----------------------------
req <- list(
  model_perf = file.path(cfg$out_tables_dir, "Table04_model_performance.csv"),
  bandit_arm = file.path(cfg$out_tables_dir, "Table06_bandit_summary_by_arm.csv"),
  bandit_tr  = file.path(cfg$out_data_dir,   "bandit_trace.csv.gz"),
  preds      = file.path(cfg$out_data_dir,   "preds_eval.csv.gz"),
  features   = file.path(cfg$out_data_dir,   "features_eval.csv.gz")
)

missing <- names(req)[!vapply(req, file.exists, logical(1))]
if (length(missing) > 0) {
  stop(sprintf(
    "Missing required artifacts: %s\nRun steps 01 to 04 first.",
    paste(missing, collapse = ", ")
  ))
}

# Decompress gz inputs for stable fread
bandit_trace_csv <- ensure_unzipped(req$bandit_tr, cache_dir = cfg$out_cache_dir)
preds_csv        <- ensure_unzipped(req$preds,    cache_dir = cfg$out_cache_dir)
features_csv     <- ensure_unzipped(req$features, cache_dir = cfg$out_cache_dir)

# Load tables and data
tab_model <- fread(req$model_perf, showProgress = FALSE)
tab_arm   <- fread(req$bandit_arm, showProgress = FALSE)
trace     <- fread(bandit_trace_csv, showProgress = FALSE)
preds     <- fread(preds_csv, showProgress = FALSE)
feat      <- fread(features_csv, showProgress = FALSE)

# -----------------------------
# 2) Create manuscript summary tables
# -----------------------------
# Table07: model performance + selection frequency by arm (if available)
# We infer selection from trace$chosen_arm.
if (!("chosen_arm" %in% names(trace))) {
  stop("bandit_trace is missing 'chosen_arm'. Step 04 output does not match expectations.")
}

sel <- trace[, .(n_selected = .N), by = chosen_arm]
sel[, pct_selected := n_selected / sum(n_selected)]

# Try to join with model performance if columns are compatible
# We standardize names to a common key.
# Expect model table has a model column like "glm","rf","xgb" or similar.
tab_model2 <- copy(tab_model)

# Heuristic: find model column
model_col <- intersect(c("model", "arm", "name"), names(tab_model2))
if (length(model_col) == 0) {
  # If unknown, just save selection table separately
  save_table(sel, 7, "bandit_selection_frequency")
} else {
  model_col <- model_col[1]
  setnames(tab_model2, model_col, "model_key")
  
  # Map chosen_arm (pred_glm etc) to model keys (glm etc)
  sel[, model_key := gsub("^pred_", "", chosen_arm)]
  tab7 <- merge(tab_model2, sel[, .(model_key, n_selected, pct_selected)], by = "model_key", all.x = TRUE)
  save_table(tab7, 7, "model_performance_with_bandit_selection")
}

# Table08: overall bandit outcome summary (loss and utility)
tab8 <- trace[, .(
  n = .N,
  mean_loss = mean(loss, na.rm = TRUE),
  sd_loss = sd(loss, na.rm = TRUE),
  mean_utility = mean(utility, na.rm = TRUE),
  sd_utility = sd(utility, na.rm = TRUE)
)]
save_table(tab8, 8, "bandit_outcomes_overall")

# -----------------------------
# 3) Create manuscript figures
# -----------------------------
# Figure05: selection frequency by arm
p_sel <- ggplot(sel, aes(x = reorder(chosen_arm, pct_selected), y = pct_selected)) +
  geom_col() +
  coord_flip() +
  scale_y_continuous(labels = percent_format(accuracy = 1)) +
  labs(
    title = "Bandit model selection frequency",
    x = NULL,
    y = "Percent selected"
  )
save_fig(p_sel, 5, "BanditSelectionFrequency")

# Figure06: cumulative average loss
trace[, cum_avg_loss := cumsum(loss) / seq_len(.N)]
p_cum <- ggplot(trace, aes(x = t, y = cum_avg_loss)) +
  geom_line() +
  labs(
    title = "Cumulative average loss over time",
    x = "t",
    y = "Cumulative average log loss"
  )
save_fig(p_cum, 6, "BanditCumulativeAverageLoss")

msg("05_make_tables_figures.R done")
