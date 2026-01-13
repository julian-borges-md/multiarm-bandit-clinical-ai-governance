# analysis/R/04_run_bandit_simulation.R
# Run contextual bandit governance simulation using model predictions
# Inputs:
#   outputs/data/preds_eval.csv.gz
#   outputs/data/features_eval.csv.gz
# Outputs:
#   outputs/tables/Table05_bandit_summary.csv
#   outputs/data/bandit_trace.csv.gz
#   outputs/figures/Figure04_BanditRegret.png  (and pdf)

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
})

# -----------------------------
# 0) Load setup once
# -----------------------------
if (!exists("cfg", inherits = TRUE) || !is.list(cfg) || is.null(cfg$output_dir)) {
  source("analysis/R/00_setup.R")
}
msg("04_run_bandit_simulation.R starting")
set.seed(cfg$seed)

# -----------------------------
# 1) Validate required upstream artifacts
# -----------------------------
preds_gz    <- file.path(cfg$out_data_dir, "preds_eval.csv.gz")
features_gz <- file.path(cfg$out_data_dir, "features_eval.csv.gz")

if (!file.exists(preds_gz)) {
  stop("Missing outputs/data/preds_eval.csv.gz. Run 03_train_models.R first.")
}
if (!file.exists(features_gz)) {
  stop("Missing outputs/data/features_eval.csv.gz. Run 02_extract_features.R first.")
}

preds_csv    <- ensure_unzipped(preds_gz, cache_dir = cfg$out_cache_dir)
features_csv <- ensure_unzipped(features_gz, cache_dir = cfg$out_cache_dir)

preds <- data.table::fread(file = preds_csv, showProgress = FALSE)
feat  <- data.table::fread(file = features_csv, showProgress = FALSE)

# Ensure required columns exist
need_pred_cols <- c("mort_hosp", "pred_glm", "pred_rf", "pred_xgb")
miss_pred_cols <- setdiff(need_pred_cols, names(preds))
if (length(miss_pred_cols) > 0) {
  stop(sprintf("preds_eval is missing columns: %s", paste(miss_pred_cols, collapse = ", ")))
}

# Merge minimal context needed
key <- intersect(c("stay_id"), names(preds))
if (length(key) == 1 && "stay_id" %in% names(feat)) {
  dt <- merge(preds, feat[, .(stay_id, age, sex)], by = "stay_id", all.x = TRUE)
} else {
  dt <- copy(preds)
}

dt[, mort_hosp := as.integer(mort_hosp)]

# -----------------------------
# 2) Define arms and reward (example)
# -----------------------------
# Arms are the three model predictions. Reward here is negative log loss plus optional cost and safety penalty.
# You can later replace with your formal utility from the Methods section.
arms <- c("pred_glm", "pred_rf", "pred_xgb")

clip01 <- function(x) pmin(pmax(x, 1e-6), 1 - 1e-6)

logloss <- function(y, p) {
  p <- clip01(p)
  -(y * log(p) + (1 - y) * log(1 - p))
}

# Example per arm cost and safety weights (placeholder)
# You can wire these to cfg$lambda_cost and cfg$lambda_safety as you finalize Methods.
arm_cost <- c(pred_glm = 0.10, pred_rf = 0.15, pred_xgb = 0.20)

# -----------------------------
# 3) Simple bandit policy (epsilon greedy placeholder)
# -----------------------------
# This is a clean baseline implementation to unblock the pipeline.
# Replace with your contextual policy (LinUCB, Thompson, etc) when ready.

epsilon <- 0.10
n <- nrow(dt)

# Online estimates
q_hat <- setNames(rep(0, length(arms)), arms)
n_arm <- setNames(rep(0, length(arms)), arms)

trace <- data.table(
  t = integer(n),
  chosen_arm = character(n),
  y = integer(n),
  p = numeric(n),
  loss = numeric(n),
  utility = numeric(n)
)

for (i in seq_len(n)) {
  # choose arm
  if (runif(1) < epsilon) {
    a <- sample(arms, 1)
  } else {
    a <- names(which.min(q_hat))
  }
  
  y <- dt$mort_hosp[i]
  p <- dt[[a]][i]
  
  loss_i <- logloss(y, p)
  util_i <- -(loss_i + cfg$lambda_cost * arm_cost[[a]])
  
  # update
  n_arm[[a]] <- n_arm[[a]] + 1
  q_hat[[a]] <- q_hat[[a]] + (loss_i - q_hat[[a]]) / n_arm[[a]]
  
  trace[i, `:=`(
    t = i,
    chosen_arm = a,
    y = y,
    p = p,
    loss = loss_i,
    utility = util_i
  )]
}

# -----------------------------
# 4) Summaries and artifacts
# -----------------------------
summary_tbl <- trace[, .(
  n = .N,
  mean_loss = mean(loss, na.rm = TRUE),
  mean_utility = mean(utility, na.rm = TRUE)
)]

arm_tbl <- trace[, .(
  n = .N,
  mean_loss = mean(loss, na.rm = TRUE),
  mean_utility = mean(utility, na.rm = TRUE)
), by = chosen_arm][order(chosen_arm)]

save_table(summary_tbl, 5, "bandit_summary_overall")
save_table(arm_tbl, 6, "bandit_summary_by_arm")
save_data(trace, "bandit_trace")

p1 <- ggplot(trace, aes(x = t, y = loss)) +
  geom_line() +
  labs(title = "Online loss trajectory", x = "t", y = "Log loss")

save_fig(p1, 4, "BanditLossTrajectory")

msg("04_run_bandit_simulation.R done")
