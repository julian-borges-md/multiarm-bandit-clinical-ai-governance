# analysis/R/03_train_models.R
# Train, calibrate and freeze the three decision arms on the development set,
# then score the deployment stream. No stream observation is used for training,
# tuning, calibration or threshold selection (asserted below).
#
# Outputs:
#   models/arm_<key>.rds                   frozen models (not committed)
#   data/stream_predictions.csv.gz         calibrated probabilities per arm for the stream (not committed)
#   results/arms_meta.csv                  arm definitions, thresholds, calibration parameters, static best flag
#   results/model_performance.csv          validation and stream performance per arm and for the ensemble
#   tables/Table04_model_performance.csv

if (!exists("cfg", inherits = TRUE)) source(file.path("analysis", "R", "00_setup.R"))
suppressPackageStartupMessages({ library(data.table); library(glmnet); library(xgboost); library(ranger); library(pROC) })
source(file.path(cfg$repo_root, "analysis", "R", "lib", "metrics.R"))
source(file.path(cfg$repo_root, "analysis", "R", "lib", "policies.R"))
source(file.path(cfg$repo_root, "analysis", "R", "lib", "synthetic.R"))   # concept constants

msg("03_train_models.R starting")
set.seed(params$reproducibility$seed_models)

feats <- load_data("features")
feats[, sex_M := as.numeric(sex == "M")]
feats[, age_ge_65 := as.integer(age >= 65)]
# extended panel availability: all three extended tests observed in the window (the context used for
# stratification); ext_lab_any records whether at least one was observed
n_ext_present <- rowSums(!is.na(feats[, paste0("lab_", EXT_LABS, "_mean"), with = FALSE]))
feats[, ext_lab_available := as.integer(n_ext_present == length(EXT_LABS))]
feats[, ext_lab_any := as.integer(n_ext_present > 0)]
for (l in LAB_CONCEPTS) data.table::set(feats, j = paste0("miss_", l), value = as.numeric(is.na(feats[[paste0("lab_", l, "_mean")]])))

train  <- feats[split == "train"]
val    <- feats[split == "val"]
stream <- feats[split == "stream"]
stopifnot(nrow(train) > 0, nrow(val) > 0, nrow(stream) > 0)
stopifnot(length(intersect(c(train$subject_id, val$subject_id), stream$subject_id)) == 0)
stopifnot(length(intersect(c(train$stay_id, val$stay_id), stream$stay_id)) == 0)

# validation halves: early stopping (es) and calibration, thresholds and reporting (cal)
val_subj <- unique(val$subject_id)
es_subj <- sample(val_subj, size = floor(length(val_subj) / 2))
val_es  <- val[subject_id %in% es_subj]
val_cal <- val[!subject_id %in% es_subj]

# -----------------------------------------------------------------------------
# 1) Feature sets and preprocessing (training medians only)
# -----------------------------------------------------------------------------
vital_cols <- paste0("vital_", rep(VITAL_CONCEPTS, each = 4), "_", STATS)
core_cols  <- paste0("lab_", rep(CORE_LABS, each = 4), "_", STATS)
ext_cols   <- paste0("lab_", rep(EXT_LABS, each = 4), "_", STATS)
feature_sets <- list(
  vitals    = c("age", "sex_M", vital_cols),
  core_labs = c("age", "sex_M", vital_cols, core_cols, paste0("miss_", CORE_LABS)),
  all       = c("age", "sex_M", vital_cols, core_cols, ext_cols, paste0("miss_", LAB_CONCEPTS))
)
all_num <- unique(unlist(feature_sets))
medians <- vapply(all_num, function(cc) { v <- train[[cc]]; m <- stats::median(v, na.rm = TRUE); if (is.na(m)) 0 else m }, numeric(1))

design <- function(dt, cols) {
  X <- as.matrix(dt[, cols, with = FALSE])
  for (j in seq_along(cols)) { v <- X[, j]; v[is.na(v)] <- medians[[cols[j]]]; X[, j] <- v }
  X
}

