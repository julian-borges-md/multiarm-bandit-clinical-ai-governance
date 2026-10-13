# analysis/R/04_run_bandit_simulation.R
# Sequential deployment simulation on the deployment stream: governance policies,
# delayed feedback, replicates, paired comparisons and sensitivity analyses.
#
# Inputs:  data/stream_predictions.csv.gz, data/validation_predictions.csv.gz, results/arms_meta.csv,
#          results/stream_meta.json
# Outputs (results/): replicate_metrics.csv, strategy_summary.csv, paired_differences.csv,
#   regret_curves.csv, exploration_deciles.csv, fcae_trace_rep1.csv, elimination_summary.csv,
#   implied_sample_complexity.csv, implied_sample_complexity_scenarios.csv, gap_bootstrap.csv,
#   sensitivity_lambda.csv, sensitivity_delta.csv, sensitivity_delay.csv, sensitivity_utility.csv,
#   sensitivity_cost_vector.csv, sensitivity_false_positive.csv, sensitivity_acquisition_cost.csv,
#   sensitivity_drift.csv, extended_horizon_replicates.csv, extended_horizon_summary.csv, simulation_meta.json

if (!exists("cfg", inherits = TRUE)) source(file.path("analysis", "R", "00_setup.R"))
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(parallel) })
n_cores <- max(1L, min(as.integer(Sys.getenv("SIM_CORES", unset = max(1L, parallel::detectCores() - 2L))), 12L))
par_lapply <- function(X, FUN) {
  if (n_cores > 1 && .Platform$OS.type != "windows") parallel::mclapply(X, FUN, mc.cores = n_cores, mc.set.seed = FALSE) else lapply(X, FUN)
}
source(file.path(cfg$repo_root, "analysis", "R", "lib", "metrics.R"))
source(file.path(cfg$repo_root, "analysis", "R", "lib", "policies.R"))

msg("04_run_bandit_simulation.R starting")
t_start <- Sys.time()

sp <- load_data("stream_predictions")
arms_meta <- load_result("arms_meta")
arms <- arms_meta[arm != "ensemble"]
K <- nrow(arms)
meta <- jsonlite::read_json(file.path(cfg$dirs$results, "stream_meta.json"))
arrival_rate <- as.numeric(meta$arrival_rate_per_hour)

P <- as.matrix(sp[, paste0("p_", arms$arm), with = FALSE]); colnames(P) <- arms$arm
y <- as.integer(sp$mort_hosp)
T <- nrow(P)
thr <- arms$threshold; cost <- arms$cost
thr_ens <- arms_meta[arm == "ensemble", threshold]
static_best <- which(arms$static_best)[1]
ctx <- sp[, .(age_ge_65, sex, ext_lab_available, race_group = if ("race_group" %in% names(sp)) race_group else NA_character_)]
stratum_all <- 1L + ctx$ext_lab_available + 2L * ctx$age_ge_65
prevalence <- mean(y)
msg("Stream: %d decisions, %d events, K=%d, static best arm on validation = %s", T, sum(y), K, arms$arm[static_best])

# absolute per arm sensitivity gaps on the stream (age, sex), for the disparity a patient experiences
# under a mixing policy
arm_abs_gap <- function(g) {
  lv <- sort(unique(g))
  vapply(seq_len(K), function(a) {
    v <- sapply(lv, function(l) { i <- y == 1 & g == l; if (sum(i) == 0) NA_real_ else mean(P[i, a] >= thr[a]) })
    v <- v[!is.na(v)]; if (length(v) < 2) NA_real_ else max(v) - min(v)
  }, numeric(1))
}
arm_gap <- list(age = arm_abs_gap(ctx$age_ge_65), sex = arm_abs_gap(ctx$sex))

policies_all <- c("fcae", "fcae_eb", "fcae_strat", "thompson", "thompson_gauss", "ucb1", "random", "static_best",
                  paste0("static_", arms$arm), "ensemble", "heuristic")
policy_label <- c(fcae = "Fixed confidence action elimination (Hoeffding bound)",
                  fcae_eb = "Fixed confidence action elimination (empirical Bernstein bound)",
                  fcae_strat = "Fixed confidence action elimination (stratified, empirical Bernstein)",
                  thompson = "Thompson sampling (Beta posterior, Bernoulli draw)",
                  thompson_gauss = "Thompson sampling (Gaussian posterior, reward moments)",
                  ucb1 = "UCB1", random = "Uniform random",
                  static_best = sprintf("Static deployment, validation best (arm %s)", arms$arm[static_best]),
                  ensemble = "Ensemble average", heuristic = "Heuristic escalation")
