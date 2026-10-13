# analysis/R/04_run_bandit_simulation.R
# Sequential deployment simulation on the deployment stream: governance policies,
# delayed feedback, replicates, paired comparisons and sensitivity analyses.
#
# Inputs:  data/stream_predictions.csv.gz, results/arms_meta.csv, results/stream_meta.json
# Outputs (results/): replicate_metrics.csv, strategy_summary.csv, paired_differences.csv,
#   regret_curves.csv, exploration_deciles.csv, fcae_trace_rep1.csv, elimination_summary.csv,
#   sensitivity_lambda.csv, sensitivity_delta.csv, sensitivity_delay.csv, sensitivity_utility.csv,
#   implied_sample_complexity.csv, implied_sample_complexity_utility.csv, gap_bootstrap.csv,
#   extended_horizon_replicates.csv, extended_horizon_summary.csv, simulation_meta.json

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
ctx <- sp[, .(age_ge_65, sex, ext_lab_available)]
stratum_all <- 1L + ctx$ext_lab_available + 2L * ctx$age_ge_65
msg("Stream: %d decisions, %d events, K=%d, static best arm on validation = %s", T, sum(y), K, arms$arm[static_best])

policies_all <- c("fcae", "fcae_eb", "fcae_strat", "thompson", "ucb1", "random", "static_best",
                  paste0("static_", arms$arm), "ensemble", "heuristic")
policy_label <- c(fcae = "Fixed confidence action elimination (Hoeffding bound)",
                  fcae_eb = "Fixed confidence action elimination (empirical Bernstein bound)",
                  fcae_strat = "Fixed confidence action elimination (stratified, empirical Bernstein)",
                  thompson = "Thompson sampling", ucb1 = "UCB1", random = "Uniform random",
                  static_best = sprintf("Static deployment, validation best (arm %s)", arms$arm[static_best]),
                  ensemble = "Ensemble average", heuristic = "Heuristic escalation")
for (k in seq_len(K)) policy_label[paste0("static_", arms$arm[k])] <- sprintf("Static deployment, arm %s", arms$arm[k])

vp <- load_data("validation_predictions")
P_val <- as.matrix(vp[, paste0("p_", arms$arm), with = FALSE]); y_val <- as.integer(vp$mort_hosp)
# the static comparator is always chosen on validation data under the scenario's own weights
utility_primary <- if (is.null(params$reward$utility)) "brier" else params$reward$utility
validation_best_arm <- function(lambda_c, lambda_s, utility = utility_primary) which.max(colMeans(reward_matrix(P_val, y_val, thr, cost, lambda_c, lambda_s, utility)))
stopifnot(validation_best_arm(params$reward$lambda_cost, params$reward$lambda_safety) == static_best)

static_index <- function(policy, sb = static_best) {
  if (policy == "static_best") return(sb)
  if (startsWith(policy, "static_")) return(match(sub("^static_", "", policy), arms$arm))
  NA_integer_
}