# -----------------------------------------------------------------------------
# 2) Learners
# -----------------------------------------------------------------------------
fit_arm <- function(learner, Xtr, ytr, Xes, yes) {
  if (learner == "glmnet_ridge") {
    cv <- glmnet::cv.glmnet(Xtr, ytr, family = "binomial", alpha = 0, nfolds = 10, standardize = TRUE)
    list(model = cv, predict = function(m, X) as.numeric(stats::predict(m, newx = X, s = "lambda.min", type = "response")),
         detail = sprintf("ridge lambda.min=%.4g", cv$lambda.min))
  } else if (learner == "xgboost") {
    dtr <- xgboost::xgb.DMatrix(Xtr, label = ytr); des <- xgboost::xgb.DMatrix(Xes, label = yes)
    prm <- list(objective = "binary:logistic", eval_metric = "logloss", eta = 0.05, max_depth = 4,
                subsample = 0.8, colsample_bytree = 0.8, min_child_weight = 5, nthread = 4)
    m0 <- xgboost::xgb.train(params = prm, data = dtr, nrounds = 2000, evals = list(es = des),
                             early_stopping_rounds = 50, verbose = 0)
    best <- suppressWarnings(as.integer(xgboost::xgb.attributes(m0)$best_iteration))
    if (length(best) == 0 || is.na(best) || best < 1) best <- 2000L
    # refit with the selected number of rounds so that the frozen model is unambiguous
    m <- xgboost::xgb.train(params = prm, data = dtr, nrounds = best, verbose = 0)
    list(model = m, predict = function(m, X) as.numeric(stats::predict(m, xgboost::xgb.DMatrix(X))),
         detail = sprintf("xgboost nrounds=%d (early stopping on validation half)", best))
  } else if (learner == "ranger") {
    # tuned by the same protocol as the other arms: the early stopping half of the validation set
    # selects mtry and the minimum node size by log loss; the frozen model is the selected fit
    df <- data.frame(y = factor(ytr, levels = c(0, 1)), Xtr)
    p_feat <- ncol(Xtr)
    grid <- expand.grid(mtry = unique(pmax(1L, c(floor(sqrt(p_feat)), floor(p_feat / 3), floor(p_feat / 2)))),
                        min.node.size = c(5L, 10L, 20L))
    logloss <- function(y, p) { p <- pmin(pmax(p, 1e-6), 1 - 1e-6); -mean(y * log(p) + (1 - y) * log(1 - p)) }
    fits <- lapply(seq_len(nrow(grid)), function(i) {
      m <- ranger::ranger(y ~ ., data = df, probability = TRUE, num.trees = 500, mtry = grid$mtry[i],
                          min.node.size = grid$min.node.size[i], seed = params$reproducibility$seed_models, num.threads = 4)
      list(model = m, loss = logloss(yes, as.numeric(stats::predict(m, data = data.frame(Xes))$predictions[, "1"])))
    })
    losses <- vapply(fits, `[[`, numeric(1), "loss")
    best_i <- which.min(losses)
    m <- fits[[best_i]]$model
    list(model = m, predict = function(m, X) as.numeric(stats::predict(m, data = data.frame(X))$predictions[, "1"]),
         detail = sprintf("ranger num.trees=500 mtry=%d min.node.size=%d (selected on validation half from %d settings)",
                          grid$mtry[best_i], grid$min.node.size[best_i], nrow(grid)))
  } else stop("Unknown learner: ", learner)
}

arms <- arm_table()
K <- nrow(arms)
preds_cal <- matrix(NA_real_, nrow(val_cal), K); preds_str <- matrix(NA_real_, nrow(stream), K)
colnames(preds_cal) <- colnames(preds_str) <- arms$arm
platt <- data.table(arm = arms$arm, platt_intercept = NA_real_, platt_slope = NA_real_, detail = NA_character_, n_features = NA_integer_)