for (k in seq_len(K)) policy_label[paste0("static_", arms$arm[k])] <- sprintf("Static deployment, arm %s", arms$arm[k])

# -----------------------------------------------------------------------------
# Reward configuration helpers
# -----------------------------------------------------------------------------
utility_primary <- if (is.null(params$reward$utility)) "brier" else params$reward$utility
lf_primary <- if (is.null(params$reward$lambda_false_positive)) 0 else params$reward$lambda_false_positive
# acquisition conditional costing: arm C is charged at arm B's cost when the extended panel is absent
cost_matrix_acq <- function(cost_vec, ext_available, n) {
  M <- matrix(rep(cost_vec, each = n), n, K)
  cC <- match("C", arms$arm); cB <- match("B", arms$arm)
  if (!is.na(cC) && !is.na(cB)) M[ext_available == 0, cC] <- cost_vec[cB]
  M
}
vp <- load_data("validation_predictions")
P_val <- as.matrix(vp[, paste0("p_", arms$arm), with = FALSE]); y_val <- as.integer(vp$mort_hosp)
ext_val <- if ("ext_lab_available" %in% names(vp)) vp$ext_lab_available else rep(1L, nrow(vp))
# the static comparator is always chosen on validation data under the scenario's own reward configuration
validation_best_arm <- function(lambda_c, lambda_s, utility = utility_primary, cost_vec = cost, lambda_f = lf_primary, acq = FALSE) {
  cv <- if (acq) cost_matrix_acq(cost_vec, ext_val, nrow(P_val)) else cost_vec
  which.max(colMeans(reward_matrix(P_val, y_val, thr, cv, lambda_c, lambda_s, utility, lambda_f)))
}
stopifnot(validation_best_arm(params$reward$lambda_cost, params$reward$lambda_safety) == static_best)

static_index <- function(policy, sb = static_best) {
  if (policy == "static_best") return(sb)
  if (startsWith(policy, "static_")) return(match(sub("^static_", "", policy), arms$arm))
  NA_integer_
}

# drift: Gaussian noise on the logit of one arm's probabilities from a point of the stream onward
apply_drift <- function(Pr, drift, rep) {
  if (is.null(drift)) return(Pr)
  a <- match(drift$arm, arms$arm)
  t0 <- floor(drift$start_fraction * nrow(Pr)) + 1L
  set.seed(params$reproducibility$seed_simulation + 500000 + rep)
  idx <- t0:nrow(Pr)
  z <- logit(Pr[idx, a]) + stats::rnorm(length(idx), 0, drift$logit_noise_sd)
  Pr[idx, a] <- expit(z)
  Pr
}

# -----------------------------------------------------------------------------
# One replicate for a set of policies under one scenario
# -----------------------------------------------------------------------------
run_replicate <- function(rep, policies, lambda_c, lambda_s, delta, delay_min, delay_max, keep_trace = FALSE, thin = 10,
                          utility = utility_primary, cost_vec = cost, lambda_f = lf_primary, acq = FALSE, drift = NULL) {
  set.seed(params$reproducibility$seed_simulation + rep)
  ord <- sample.int(T)
  Pr <- P[ord, , drop = FALSE]; yr <- y[ord]; ctx_r <- ctx[ord]; st_r <- stratum_all[ord]
  Pr <- apply_drift(Pr, drift, rep)
  cv <- if (acq) cost_matrix_acq(cost_vec, ctx_r$ext_lab_available, T) else cost_vec
  R <- reward_matrix(Pr, yr, thr, cv, lambda_c, lambda_s, utility, lambda_f)
  best_fixed <- which.max(colSums(R))
  extra <- make_extra(Pr, yr, thr, cv, lambda_c, lambda_s, thr_ens, arm_low = 1L, arm_high = K, utility = utility, lambda_f = lambda_f)
  sched <- make_schedule(T, arrival_rate, delay_min, delay_max)
  sb <- validation_best_arm(lambda_c, lambda_s, utility, cost_vec, lambda_f, acq)
  rows <- list(); curves <- list(); deciles <- list(); trace <- list()
  for (pol in policies) {
    res <- run_policy(pol, R, Pr, yr, thr, cv, sched, delta = delta, stratum = st_r, extra = extra,
                      static_arm = static_index(pol, sb), trace_every = thin, check_leakage = TRUE)
    m <- run_metrics(res, R, yr, ctx_r, best_fixed, thin = thin, arm_gap = arm_gap)
    rows[[pol]] <- data.table(rep = rep, policy = pol, best_fixed_arm = arms$arm[best_fixed], static_best_arm = arms$arm[sb],
                              static_best_regret = sum(R[, best_fixed] - R[, sb]), t(m$scalar))
    curves[[pol]] <- cbind(rep = rep, policy = pol, m$curve)
    deciles[[pol]] <- data.table(rep = rep, policy = pol, decile = 1:10, explore_share = m$explore_by_decile)
    if (keep_trace && pol %in% c("fcae", "fcae_eb")) trace[[pol]] <- cbind(rep = rep, policy = pol, res$trace)
  }
  list(metrics = rbindlist(rows), curves = rbindlist(curves), deciles = rbindlist(deciles),
       trace = if (length(trace)) rbindlist(trace) else NULL)
}