# -----------------------------------------------------------------------------
# One replicate for a set of policies under one scenario
# -----------------------------------------------------------------------------
run_replicate <- function(rep, policies, lambda_c, lambda_s, delta, delay_min, delay_max, keep_trace = FALSE, thin = 10,
                          utility = utility_primary) {
  set.seed(params$reproducibility$seed_simulation + rep)
  ord <- sample.int(T)
  Pr <- P[ord, , drop = FALSE]; yr <- y[ord]; ctx_r <- ctx[ord]; st_r <- stratum_all[ord]
  R <- reward_matrix(Pr, yr, thr, cost, lambda_c, lambda_s, utility)
  best_fixed <- which.max(colSums(R))
  extra <- make_extra(Pr, yr, thr, cost, lambda_c, lambda_s, thr_ens, arm_low = 1L, arm_high = K, utility = utility)
  sched <- make_schedule(T, arrival_rate, delay_min, delay_max)
  sb <- validation_best_arm(lambda_c, lambda_s, utility)
  rows <- list(); curves <- list(); deciles <- list(); trace <- list()
  for (pol in policies) {
    res <- run_policy(pol, R, Pr, yr, thr, cost, sched, delta = delta, stratum = st_r, extra = extra,
                      static_arm = static_index(pol, sb), trace_every = thin, check_leakage = TRUE)
    m <- run_metrics(res, R, yr, ctx_r, best_fixed, thin = thin)
    rows[[pol]] <- data.table(rep = rep, policy = pol, best_fixed_arm = arms$arm[best_fixed], static_best_arm = arms$arm[sb], t(m$scalar))
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
msg("Primary scenario: utility=%s lambda_c=%.2f lambda_s=%.2f delta=%.2f delay=[%g,%g] h, %d replicates", utility_primary, lc, ls, delta, dmin, dmax, Rn)

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
                 "alert_rate", "tpr_gap_age", "tpr_gap_sex", "explore_first_decile", "explore_last_decile",
                 paste0("share_arm", seq_len(K)))
summ <- metrics[, {
  out <- list()
  for (mc in metric_cols) { s <- summary_stats(get(mc)); for (nm in names(s)[1:5]) out[[paste0(mc, "_", nm)]] <- s[[nm]] }
  out
}, by = .(policy, policy_label)]
summ <- summ[match(policies_all, policy)]
save_result(summ, "strategy_summary")

# paired differences against static best and against FCAE (per replicate pairing)
B <- params$simulation$bootstrap_resamples
paired <- function(ref) {
  rbindlist(lapply(setdiff(policies_all, ref), function(pol) {
    rbindlist(lapply(c("cum_regret_fixed", "cum_regret_oracle", "mean_reward", "mean_cost", "fnr", "auroc", "brier", "tpr_gap_age", "tpr_gap_sex"), function(mc) {
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
# elimination share per policy over replicates, for the sensitivity sets
sens_l_elim <- NULL

elim <- metrics[policy %in% c("fcae", "fcae_eb"), lapply(.SD, function(x) c(eliminated_share = mean(!is.na(x)), median_step = median(x, na.rm = TRUE),
                                                             p2.5_step = quantile(x, 0.025, na.rm = TRUE), p97.5_step = quantile(x, 0.975, na.rm = TRUE))),
                .SDcols = paste0("elim_step_arm", seq_len(K)), by = policy]
elim <- cbind(elim[, .(policy)], statistic = rep(c("eliminated_share", "median_step", "p2.5_step", "p97.5_step"), length.out = nrow(elim)),
              elim[, paste0("elim_step_arm", seq_len(K)), with = FALSE])
setnames(elim, paste0("elim_step_arm", seq_len(K)), paste0("arm_", arms$arm))
surv <- metrics[policy == "fcae", .N, by = best_fixed_arm]

# implied sample complexity from the observed gaps on the stream (full information)
implied_complexity_table <- function(R0, utility) {
  mu <- colMeans(R0); v <- apply(R0, 2, var); best0 <- which.max(mu)
  rbindlist(lapply(seq_len(K), function(a) {
    gap <- mu[best0] - mu[a]
    n_h <- implied_sample_size(gap, v[a], v[best0], K, delta, "hoeffding")
    n_b <- implied_sample_size(gap, v[a], v[best0], K, delta, "bernstein")
    data.table(utility = utility, arm = arms$arm[a], mean_reward = mu[a], sd_reward = sqrt(v[a]), gap_to_best = gap,
               gap_in_sd_units = gap / sqrt(v[a]),
               n_per_arm_hoeffding = n_h, n_per_arm_bernstein = n_b,
               decisions_round_robin_hoeffding = K * n_h, decisions_round_robin_bernstein = K * n_b,
               stream_length = T)
  }))
}
R0 <- reward_matrix(P, y, thr, cost, lc, ls, utility_primary)
isc <- implied_complexity_table(R0, utility_primary)
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
sens_pols <- c("fcae", "fcae_eb", "fcae_strat", "thompson", "ucb1", "random", "static_best", "ensemble", "heuristic")
summarise_scenario <- function(mlist, label_cols) {
  m <- rbindlist(mlist)
  m[, c("cum_regret_fixed", "mean_reward", "mean_cost", "fnr", "auroc") := lapply(.SD, as.numeric), .SDcols = c("cum_regret_fixed", "mean_reward", "mean_cost", "fnr", "auroc")]
  elim_cols <- paste0("elim_step_arm", seq_len(K))
  out <- m[, c(list(replicates = .N, best_fixed_arm = names(which.max(table(best_fixed_arm))), static_best_arm = names(which.max(table(static_best_arm))),
               cum_regret_fixed_mean = mean(cum_regret_fixed), cum_regret_fixed_lo = quantile(cum_regret_fixed, 0.025), cum_regret_fixed_hi = quantile(cum_regret_fixed, 0.975),
               mean_reward_mean = mean(mean_reward), mean_cost_mean = mean(mean_cost), fnr_mean = mean(fnr), auroc_mean = mean(auroc),
               explore_first_decile_mean = mean(explore_first_decile, na.rm = TRUE), explore_last_decile_mean = mean(explore_last_decile, na.rm = TRUE)),
          lapply(.SD, function(x) mean(!is.na(as.numeric(x))))),
    by = c(label_cols, "policy"), .SDcols = elim_cols]
  setnames(out, elim_cols, paste0("eliminated_share_arm_", arms$arm))
  out
}

msg("Sensitivity: reward weights grid")
sens_l <- list()
for (lcg in params$simulation$lambda_cost_grid) for (lsg in params$simulation$lambda_safety_grid) {
  ml <- par_lapply(seq_len(Rs), function(r) { x <- run_replicate(r, sens_pols, lcg, lsg, delta, dmin, dmax)$metrics; x[, `:=`(lambda_cost = lcg, lambda_safety = lsg)]; x })
  sens_l[[length(sens_l) + 1]] <- summarise_scenario(ml, c("lambda_cost", "lambda_safety"))
}
save_result(rbindlist(sens_l), "sensitivity_lambda")

msg("Sensitivity: confidence level grid")
sens_d <- list()
for (dg in params$simulation$delta_grid) {
  ml <- par_lapply(seq_len(Rs), function(r) { x <- run_replicate(r, c("fcae", "fcae_eb", "fcae_strat"), lc, ls, dg, dmin, dmax)$metrics; x[, delta := dg]; x })
  sens_d[[length(sens_d) + 1]] <- summarise_scenario(ml, "delta")
}
save_result(rbindlist(sens_d), "sensitivity_delta")

msg("Sensitivity: delay scenarios")
sens_y <- list()
for (sc in params$simulation$delay_scenarios) {
  ml <- par_lapply(seq_len(Rs), function(r) { x <- run_replicate(r, c("fcae", "fcae_eb", "fcae_strat", "thompson", "ucb1", "random", "static_best"), lc, ls, delta, sc$min_hours, sc$max_hours)$metrics; x[, delay_scenario := sc$label]; x })
  sens_y[[length(sens_y) + 1]] <- summarise_scenario(ml, "delay_scenario")
}
save_result(rbindlist(sens_y), "sensitivity_delay")

msg("Sensitivity: utility functional")
util_alts <- setdiff(unlist(params$simulation$utility_alternatives), utility_primary)
sens_u <- list(); isc_u <- list(implied_complexity_table(R0, utility_primary))
for (ug in util_alts) {
  ml <- par_lapply(seq_len(Rs), function(r) { x <- run_replicate(r, sens_pols, lc, ls, delta, dmin, dmax, utility = ug)$metrics; x[, utility := ug]; x })
  sens_u[[length(sens_u) + 1]] <- summarise_scenario(ml, "utility")
  isc_u[[length(isc_u) + 1]] <- implied_complexity_table(reward_matrix(P, y, thr, cost, lc, ls, ug), ug)
}
mlp <- lapply(seq_len(Rs), function(r) { x <- metrics[rep == r & policy %in% sens_pols]; x[, utility := utility_primary]; x[, policy_label := NULL]; x })
sens_u <- c(list(summarise_scenario(mlp, "utility")), sens_u)
save_result(rbindlist(sens_u), "sensitivity_utility")
save_result(rbindlist(isc_u), "implied_sample_complexity_utility")

# -----------------------------------------------------------------------------
# 3) Extended horizon: stream resampled with replacement to test whether elimination
#    occurs at the sample sizes implied by the observed gaps (a planning check, not a result
#    about new patients)
# -----------------------------------------------------------------------------
Te <- params$simulation$extended_horizon$T; Re <- params$simulation$extended_horizon$replicates
msg("Extended horizon: T=%d resampled decisions, %d replicates", Te, Re)
ext_pols <- c("fcae", "fcae_eb", "thompson", "ucb1", "random", "static_best")
run_extended <- function(rep) {
  set.seed(params$reproducibility$seed_simulation + 100000 + rep)
  idx <- sample.int(T, Te, replace = TRUE)
  Pr <- P[idx, , drop = FALSE]; yr <- y[idx]; ctx_r <- ctx[idx]; st_r <- stratum_all[idx]
  R <- reward_matrix(Pr, yr, thr, cost, lc, ls, utility_primary)
  best_fixed <- which.max(colSums(R))
  extra <- make_extra(Pr, yr, thr, cost, lc, ls, thr_ens, arm_low = 1L, arm_high = K, utility = utility_primary)
  sched <- make_schedule(Te, arrival_rate, dmin, dmax)
  rbindlist(lapply(ext_pols, function(pol) {
    res <- run_policy(pol, R, Pr, yr, thr, cost, sched, delta = delta, stratum = st_r, extra = extra,
                      static_arm = static_index(pol, static_best), trace_every = 1e9, check_leakage = TRUE)
    m <- run_metrics(res, R, yr, ctx_r, best_fixed, thin = Te)
    data.table(rep = rep, policy = pol, best_fixed_arm = arms$arm[best_fixed], t(m$scalar))
  }))
}
ext <- rbindlist(par_lapply(seq_len(Re), run_extended))
ext_summary <- ext[, c(list(replicates = .N,
                            cum_regret_fixed_mean = mean(cum_regret_fixed), cum_regret_fixed_lo = quantile(cum_regret_fixed, 0.025),
                            cum_regret_fixed_hi = quantile(cum_regret_fixed, 0.975), mean_reward_mean = mean(mean_reward),
                            mean_cost_mean = mean(mean_cost), fnr_mean = mean(fnr)),
                       lapply(.SD, function(x) mean(!is.na(x))),
                       setNames(lapply(.SD, function(x) median(x, na.rm = TRUE)), paste0("median_", paste0("elim_step_arm", seq_len(K))))),
                 by = policy, .SDcols = paste0("elim_step_arm", seq_len(K))]
setnames(ext_summary, paste0("elim_step_arm", seq_len(K)), paste0("eliminated_share_arm_", arms$arm))
setnames(ext_summary, paste0("median_elim_step_arm", seq_len(K)), paste0("median_elimination_step_arm_", arms$arm))
ext_summary[, T := Te]
save_result(ext, "extended_horizon_replicates")
save_result(ext_summary, "extended_horizon_summary")

write_json_result(list(T = T, events = sum(y), K = K, arms = arms$arm, static_best_arm = arms$arm[static_best],
                       replicates = Rn, sensitivity_replicates = Rs, utility = utility_primary, utility_alternatives = util_alts,
                       gap_bootstrap_resamples = Bg, lambda_cost = lc, lambda_safety = ls, delta = delta,
                       delay_hours = c(dmin, dmax), arrival_rate_per_hour = arrival_rate,
                       elapsed_min = as.numeric(difftime(Sys.time(), t_start, units = "mins"))), "simulation_meta")
msg("04_run_bandit_simulation.R done (%.1f min)", as.numeric(difftime(Sys.time(), t_start, units = "mins")))