for (k in seq_len(K)) {
  a <- arms[k]
  cols <- feature_sets[[a$feature_set]]
  msg("Training arm %s (%s on %d features)", a$arm, a$learner, length(cols))
  fit <- fit_arm(a$learner, design(train, cols), train$mort_hosp, design(val_es, cols), val_es$mort_hosp)
  raw_cal <- fit$predict(fit$model, design(val_cal, cols))
  raw_str <- fit$predict(fit$model, design(stream, cols))
  # Platt scaling on the calibration half of the validation set
  pl <- stats::glm(val_cal$mort_hosp ~ logit(raw_cal), family = stats::binomial())
  cf <- stats::coef(pl)
  preds_cal[, k] <- expit(cf[1] + cf[2] * logit(raw_cal))
  preds_str[, k] <- expit(cf[1] + cf[2] * logit(raw_str))
  platt[k, `:=`(platt_intercept = unname(cf[1]), platt_slope = unname(cf[2]), detail = fit$detail, n_features = length(cols))]
  saveRDS(list(model = fit$model, learner = a$learner, cols = cols, medians = medians[cols], platt = cf),
          file.path(cfg$dirs$models, sprintf("arm_%s.rds", a$arm)))
}

# -----------------------------------------------------------------------------
# 3) Operating thresholds, ensemble threshold, static best arm (validation only)
# -----------------------------------------------------------------------------
target <- params$features$target_sensitivity
thr <- vapply(seq_len(K), function(k) threshold_for_sensitivity(val_cal$mort_hosp, preds_cal[, k], target), numeric(1))
p_ens_cal <- rowMeans(preds_cal)
thr_ens <- threshold_for_sensitivity(val_cal$mort_hosp, p_ens_cal, target)
lc <- params$reward$lambda_cost; ls <- params$reward$lambda_safety
R_cal <- reward_matrix(preds_cal, val_cal$mort_hosp, thr, arms$cost, lc, ls)
val_mean_reward <- colMeans(R_cal)
static_best <- which.max(val_mean_reward)

arms_meta <- cbind(arms, platt[, .(platt_intercept, platt_slope, detail, n_features)])
arms_meta[, threshold := thr]
arms_meta[, val_mean_reward := val_mean_reward]
arms_meta[, static_best := seq_len(K) == static_best]
arms_meta <- rbind(arms_meta,
                   data.table(arm = "ensemble", label = "Equal weight average of the three arms", learner = "average", feature_set = "all",
                              cost = max(arms$cost), platt_intercept = NA, platt_slope = NA, detail = NA, n_features = NA,
                              threshold = thr_ens, val_mean_reward = mean(composite_reward(p_ens_cal, val_cal$mort_hosp, thr_ens, max(arms$cost), lc, ls)),
                              static_best = FALSE))
save_result(arms_meta, "arms_meta")

# -----------------------------------------------------------------------------
# 4) Performance on validation (calibration half) and on the deployment stream
# -----------------------------------------------------------------------------
perf_row <- function(set, model, y, p, thr_x, cost_x) {
  roc <- tryCatch(pROC::roc(y, p, quiet = TRUE), error = function(e) NULL)
  ci <- if (!is.null(roc)) as.numeric(pROC::ci.auc(roc, method = "delong")) else c(NA, NA, NA)
  cl <- classification_at(y, p, thr_x); cal <- calibration_fit(y, p)
  data.table(set = set, model = model, n = length(y), events = sum(y), auroc = ci[2], auroc_lo = ci[1], auroc_hi = ci[3],
             auprc = auprc(y, p), brier = brier(y, p), cal_intercept = cal[["intercept"]], cal_slope = cal[["slope"]],
             threshold = thr_x, sensitivity = cl[["sensitivity"]], specificity = cl[["specificity"]], ppv = cl[["ppv"]],
             fnr = cl[["fnr"]], alert_rate = cl[["alert_rate"]], cost = cost_x)
}
perf <- rbindlist(c(
  lapply(seq_len(K), function(k) perf_row("validation", arms$arm[k], val_cal$mort_hosp, preds_cal[, k], thr[k], arms$cost[k])),
  list(perf_row("validation", "ensemble", val_cal$mort_hosp, p_ens_cal, thr_ens, max(arms$cost))),
  lapply(seq_len(K), function(k) perf_row("stream", arms$arm[k], stream$mort_hosp, preds_str[, k], thr[k], arms$cost[k])),
  list(perf_row("stream", "ensemble", stream$mort_hosp, rowMeans(preds_str), thr_ens, max(arms$cost)))
))
save_result(perf, "model_performance")
save_table(perf, 4, "model_performance")