# -----------------------------------------------------------------------------
# 1) Primary analysis
# -----------------------------------------------------------------------------
lc <- params$reward$lambda_cost; ls <- params$reward$lambda_safety; delta <- params$governance$delta
dmin <- params$delay$min_hours; dmax <- params$delay$max_hours
Rn <- params$simulation$replicates
thin <- params$simulation$regret_curve_thin
msg("Primary scenario: utility=%s lambda_c=%.2f lambda_s=%.2f lambda_f=%.2f delta=%.2f delay=[%g,%g] h, %d replicates",
    utility_primary, lc, ls, lf_primary, delta, dmin, dmax, Rn)

msg("Using %d cores for replicates", n_cores)
prim <- par_lapply(seq_len(Rn), function(r) run_replicate(r, policies_all, lc, ls, delta, dmin, dmax, keep_trace = (r == 1), thin = thin))
bad <- which(!vapply(prim, is.list, logical(1)))
if (length(bad)) stop_log("Replicates failed: %s", paste(bad, collapse = ","))
metrics <- rbindlist(lapply(prim, `[[`, "metrics"))
curves  <- rbindlist(lapply(prim, `[[`, "curves"))
deciles <- rbindlist(lapply(prim, `[[`, "deciles"))
trace1  <- prim[[1]]$trace
metrics[, policy_label := policy_label[policy]]
save_result(metrics, "replicate_metrics")
if (any(metrics$leak_violations > 0)) stop_log("Delayed feedback leakage detected in the simulator")

# strategy summary (mean, sd, percentiles) per policy and metric
metric_cols <- c("cum_regret_fixed", "cum_regret_oracle", "mean_reward", "mean_cost", "auroc", "brier", "fnr",
                 "alert_rate", "tpr_gap_age", "tpr_gap_sex", "tpr_gap_age_signed", "tpr_gap_sex_signed",
                 "experienced_gap_age", "experienced_gap_sex", "tpr_range_race",
                 "explore_first_decile", "explore_last_decile", paste0("share_arm", seq_len(K)))
summ <- metrics[, {
  out <- list()
  for (mc in metric_cols) { s <- summary_stats(get(mc)); for (nm in names(s)[1:5]) out[[paste0(mc, "_", nm)]] <- s[[nm]] }
  out
}, by = .(policy, policy_label)]
summ <- summ[match(policies_all, policy)]
save_result(summ, "strategy_summary")

# paired differences against static best and against FCAE (per replicate pairing)
B <- params$simulation$bootstrap_resamples
paired_metrics <- c("cum_regret_fixed", "cum_regret_oracle", "mean_reward", "mean_cost", "fnr", "auroc", "brier",
                    "tpr_gap_age", "tpr_gap_sex", "tpr_gap_age_signed", "tpr_gap_sex_signed", "experienced_gap_age", "experienced_gap_sex")
paired <- function(ref) {
  rbindlist(lapply(setdiff(policies_all, ref), function(pol) {
    rbindlist(lapply(paired_metrics, function(mc) {
      a <- metrics[policy == pol][order(rep)][[mc]]; b <- metrics[policy == ref][order(rep)][[mc]]
      d <- a - b; ci <- boot_mean_ci(d, B = B, seed = 7)
      rel <- if (mean(b) != 0) 100 * mean(d) / mean(b) else NA_real_
      data.table(reference = ref, policy = pol, metric = mc, mean_policy = mean(a), mean_reference = mean(b),
                 diff_mean = ci[["mean"]], diff_lo = ci[["lo"]], diff_hi = ci[["hi"]], relative_pct = rel,
                 share_lower = mean(d < 0))
    }))
  }))
}
pd <- rbind(paired("static_best"), paired("fcae"))
save_result(pd, "paired_differences")

