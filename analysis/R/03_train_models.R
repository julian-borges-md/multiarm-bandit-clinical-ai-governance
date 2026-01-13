# analysis/R/03_train_models.R
# Train baseline predictive models on evaluation features
# Outputs:
#   outputs/models/model_glm.rds
#   outputs/models/model_ranger.rds
#   outputs/models/model_xgb.rds
#   outputs/tables/Table04_model_performance.csv
#   outputs/data/preds_eval.csv.gz

suppressPackageStartupMessages({
  library(data.table)
  library(ranger)
  library(xgboost)
})

# -----------------------------
# 0) Load setup once
# -----------------------------
if (!exists("cfg", inherits = TRUE) || !is.list(cfg) || is.null(cfg$output_dir)) {
  source("analysis/R/00_setup.R")
}

msg("03_train_models.R starting")
set.seed(cfg$seed)

# -----------------------------
# 1) Inputs and outputs
# -----------------------------
features_gz <- file.path(cfg$out_data_dir, "features_eval.csv.gz")
if (!file.exists(features_gz)) {
  stop("Missing outputs/data/features_eval.csv.gz. Run 02_extract_features.R first.")
}

models_dir <- file.path(cfg$output_dir, "models")
dir.create(models_dir, recursive = TRUE, showWarnings = FALSE)

# If gz, decompress to cache for fread stability
features_csv <- ensure_unzipped(features_gz, cache_dir = cfg$out_cache_dir)

# IMPORTANT: always use file= for paths (paths may contain spaces)
dt <- data.table::fread(file = features_csv, showProgress = FALSE)

# -----------------------------
# 2) Minimal cleaning / prep
# -----------------------------
# Outcome must exist
if (!("mort_hosp" %in% names(dt))) stop("features_eval is missing mort_hosp outcome.")
dt[, mort_hosp := as.integer(mort_hosp)]

# Ensure id columns exist
id_cols <- intersect(c("subject_id", "hadm_id", "stay_id"), names(dt))

# Convert sex to factor if present
if ("sex" %in% names(dt)) {
  dt[, sex := as.factor(sex)]
}

# Define feature columns
drop_cols <- unique(c(id_cols, "mort_hosp"))
x_cols <- setdiff(names(dt), drop_cols)

# Basic numeric imputation for NA (median), and one hot encode factor columns
# Split feature columns into numeric and factor
is_fac <- vapply(dt[, ..x_cols], is.factor, logical(1))
fac_cols <- x_cols[is_fac]
num_cols <- x_cols[!is_fac]

# Median impute numeric
for (cc in num_cols) {
  v <- dt[[cc]]
  if (all(is.na(v))) {
    dt[[cc]] <- 0
  } else {
    med <- suppressWarnings(stats::median(v, na.rm = TRUE))
    v[is.na(v)] <- med
    dt[[cc]] <- v
  }
}

# One hot encode factors (including sex)
if (length(fac_cols) > 0) {
  # model.matrix will create dummy vars; keep stable ordering
  mm <- stats::model.matrix(~ . - 1, data = dt[, ..fac_cols])
  mm <- as.matrix(mm)
  
  # Remove original factor cols from dt, append dummies
  dt[, (fac_cols) := NULL]
  dt <- cbind(dt, as.data.table(mm))
  x_cols <- setdiff(names(dt), drop_cols)
}

# Final design matrix and label vector
X <- as.matrix(dt[, ..x_cols])
y <- dt[["mort_hosp"]]

# -----------------------------
# 3) Train models
# -----------------------------

# 3.1 GLM logistic regression
glm_df <- data.frame(mort_hosp = y, X)
m_glm <- stats::glm(mort_hosp ~ ., data = glm_df, family = stats::binomial())

# 3.2 Random forest (ranger)
rf_df <- data.frame(mort_hosp = as.factor(y), X)
m_rf <- ranger::ranger(
  mort_hosp ~ .,
  data = rf_df,
  probability = TRUE,
  num.trees = 500,
  seed = cfg$seed
)

# 3.3 XGBoost (future proof: put objective and eval_metric inside params)
dtrain <- xgboost::xgb.DMatrix(data = X, label = y)

xgb_params <- list(
  booster = "gbtree",
  objective = "binary:logistic",
  eval_metric = "logloss"
)

m_xgb <- xgboost::xgb.train(
  params  = xgb_params,
  data    = dtrain,
  nrounds = 300,
  verbose = 0
)

# -----------------------------
# 4) Predictions and metrics
# -----------------------------
pred_glm <- as.numeric(stats::predict(m_glm, newdata = glm_df, type = "response"))
pred_rf  <- as.numeric(predict(m_rf, data = rf_df)$predictions[, "1"])
pred_xgb <- as.numeric(predict(m_xgb, newdata = dtrain))

# AUC helper (no extra packages)
auc_fast <- function(y_true, y_score) {
  o <- order(y_score)
  y <- y_true[o]
  n1 <- sum(y == 1)
  n0 <- sum(y == 0)
  if (n1 == 0 || n0 == 0) return(NA_real_)
  r <- rank(y_score[o], ties.method = "average")
  (sum(r[y == 1]) - n1 * (n1 + 1) / 2) / (n1 * n0)
}

perf <- data.table(
  model = c("glm_logistic", "ranger_rf", "xgboost"),
  auc = c(
    auc_fast(y, pred_glm),
    auc_fast(y, pred_rf),
    auc_fast(y, pred_xgb)
  )
)

# Save table
save_table(perf, 4, "model_performance")

# Save predictions
preds <- data.table(
  stay_id = if ("stay_id" %in% names(dt)) dt[["stay_id"]] else NA_integer_,
  mort_hosp = y,
  pred_glm = pred_glm,
  pred_rf = pred_rf,
  pred_xgb = pred_xgb
)
save_data(preds, "preds_eval")

# -----------------------------
# 5) Save models
# -----------------------------
saveRDS(m_glm, file.path(models_dir, "model_glm.rds"))
saveRDS(m_rf,  file.path(models_dir, "model_ranger.rds"))
saveRDS(m_xgb, file.path(models_dir, "model_xgb.rds"))

msg("Saved models to: %s", models_dir)
msg("03_train_models.R done")