# per stratum stream performance (context dependence of the arms), with DeLong intervals for the AUROC
auroc_ci <- function(y, p) {
  if (sum(y == 1) < 2 || sum(y == 0) < 2) return(c(NA_real_, NA_real_, NA_real_))
  roc <- tryCatch(pROC::roc(y, p, quiet = TRUE), error = function(e) NULL)
  if (is.null(roc)) return(c(NA_real_, NA_real_, NA_real_))
  as.numeric(pROC::ci.auc(roc, method = "delong"))[c(2, 1, 3)]
}
strat_perf <- rbindlist(lapply(seq_len(K), function(k) {
  stream[, {
    ci <- auroc_ci(mort_hosp, preds_str[.I, k])
    .(model = arms$arm[k], n = .N, events = sum(mort_hosp), auroc = ci[1], auroc_lo = ci[2], auroc_hi = ci[3],
      brier = brier(mort_hosp, preds_str[.I, k]),
      sensitivity = classification_at(mort_hosp, preds_str[.I, k], thr[k])[["sensitivity"]],
      fnr = classification_at(mort_hosp, preds_str[.I, k], thr[k])[["fnr"]],
      mean_reward = mean(composite_reward(preds_str[.I, k], mort_hosp, thr[k], arms$cost[k], lc, ls)))
  }, by = .(ext_lab_available, age_ge_65)]
}))
save_result(strat_perf[order(model, ext_lab_available, age_ge_65)], "stream_performance_by_stratum")

# subgroup sensitivity of each arm on the stream (signed gaps are reported by the simulation)
wilson <- function(x, n, z = 1.959964) {
  if (n == 0) return(c(NA_real_, NA_real_))
  ph <- x / n; d <- 1 + z^2 / n; c0 <- (ph + z^2 / (2 * n)) / d; h <- z * sqrt(ph * (1 - ph) / n + z^2 / (4 * n^2)) / d
  c(c0 - h, c0 + h)
}
stream[, age_group := fifelse(age_ge_65 == 1, "65 and over", "under 65")]
stream[, sex_group := fifelse(sex == "F", "female", "male")]
sub_sens <- rbindlist(lapply(seq_len(K), function(k) rbindlist(lapply(c("age_group", "sex_group", "race_group"), function(g) {
  out <- stream[mort_hosp == 1, {
    x <- sum(preds_str[.I, k] >= thr[k]); ci <- wilson(x, .N)
    .(deaths = .N, detected = x, sensitivity = x / .N, sensitivity_lo = ci[1], sensitivity_hi = ci[2])
  }, by = .(level = get(g))]
  cbind(data.table(model = arms$arm[k], variable = g), out)
}))))
save_result(sub_sens[order(model, variable, level)], "arm_subgroup_sensitivity")

# -----------------------------------------------------------------------------
# 5) Validation (calibration half) and stream predictions for the simulation
# -----------------------------------------------------------------------------
vp <- data.table(stay_id = val_cal$stay_id, mort_hosp = val_cal$mort_hosp, ext_lab_available = val_cal$ext_lab_available,
                 ext_lab_any = val_cal$ext_lab_any)
for (k in seq_len(K)) data.table::set(vp, j = paste0("p_", arms$arm[k]), value = preds_cal[, k])
save_data(vp, "validation_predictions")

sp <- data.table(stay_id = stream$stay_id, subject_id = stream$subject_id, mort_hosp = stream$mort_hosp,
                 age = stream$age, age_ge_65 = stream$age_ge_65, sex = stream$sex, race_group = stream$race_group,
                 ext_lab_available = stream$ext_lab_available, ext_lab_any = stream$ext_lab_any)
for (k in seq_len(K)) data.table::set(sp, j = paste0("p_", arms$arm[k]), value = preds_str[, k])
save_data(sp, "stream_predictions")
msg("Static best arm on validation: %s (mean reward %.4f)", arms$arm[static_best], val_mean_reward[static_best])
msg("03_train_models.R done")