# regret curves aggregated across replicates
agg_curves <- curves[, .(cum_regret_fixed_mean = mean(cum_regret_fixed), cum_regret_fixed_lo = quantile(cum_regret_fixed, 0.025),
                         cum_regret_fixed_hi = quantile(cum_regret_fixed, 0.975),
                         cum_regret_oracle_mean = mean(cum_regret_oracle), cum_cost_mean = mean(cum_cost)), by = .(policy, t)]
agg_curves[, policy_label := policy_label[policy]]
save_result(agg_curves, "regret_curves")

agg_dec <- deciles[, .(explore_share_mean = mean(explore_share, na.rm = TRUE), explore_share_lo = quantile(explore_share, 0.025, na.rm = TRUE),
                       explore_share_hi = quantile(explore_share, 0.975, na.rm = TRUE)), by = .(policy, decile)]
save_result(agg_dec, "exploration_deciles")
if (!is.null(trace1)) { trace1[, arm_key := arms$arm[arm]]; save_result(trace1, "fcae_trace_rep1") }

elim <- metrics[policy %in% c("fcae", "fcae_eb"), lapply(.SD, function(x) c(eliminated_share = mean(!is.na(x)), median_step = median(x, na.rm = TRUE),
                                                             p2.5_step = quantile(x, 0.025, na.rm = TRUE), p97.5_step = quantile(x, 0.975, na.rm = TRUE))),
                .SDcols = paste0("elim_step_arm", seq_len(K)), by = policy]
elim <- cbind(elim[, .(policy)], statistic = rep(c("eliminated_share", "median_step", "p2.5_step", "p97.5_step"), length.out = nrow(elim)),
              elim[, paste0("elim_step_arm", seq_len(K)), with = FALSE])
setnames(elim, paste0("elim_step_arm", seq_len(K)), paste0("arm_", arms$arm))
surv <- metrics[policy == "fcae", .N, by = best_fixed_arm]

# -----------------------------------------------------------------------------
# Implied sample complexity from the observed gaps on the stream (full information): exact
# smallest per arm sample, outcomes actually available under round robin, shortfall factors and
# the confidence level at which the available sample would just suffice
# -----------------------------------------------------------------------------
n_avail <- floor(T / K)
implied_complexity_table <- function(R0, scenario, utility = utility_primary) {
  mu <- colMeans(R0); v <- apply(R0, 2, var); best0 <- which.max(mu)
  rbindlist(lapply(seq_len(K), function(a) {
    gap <- mu[best0] - mu[a]
    n_h <- implied_sample_size(gap, v[a], v[best0], K, delta, "hoeffding")
    n_b <- implied_sample_size(gap, v[a], v[best0], K, delta, "bernstein")
    data.table(scenario = scenario, utility = utility, arm = arms$arm[a], best_arm = arms$arm[best0],
               mean_reward = mu[a], sd_reward = sqrt(v[a]), gap_to_best = gap, gap_in_sd_units = gap / sqrt(v[a]),
               n_per_arm_hoeffding = n_h, n_per_arm_bernstein = n_b,
               decisions_round_robin_hoeffding = K * n_h, decisions_round_robin_bernstein = K * n_b,
               stream_length = T, outcomes_available_per_arm = n_avail,
               shortfall_factor_hoeffding = n_h / n_avail, shortfall_factor_bernstein = n_b / n_avail,
               required_delta_hoeffding = required_delta(gap, v[a], v[best0], K, n_avail, "hoeffding"),
               required_delta_bernstein = required_delta(gap, v[a], v[best0], K, n_avail, "bernstein"))
  }))
}
R0 <- reward_matrix(P, y, thr, cost, lc, ls, utility_primary, lf_primary)
isc <- implied_complexity_table(R0, "primary")
save_result(isc, "implied_sample_complexity")
save_result(elim, "elimination_summary")
save_result(surv, "best_fixed_arm_by_replicate")

# patient level bootstrap of the arm means, gaps and implied sample sizes (resampling stays
# within the deployment stream; it quantifies sampling uncertainty of the gap estimates, not
# generalisation to new hospitals)
Bg <- params$simulation$gap_bootstrap_resamples
msg("Gap bootstrap: %d patient level resamples of the stream", Bg)
gb <- gap_bootstrap(R0, K, delta, B = Bg, seed = params$reproducibility$seed_simulation)
best_share <- vapply(seq_len(K), function(a) mean(gb[, "best"] == a), numeric(1))
q <- function(x, p) if (all(is.na(x))) NA_real_ else unname(quantile(x, p, na.rm = TRUE))
gbs <- rbindlist(lapply(seq_len(K), function(a) {
  nh <- gb[, paste0("n_hoeffding_", a)]; nb <- gb[, paste0("n_bernstein_", a)]
  data.table(arm = arms$arm[a], resamples = Bg, share_best = best_share[a],
             mean_reward_point = isc$mean_reward[a], mean_reward_lo = q(gb[, paste0("mu_", a)], 0.025), mean_reward_hi = q(gb[, paste0("mu_", a)], 0.975),
             gap_point = isc$gap_to_best[a], gap_lo = q(gb[, paste0("gap_", a)], 0.025), gap_hi = q(gb[, paste0("gap_", a)], 0.975),
             n_per_arm_hoeffding_point = isc$n_per_arm_hoeffding[a], n_per_arm_hoeffding_lo = q(nh, 0.025), n_per_arm_hoeffding_hi = q(nh, 0.975),
             n_per_arm_bernstein_point = isc$n_per_arm_bernstein[a], n_per_arm_bernstein_lo = q(nb, 0.025), n_per_arm_bernstein_hi = q(nb, 0.975),
             share_resamples_arm_not_best = mean(gb[, "best"] != a),
             share_resamples_n_bernstein_within_stream = mean(!is.na(nb) & K * nb <= T))
}))
save_result(gbs, "gap_bootstrap")

# -----------------------------------------------------------------------------
# 2) Sensitivity analyses (fewer replicates)
# -----------------------------------------------------------------------------
Rs <- params$simulation$sensitivity_replicates
sens_pols <- c("fcae", "fcae_eb", "fcae_strat", "thompson", "thompson_gauss", "ucb1", "random", "static_best", "ensemble", "heuristic")
summarise_scenario <- function(mlist, label_cols) {
  m <- rbindlist(mlist)
  num_cols <- c("cum_regret_fixed", "mean_reward", "mean_cost", "fnr", "auroc", "static_best_regret")
  m[, (num_cols) := lapply(.SD, as.numeric), .SDcols = num_cols]
  elim_cols <- paste0("elim_step_arm", seq_len(K))
  out <- m[, c(list(replicates = .N, best_fixed_arm = names(which.max(table(best_fixed_arm))), static_best_arm = names(which.max(table(static_best_arm))),
               cum_regret_fixed_mean = mean(cum_regret_fixed), cum_regret_fixed_lo = quantile(cum_regret_fixed, 0.025), cum_regret_fixed_hi = quantile(cum_regret_fixed, 0.975),
               static_best_regret_mean = mean(static_best_regret),
               mean_reward_mean = mean(mean_reward), mean_cost_mean = mean(mean_cost), fnr_mean = mean(fnr), auroc_mean = mean(auroc),
               explore_first_decile_mean = mean(explore_first_decile, na.rm = TRUE), explore_last_decile_mean = mean(explore_last_decile, na.rm = TRUE)),
          as.list(setNames(vapply(seq_len(K), function(a) mean(get(paste0("share_arm", a))), numeric(1)), paste0("share_arm_", arms$arm))),
          lapply(.SD, function(x) mean(!is.na(as.numeric(x)))),
          as.list(setNames(vapply(elim_cols, function(cc) median(as.numeric(.SD[[cc]]), na.rm = TRUE), numeric(1)), paste0("median_elim_step_arm_", arms$arm)))),
    by = c(label_cols, "policy"), .SDcols = elim_cols]
  setnames(out, elim_cols, paste0("eliminated_share_arm_", arms$arm))
  out
}
run_cells <- function(cells, label_cols, pols = sens_pols) {
  rbindlist(lapply(cells, function(cell) {
    ml <- par_lapply(seq_len(Rs), function(r) {
      x <- do.call(run_replicate, c(list(r, pols), cell$args))$metrics
      for (nm in names(cell$labels)) x[, (nm) := cell$labels[[nm]]]
      x
    })
    summarise_scenario(ml, label_cols)
  }))
}

msg("Sensitivity: reward weights grid")
cells <- list()
for (lcg in params$simulation$lambda_cost_grid) for (lsg in params$simulation$lambda_safety_grid)
  cells[[length(cells) + 1]] <- list(args = list(lcg, lsg, delta, dmin, dmax), labels = list(lambda_cost = lcg, lambda_safety = lsg))
save_result(run_cells(cells, c("lambda_cost", "lambda_safety")), "sensitivity_lambda")

msg("Sensitivity: confidence level grid")
cells <- lapply(params$simulation$delta_grid, function(dg) list(args = list(lc, ls, dg, dmin, dmax), labels = list(delta = dg)))
save_result(run_cells(cells, "delta", pols = c("fcae", "fcae_eb", "fcae_strat")), "sensitivity_delta")

msg("Sensitivity: delay scenarios")
cells <- lapply(params$simulation$delay_scenarios, function(sc) list(args = list(lc, ls, delta, sc$min_hours, sc$max_hours), labels = list(delay_scenario = sc$label)))
save_result(run_cells(cells, "delay_scenario", pols = c("fcae", "fcae_eb", "fcae_strat", "thompson", "thompson_gauss", "ucb1", "random", "static_best")), "sensitivity_delay")

msg("Sensitivity: utility functional")
util_alts <- setdiff(unlist(params$simulation$utility_alternatives), utility_primary)
cells <- lapply(util_alts, function(ug) list(args = list(lc, ls, delta, dmin, dmax, utility = ug), labels = list(utility = ug)))
mlp <- lapply(seq_len(Rs), function(r) { x <- metrics[rep == r & policy %in% sens_pols]; x[, utility := utility_primary]; x[, policy_label := NULL]; x })
sens_u <- rbind(summarise_scenario(mlp, "utility"), if (length(cells)) run_cells(cells, "utility") else NULL)
save_result(sens_u, "sensitivity_utility")
isc_scen <- list(copy(isc)[, scenario := "utility_brier"],
                 rbindlist(lapply(util_alts, function(ug) implied_complexity_table(reward_matrix(P, y, thr, cost, lc, ls, ug, lf_primary), paste0("utility_", ug), ug))))

msg("Sensitivity: cost vectors")
cost_vectors <- params$simulation$cost_vectors
cells <- lapply(cost_vectors, function(cv) list(args = list(lc, ls, delta, dmin, dmax, cost_vec = as.numeric(unlist(cv$costs))),
                                                labels = list(cost_vector = cv$label, costs = paste(sprintf("%.2f", unlist(cv$costs)), collapse = " / "))))
save_result(run_cells(cells, c("cost_vector", "costs")), "sensitivity_cost_vector")
isc_scen <- c(isc_scen, lapply(cost_vectors, function(cv) implied_complexity_table(reward_matrix(P, y, thr, as.numeric(unlist(cv$costs)), lc, ls, utility_primary, lf_primary), paste0("cost_vector_", cv$label))))

msg("Sensitivity: false positive weight")
lf_grid <- params$simulation$lambda_false_positive_grid
cells <- lapply(lf_grid, function(lfg) list(args = list(lc, ls, delta, dmin, dmax, lambda_f = lfg), labels = list(lambda_false_positive = lfg)))
sens_f <- rbind(copy(sens_u[utility == utility_primary])[, utility := NULL][, lambda_false_positive := lf_primary], run_cells(cells, "lambda_false_positive"), fill = TRUE)
setcolorder(sens_f, "lambda_false_positive")
save_result(sens_f, "sensitivity_false_positive")
isc_scen <- c(isc_scen, lapply(lf_grid, function(lfg) implied_complexity_table(reward_matrix(P, y, thr, cost, lc, ls, utility_primary, lfg), sprintf("false_positive_weight_%.2f", lfg))))
# break even false positive weight at which each arm's mean raw reward equals the best arm's
fp_rate <- vapply(seq_len(K), function(a) mean(y == 0 & P[, a] >= thr[a]), numeric(1))
best0 <- which.max(colMeans(R0))
raw_mu <- colMeans(R0) * (1 + lc + ls + lf_primary) - (lc + ls + lf_primary)
raw_gap <- raw_mu[best0] - raw_mu
break_even <- data.table(arm = arms$arm, false_positive_rate = fp_rate, raw_gap_to_best = raw_gap,
                         false_positive_rate_best = fp_rate[best0],
                         break_even_lambda_f = ifelse(raw_gap > 0 & fp_rate < fp_rate[best0], raw_gap / (fp_rate[best0] - fp_rate), NA_real_))
save_result(break_even, "false_positive_break_even")

if (isTRUE(params$simulation$acquisition_conditional_cost)) {
  msg("Sensitivity: acquisition conditional costing")
  cells <- list(list(args = list(lc, ls, delta, dmin, dmax, acq = TRUE), labels = list(cost_model = "acquisition_conditional")))
  sens_a <- rbind(copy(sens_u[utility == utility_primary])[, utility := NULL][, cost_model := "fixed_per_arm"], run_cells(cells, "cost_model"), fill = TRUE)
  setcolorder(sens_a, "cost_model")
  save_result(sens_a, "sensitivity_acquisition_cost")
  cm <- cost_matrix_acq(cost, ctx$ext_lab_available, T)
  isc_scen <- c(isc_scen, list(implied_complexity_table(reward_matrix(P, y, thr, cm, lc, ls, utility_primary, lf_primary), "cost_acquisition_conditional")))
  save_result(data.table(arm = arms$arm, mean_cost_fixed = cost, mean_cost_acquisition_conditional = colMeans(cm),
                         share_extended_panel_present = mean(ctx$ext_lab_available)), "acquisition_conditional_cost_summary")
}
save_result(rbindlist(isc_scen), "implied_sample_complexity_scenarios")

msg("Sensitivity: drift scenarios (validation chosen arm inferior on the stream)")
drift_pols <- c("fcae", "fcae_eb", "thompson", "thompson_gauss", "ucb1", "random", "static_best", "ensemble", "heuristic")
delay_map <- setNames(params$simulation$delay_scenarios, vapply(params$simulation$delay_scenarios, `[[`, character(1), "label"))
cells <- list()
for (i in seq_along(params$simulation$drift_scenarios)) {
  ds <- params$simulation$drift_scenarios[[i]]
  delays <- unlist(params$simulation$drift_delay_scenarios)
  for (dl in delays) {
    sc <- delay_map[[dl]]
    cells[[length(cells) + 1]] <- list(args = list(lc, ls, delta, sc$min_hours, sc$max_hours, drift = ds),
                                       labels = list(drift_scenario = ds$label, drift_arm = ds$arm, drift_start_fraction = ds$start_fraction,
                                                     logit_noise_sd = ds$logit_noise_sd, delay_scenario = dl))
  }
}
save_result(run_cells(cells, c("drift_scenario", "drift_arm", "drift_start_fraction", "logit_noise_sd", "delay_scenario"), pols = drift_pols), "sensitivity_drift")
# full information description of the drifted arm (replicate 1 noise), for the Methods
drift_desc <- rbindlist(lapply(params$simulation$drift_scenarios, function(ds) {
  Pd <- apply_drift(P, ds, 1L); a <- match(ds$arm, arms$arm)
  i <- (floor(ds$start_fraction * T) + 1L):T
  Rd <- reward_matrix(Pd, y, thr, cost, lc, ls, utility_primary, lf_primary)
  mu <- colMeans(Rd[i, , drop = FALSE])
  v <- apply(Rd[i, , drop = FALSE], 2, var); best_after <- which.max(mu); gap_a <- max(mu) - mu[a]
  n_h <- implied_sample_size(gap_a, v[a], v[best_after], K, delta, "hoeffding")
  n_b <- implied_sample_size(gap_a, v[a], v[best_after], K, delta, "bernstein")
  data.table(drift_scenario = ds$label, arm = ds$arm, logit_noise_sd = ds$logit_noise_sd, decisions_affected = length(i),
             auroc_before = auroc(y[i], P[i, a]), auroc_after = auroc(y[i], Pd[i, a]),
             brier_before = brier(y[i], P[i, a]), brier_after = brier(y[i], Pd[i, a]),
             sensitivity_before = mean(P[i, a][y[i] == 1] >= thr[a]), sensitivity_after = mean(Pd[i, a][y[i] == 1] >= thr[a]),
             best_arm_after = arms$arm[best_after], gap_drifted_arm_after = gap_a, sd_reward_drifted_arm = sqrt(v[a]),
             n_per_arm_hoeffding = n_h, n_per_arm_bernstein = n_b, decisions_round_robin_bernstein = K * n_b,
             outcomes_available_per_arm = floor(length(i) / K))
}))
save_result(drift_desc, "drift_scenario_description")

# -----------------------------------------------------------------------------
# 3) Extended horizon: stream resampled with replacement to test whether elimination
#    occurs at the sample sizes implied by the observed gaps (a planning check, not a result
#    about new patients)
# -----------------------------------------------------------------------------
Te <- params$simulation$extended_horizon$T; Re <- params$simulation$extended_horizon$replicates
msg("Extended horizon: T=%d resampled decisions, %d replicates", Te, Re)
ext_pols <- c("fcae", "fcae_eb", "thompson", "thompson_gauss", "ucb1", "random", "static_best")
run_extended <- function(rep, drift = NULL) {
  set.seed(params$reproducibility$seed_simulation + 100000 + rep)
  idx <- sample.int(T, Te, replace = TRUE)
  Pr <- P[idx, , drop = FALSE]; yr <- y[idx]; ctx_r <- ctx[idx]; st_r <- stratum_all[idx]
  Pr <- apply_drift(Pr, drift, rep)
  R <- reward_matrix(Pr, yr, thr, cost, lc, ls, utility_primary, lf_primary)
  best_fixed <- which.max(colSums(R))
  extra <- make_extra(Pr, yr, thr, cost, lc, ls, thr_ens, arm_low = 1L, arm_high = K, utility = utility_primary, lambda_f = lf_primary)
  sched <- make_schedule(Te, arrival_rate, dmin, dmax)
  rbindlist(lapply(ext_pols, function(pol) {
    res <- run_policy(pol, R, Pr, yr, thr, cost, sched, delta = delta, stratum = st_r, extra = extra,
                      static_arm = static_index(pol, static_best), trace_every = 1e9, check_leakage = TRUE)
    m <- run_metrics(res, R, yr, ctx_r, best_fixed, thin = Te, arm_gap = arm_gap)
    data.table(scenario = if (is.null(drift)) "primary" else drift$label, rep = rep, policy = pol, best_fixed_arm = arms$arm[best_fixed], t(m$scalar))
  }))
}
ext <- rbindlist(par_lapply(seq_len(Re), run_extended))
ext_drift_label <- params$simulation$extended_horizon$drift_scenario
if (!is.null(ext_drift_label)) {
  ds <- params$simulation$drift_scenarios[[match(ext_drift_label, vapply(params$simulation$drift_scenarios, `[[`, character(1), "label"))]]
  msg("Extended horizon under drift scenario %s", ds$label)
  ext <- rbind(ext, rbindlist(par_lapply(seq_len(Re), function(r) run_extended(r, drift = ds))))
}
ext_summary <- ext[, c(list(replicates = .N, best_fixed_arm = names(which.max(table(best_fixed_arm))),
                            cum_regret_fixed_mean = mean(cum_regret_fixed), cum_regret_fixed_lo = quantile(cum_regret_fixed, 0.025),
                            cum_regret_fixed_hi = quantile(cum_regret_fixed, 0.975), mean_reward_mean = mean(mean_reward),
                            mean_cost_mean = mean(mean_cost), fnr_mean = mean(fnr)),
                       lapply(.SD, function(x) mean(!is.na(x))),
                       setNames(lapply(.SD, function(x) median(x, na.rm = TRUE)), paste0("median_", paste0("elim_step_arm", seq_len(K))))),
                 by = .(scenario, policy), .SDcols = paste0("elim_step_arm", seq_len(K))]
setnames(ext_summary, paste0("elim_step_arm", seq_len(K)), paste0("eliminated_share_arm_", arms$arm))
setnames(ext_summary, paste0("median_elim_step_arm", seq_len(K)), paste0("median_elimination_step_arm_", arms$arm))
ext_summary[, T := Te]
save_result(ext, "extended_horizon_replicates")
save_result(ext_summary, "extended_horizon_summary")

write_json_result(list(T = T, events = sum(y), K = K, arms = arms$arm, static_best_arm = arms$arm[static_best],
                       replicates = Rn, sensitivity_replicates = Rs, utility = utility_primary, utility_alternatives = util_alts,
                       lambda_false_positive = lf_primary, gap_bootstrap_resamples = Bg, outcomes_available_per_arm = n_avail,
                       lambda_cost = lc, lambda_safety = ls, delta = delta,
                       delay_hours = c(dmin, dmax), arrival_rate_per_hour = arrival_rate,
                       arrival_rate_database = meta$arrival_rate_database, arrival_rate_stream_own = meta$arrival_rate_stream_own,
                       arrival_rate_recent_guaranteed = meta$arrival_rate_recent_guaranteed,
                       arm_abs_gap_age = arm_gap$age, arm_abs_gap_sex = arm_gap$sex,
                       elapsed_min = as.numeric(difftime(Sys.time(), t_start, units = "mins"))), "simulation_meta")
msg("04_run_bandit_simulation.R done (%.1f min)", as.numeric(difftime(Sys.time(), t_start, units = "mins")))
