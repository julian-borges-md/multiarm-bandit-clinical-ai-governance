# analysis/R/05_make_tables_figures.R
# Manuscript tables and figures from the results files. Reads only results/ and tables/,
# never patient level data, so it can run anywhere the results exist.

if (!exists("cfg", inherits = TRUE)) source(file.path("analysis", "R", "00_setup.R"))
suppressPackageStartupMessages({ library(data.table); library(ggplot2); library(scales) })

msg("05_make_tables_figures.R starting")
summ <- load_result("strategy_summary")
pd   <- load_result("paired_differences")
cur  <- load_result("regret_curves")
dec  <- load_result("exploration_deciles")
elim <- load_result("elimination_summary")
arms_meta <- load_result("arms_meta")
arms <- arms_meta[arm != "ensemble"]
K <- nrow(arms)
sens_l <- load_result("sensitivity_lambda"); sens_d <- load_result("sensitivity_delta"); sens_y <- load_result("sensitivity_delay")
strat <- load_result("stream_performance_by_stratum")
trace_path <- file.path(cfg$dirs$results, "fcae_trace_rep1.csv")

fmt_ci <- function(m, lo, hi, d = 3) sprintf(paste0("%.", d, "f (%.", d, "f to %.", d, "f)"), m, lo, hi)
main_pols <- c("fcae", "fcae_eb", "fcae_strat", "thompson", "thompson_gauss", "ucb1", "random", "static_best",
               paste0("static_", setdiff(arms$arm, arms$arm[arms$static_best])), "ensemble", "heuristic")
theme_set(theme_minimal(base_size = 11))
pal <- c("fcae" = "#1b4f72", "fcae_eb" = "#5dade2", "fcae_strat" = "#2e86c1", "thompson" = "#b9770e", "thompson_gauss" = "#e67e22", "ucb1" = "#7d6608",
         "random" = "#7b7d7d", "static_best" = "#117a65", "ensemble" = "#884ea0", "heuristic" = "#cb4335")
for (k in seq_len(K)) pal[paste0("static_", arms$arm[k])] <- c("#1e8449", "#239b56", "#28b463")[k]

# -----------------------------------------------------------------------------
# Table 5: strategy summary
# -----------------------------------------------------------------------------
t5 <- summ[, .(
  policy, policy_label,
  cumulative_regret_fixed = fmt_ci(cum_regret_fixed_mean, cum_regret_fixed_p2.5, cum_regret_fixed_p97.5, 1),
  cumulative_regret_oracle = fmt_ci(cum_regret_oracle_mean, cum_regret_oracle_p2.5, cum_regret_oracle_p97.5, 1),
  mean_reward = fmt_ci(mean_reward_mean, mean_reward_p2.5, mean_reward_p97.5, 4),
  mean_cost = fmt_ci(mean_cost_mean, mean_cost_p2.5, mean_cost_p97.5, 3),
  false_negative_rate = fmt_ci(fnr_mean, fnr_p2.5, fnr_p97.5, 3),
  auroc = fmt_ci(auroc_mean, auroc_p2.5, auroc_p97.5, 3),
  brier = fmt_ci(brier_mean, brier_p2.5, brier_p97.5, 4),
  sensitivity_gap_age = fmt_ci(tpr_gap_age_mean, tpr_gap_age_p2.5, tpr_gap_age_p97.5, 3),
  sensitivity_gap_sex = fmt_ci(tpr_gap_sex_mean, tpr_gap_sex_p2.5, tpr_gap_sex_p97.5, 3),
  sensitivity_gap_age_signed = fmt_ci(tpr_gap_age_signed_mean, tpr_gap_age_signed_p2.5, tpr_gap_age_signed_p97.5, 3),
  sensitivity_gap_sex_signed = fmt_ci(tpr_gap_sex_signed_mean, tpr_gap_sex_signed_p2.5, tpr_gap_sex_signed_p97.5, 3),
  experienced_gap_age = fmt_ci(experienced_gap_age_mean, experienced_gap_age_p2.5, experienced_gap_age_p97.5, 3),
  experienced_gap_sex = fmt_ci(experienced_gap_sex_mean, experienced_gap_sex_p2.5, experienced_gap_sex_p97.5, 3),
  sensitivity_range_race = fmt_ci(tpr_range_race_mean, tpr_range_race_p2.5, tpr_range_race_p97.5, 3)
)]
shares <- summ[, c("policy", paste0("share_arm", seq_len(K), "_mean")), with = FALSE]
setnames(shares, paste0("share_arm", seq_len(K), "_mean"), paste0("share_arm_", arms$arm))
t5 <- merge(t5, shares, by = "policy", sort = FALSE)
save_table(t5, 5, "strategy_summary")

# -----------------------------------------------------------------------------
# Table 6: paired differences versus static best and versus FCAE
# -----------------------------------------------------------------------------
t6 <- pd[metric %in% c("cum_regret_fixed", "mean_reward", "mean_cost", "fnr", "auroc", "tpr_gap_age", "tpr_gap_sex", "tpr_gap_age_signed", "tpr_gap_sex_signed", "experienced_gap_age", "experienced_gap_sex"),
         .(reference, policy, metric, mean_policy = round(mean_policy, 4), mean_reference = round(mean_reference, 4),
           difference = fmt_ci(diff_mean, diff_lo, diff_hi, 4), relative_pct = round(relative_pct, 1),
           share_of_replicates_lower = round(share_lower, 2))]
save_table(t6, 6, "paired_differences")

# -----------------------------------------------------------------------------
# Table 7: elimination and exploration
# -----------------------------------------------------------------------------
dec_w <- dcast(dec[policy %in% c("fcae", "fcae_eb", "fcae_strat", "thompson", "thompson_gauss", "ucb1")], policy ~ decile, value.var = "explore_share_mean")
setnames(dec_w, as.character(1:10), paste0("decile_", 1:10))
save_table(dec_w, 7, "exploration_by_decile")
save_table(elim, 8, "elimination_summary")
isc <- load_result("implied_sample_complexity")
ext <- load_result("extended_horizon_summary")
sig <- function(dt) dt[, lapply(.SD, function(x) if (is.numeric(x)) signif(x, 6) else x)]
save_table(sig(ext), 15, "extended_horizon")
save_table(sig(isc), 14, "implied_sample_complexity")

# -----------------------------------------------------------------------------
# Tables 16 and 17: utility functional sensitivity and patient level gap bootstrap
# -----------------------------------------------------------------------------
sens_u <- load_result("sensitivity_utility")
isc_u <- load_result("implied_sample_complexity_scenarios")
gbs <- load_result("gap_bootstrap")
save_table(sens_u[, c(.(utility = utility, policy = policy, best_fixed_arm = best_fixed_arm, static_best_arm = static_best_arm,
                        cum_regret_fixed = fmt_ci(cum_regret_fixed_mean, cum_regret_fixed_lo, cum_regret_fixed_hi, 1),
                        mean_reward = round(mean_reward_mean, 4), mean_cost = round(mean_cost_mean, 3), fnr = round(fnr_mean, 3)),
                      lapply(.SD, function(x) round(x, 2))), .SDcols = grep("^eliminated_share_arm_", names(sens_u), value = TRUE)],
           16, "sensitivity_utility")
save_table(sig(isc_u), 18, "implied_sample_complexity_scenarios")
fmt_n <- function(m, lo, hi) { f <- function(x) formatC(round(x), format = "d", big.mark = ","); ifelse(is.na(m), "best arm", sprintf("%s (%s to %s)", f(m), f(lo), f(hi))) }
save_table(gbs[, .(arm, resamples, share_best = round(share_best, 3),
                   mean_reward = fmt_ci(mean_reward_point, mean_reward_lo, mean_reward_hi, 4),
                   gap_to_best = ifelse(gap_point <= 0, "best arm", fmt_ci(gap_point, gap_lo, gap_hi, 4)),
                   n_per_arm_hoeffding = fmt_n(n_per_arm_hoeffding_point, n_per_arm_hoeffding_lo, n_per_arm_hoeffding_hi),
                   n_per_arm_bernstein = fmt_n(n_per_arm_bernstein_point, n_per_arm_bernstein_lo, n_per_arm_bernstein_hi),
                   share_resamples_n_bernstein_within_stream = round(share_resamples_n_bernstein_within_stream, 3))],
           17, "gap_bootstrap")

# -----------------------------------------------------------------------------
# Tables 19 to 28: cost vector, false positive weight, acquisition conditional cost, drift,
# subgroup sensitivity, break even weight, drift description, stay offsets, acquisition cost summary
# -----------------------------------------------------------------------------
scen_cols <- function(dt, label_cols) dt[, c(label_cols, "policy", "best_fixed_arm", "static_best_arm", "cum_regret_fixed_mean", "cum_regret_fixed_lo", "cum_regret_fixed_hi",
                                              "static_best_regret_mean", "mean_cost_mean", "fnr_mean", "auroc_mean",
                                              grep("^share_arm_|^eliminated_share_arm_|^median_elim_step_arm_", names(dt), value = TRUE)), with = FALSE]
save_table(sig(scen_cols(load_result("sensitivity_cost_vector"), c("cost_vector", "costs"))), 19, "sensitivity_cost_vector")
save_table(sig(scen_cols(load_result("sensitivity_false_positive"), "lambda_false_positive")), 20, "sensitivity_false_positive")
if (file.exists(file.path(cfg$dirs$results, "sensitivity_acquisition_cost.csv"))) {
  save_table(sig(scen_cols(load_result("sensitivity_acquisition_cost"), "cost_model")), 21, "sensitivity_acquisition_cost")
  save_table(sig(load_result("acquisition_conditional_cost_summary")), 28, "acquisition_conditional_cost_summary")
}
save_table(sig(scen_cols(load_result("sensitivity_drift"), c("drift_scenario", "drift_arm", "drift_start_fraction", "logit_noise_sd", "delay_scenario"))), 22, "sensitivity_drift")
save_table(sig(load_result("arm_subgroup_sensitivity")), 24, "arm_subgroup_sensitivity")
save_table(sig(load_result("false_positive_break_even")), 25, "false_positive_break_even")
save_table(sig(load_result("drift_scenario_description")), 26, "drift_scenario_description")
if (file.exists(file.path(cfg$dirs$results, "stay_offset_distribution.csv"))) save_table(load_result("stay_offset_distribution"), 27, "stay_offset_distribution")

# -----------------------------------------------------------------------------
# Tables 9 to 11: sensitivity analyses
# -----------------------------------------------------------------------------
sl <- dcast(sens_l[policy %in% c("fcae", "fcae_eb", "fcae_strat", "thompson", "static_best", "random", "ensemble", "heuristic")],
            lambda_cost + lambda_safety ~ policy, value.var = "cum_regret_fixed_mean")
save_table(sl, 9, "sensitivity_lambda_regret")
elim_share_cols <- grep("^eliminated_share_arm_", names(sens_l), value = TRUE)
sl2 <- sens_l[, c(.(lambda_cost = lambda_cost, lambda_safety = lambda_safety, policy = policy, best_fixed_arm = best_fixed_arm, static_best_arm = static_best_arm,
                    cum_regret_fixed_mean = round(cum_regret_fixed_mean, 2), mean_cost = round(mean_cost_mean, 3), fnr = round(fnr_mean, 3), auroc = round(auroc_mean, 3)),
                  lapply(.SD, function(x) round(x, 2))), .SDcols = elim_share_cols]
save_table(sl2, 10, "sensitivity_lambda_full")
save_table(sens_d[, c(.(delta = delta, policy = policy, cum_regret_fixed = fmt_ci(cum_regret_fixed_mean, cum_regret_fixed_lo, cum_regret_fixed_hi, 1),
                        fnr = round(fnr_mean, 3), explore_first_decile = round(explore_first_decile_mean, 3)), lapply(.SD, function(x) round(x, 2))),
                  .SDcols = grep("^eliminated_share_arm_", names(sens_d), value = TRUE)], 11, "sensitivity_delta")
save_table(sens_y[, .(delay_scenario, policy, cum_regret_fixed = fmt_ci(cum_regret_fixed_mean, cum_regret_fixed_lo, cum_regret_fixed_hi, 1),
                      mean_reward = round(mean_reward_mean, 4), fnr = round(fnr_mean, 3))], 12, "sensitivity_delay")
save_table(strat[, .(model, ext_lab_available, age_ge_65, n, events, auroc = round(auroc, 3), auroc_lo = round(auroc_lo, 3), auroc_hi = round(auroc_hi, 3),
                     brier = round(brier, 4), sensitivity = round(sensitivity, 3), fnr = round(fnr, 3), mean_reward = round(mean_reward, 4))], 13, "stream_performance_by_stratum")

# -----------------------------------------------------------------------------
# Figure 2: cumulative regret curves
# -----------------------------------------------------------------------------
cur_m <- cur[policy %in% main_pols]
cur_m[, policy := factor(policy, levels = main_pols)]
p2 <- ggplot(cur_m, aes(x = t, y = cum_regret_fixed_mean, colour = policy, fill = policy)) +
  geom_ribbon(aes(ymin = cum_regret_fixed_lo, ymax = cum_regret_fixed_hi), alpha = 0.12, colour = NA) +
  geom_line(linewidth = 0.8) +
  scale_colour_manual(values = pal, labels = summ[match(main_pols, policy), policy_label]) +
  scale_fill_manual(values = pal, guide = "none") +
  labs(x = "Sequential ICU admissions in the deployment stream", y = "Cumulative regret (composite reward units)", colour = NULL) +
  theme(legend.position = "bottom") + guides(colour = guide_legend(ncol = 2))
save_fig(p2, 2, "CumulativeRegret", width = 8.5, height = 6)

# -----------------------------------------------------------------------------
# Figure 3: FCAE confidence bounds (replicate 1) and selection share by decile
# -----------------------------------------------------------------------------
if (file.exists(trace_path)) {
  tr <- fread(trace_path)
  tr[, arm_key := factor(arm_key, levels = arms$arm)]
  tr[, bound := factor(ifelse(policy == "fcae", "Hoeffding bound", "Empirical Bernstein bound"), levels = c("Hoeffding bound", "Empirical Bernstein bound"))]
  p3a <- ggplot(tr[!is.na(mean) & is.finite(lcb)], aes(x = t, colour = arm_key, fill = arm_key)) +
    geom_ribbon(aes(ymin = pmax(lcb, 0), ymax = pmin(ucb, 1)), alpha = 0.15, colour = NA) +
    geom_line(aes(y = mean), linewidth = 0.8) + facet_wrap(~ bound, ncol = 1) +
    labs(x = "Sequential ICU admissions", y = "Estimated composite reward with confidence bounds", colour = "Arm", fill = "Arm") +
    theme(legend.position = "bottom")
  save_fig(p3a, 3, "FCAE_ConfidenceBounds", width = 8, height = 7)
}
dec_m <- dec[policy %in% c("fcae", "fcae_eb", "fcae_strat", "thompson", "thompson_gauss", "ucb1")]
dec_m[, policy := factor(policy, levels = c("fcae", "fcae_eb", "fcae_strat", "thompson", "thompson_gauss", "ucb1"))]
p4 <- ggplot(dec_m, aes(x = decile, y = explore_share_mean, colour = policy)) +
  geom_line(linewidth = 0.8) + geom_point() +
  geom_errorbar(aes(ymin = explore_share_lo, ymax = explore_share_hi), width = 0.2, alpha = 0.6) +
  scale_x_continuous(breaks = 1:10) + scale_y_continuous(labels = percent) +
  scale_colour_manual(values = pal, labels = summ[match(levels(dec_m$policy), policy), policy_label]) +
  labs(x = "Decile of the deployment stream", y = "Share of decisions on non dominant arms", colour = NULL) +
  theme(legend.position = "bottom") + guides(colour = guide_legend(ncol = 2))
save_fig(p4, 4, "ExplorationProxy", width = 8, height = 5)

# -----------------------------------------------------------------------------
# Figure 5: cumulative cost
# -----------------------------------------------------------------------------
p5 <- ggplot(cur_m, aes(x = t, y = cum_cost_mean / t, colour = policy)) + geom_line(linewidth = 0.8) +
  scale_colour_manual(values = pal, labels = summ[match(main_pols, policy), policy_label]) +
  labs(x = "Sequential ICU admissions", y = "Mean normalised cost per decision (running)", colour = NULL) +
  theme(legend.position = "bottom") + guides(colour = guide_legend(ncol = 2))
save_fig(p5, 5, "RunningCost", width = 8.5, height = 5.5)

# -----------------------------------------------------------------------------
# Figure 6: sensitivity to reward weights (regret of FCAE minus static best)
# -----------------------------------------------------------------------------
sw <- dcast(sens_l[policy %in% c("fcae_eb", "static_best")], lambda_cost + lambda_safety ~ policy, value.var = "cum_regret_fixed_mean")
sw[, diff := fcae_eb - static_best]
p6 <- ggplot(sw, aes(x = factor(lambda_cost), y = factor(lambda_safety), fill = diff)) + geom_tile() +
  geom_text(aes(label = sprintf("%.1f", diff)), size = 3.5) +
  scale_fill_gradient2(low = "#1a9850", mid = "white", high = "#d73027", midpoint = 0) +
  labs(x = "Cost weight (lambda_c)", y = "Safety weight (lambda_s)", fill = "Regret difference\nFCAE (Bernstein) minus static best")
save_fig(p6, 6, "SensitivityLambda", width = 6.5, height = 5)

# -----------------------------------------------------------------------------
# Figure 7: arm performance by context stratum on the stream
# -----------------------------------------------------------------------------
strat[, stratum := sprintf("ext labs %s, age %s", ifelse(ext_lab_available == 1, "available", "absent"), ifelse(age_ge_65 == 1, "65+", "<65"))]
p7 <- ggplot(strat, aes(x = stratum, y = mean_reward, fill = model)) + geom_col(position = position_dodge(width = 0.8), width = 0.7) +
  labs(x = NULL, y = "Mean composite reward on the stream", fill = "Arm") + theme(axis.text.x = element_text(angle = 15, hjust = 1))
save_fig(p7, 7, "ArmPerformanceByStratum", width = 8, height = 5)


# -----------------------------------------------------------------------------
# Figure 8: the evidence horizon. Outcomes per arm a confident retirement needs against the outcomes the stream supplies
# -----------------------------------------------------------------------------
gb   <- load_result("gap_bootstrap")
isc  <- load_result("implied_sample_complexity_scenarios")
n_avail <- isc$outcomes_available_per_arm[1]
n_ext   <- floor(params$simulation$extended_horizon$T / K)
h8a <- rbindlist(list(
  gb[!is.na(n_per_arm_hoeffding_point), .(panel = "A. Primary analysis, with patient level bootstrap intervals", x = "Hoeffding bound", arm,
                                           y = n_per_arm_hoeffding_point, lo = n_per_arm_hoeffding_lo, hi = n_per_arm_hoeffding_hi)],
  gb[!is.na(n_per_arm_bernstein_point), .(panel = "A. Primary analysis, with patient level bootstrap intervals", x = "Empirical Bernstein bound", arm,
                                           y = n_per_arm_bernstein_point, lo = n_per_arm_bernstein_lo, hi = n_per_arm_bernstein_hi)]))
scen_lab <- c(utility_brier = "Primary", utility_accuracy = "Accuracy\nutility", cost_vector_compressed = "Compressed\ncosts",
              cost_vector_expanded = "Expanded\ncosts", cost_vector_equal = "Equal\ncosts", cost_acquisition_conditional = "Acquisition\nconditional cost",
              false_positive_weight_0.10 = "Alert\nweight 0.10", false_positive_weight_0.20 = "Alert\nweight 0.20", false_positive_weight_0.40 = "Alert\nweight 0.40")
h8b <- isc[scenario %in% names(scen_lab) & !is.na(n_per_arm_bernstein),
           .(panel = "B. Scenarios, empirical Bernstein bound", x = scen_lab[scenario], arm, y = n_per_arm_bernstein, lo = NA_real_, hi = NA_real_)]
h8 <- rbind(h8a, h8b)
h8[, x := factor(x, levels = c("Hoeffding bound", "Empirical Bernstein bound", unname(scen_lab)))]
h8[, arm := factor(arm, levels = arms$arm)]
ref8 <- data.table(y = c(n_avail, n_ext), lab = c(sprintf("available in the stream (%s per arm)", format(n_avail, big.mark = ",")),
                                                 sprintf("extended horizon (%s per arm)", format(n_ext, big.mark = ","))))
p8 <- ggplot(h8, aes(x = x, y = y, colour = arm)) +
  geom_hline(data = ref8, aes(yintercept = y, linetype = lab), colour = "grey35") +
  geom_errorbar(aes(ymin = lo, ymax = hi), width = 0.25, position = position_dodge(width = 0.5), na.rm = TRUE) +
  geom_point(size = 2.6, position = position_dodge(width = 0.5)) +
  facet_wrap(~ panel, ncol = 1, scales = "free") +
  scale_y_log10(labels = comma, breaks = c(1e3, 3e3, 1e4, 3e4, 1e5, 3e5, 1e6, 3e6, 1e7)) +
  scale_colour_manual(values = c(A = "#1e8449", B = "#2e86c1", C = "#cb4335"), drop = FALSE) +
  scale_linetype_manual(values = c("dashed", "dotted")) +
  labs(x = NULL, y = "Outcomes per arm needed to retire the arm at delta = 0.05 (log scale)", colour = "Arm retired", linetype = NULL) +
  theme(legend.position = "bottom", legend.box = "vertical")
save_fig(p8, 8, "EvidenceHorizon", width = 8.5, height = 8)

# -----------------------------------------------------------------------------
# Figure 9: when the validation choice is wrong on the stream (drift scenarios)
# -----------------------------------------------------------------------------
sdr <- load_result("sensitivity_drift")
drift_lab <- c(arm_A_moderate_from_start = "Moderate degradation of arm A from the start", arm_A_moderate_from_third = "Moderate degradation of arm A from one third",
               arm_A_severe_from_start = "Severe degradation of arm A from the start", arm_A_severe_from_third = "Severe degradation of arm A from one third")
pol9 <- c("static_A", "fcae_eb", "ucb1", "thompson_gauss", "random")
s9 <- sdr[policy %in% pol9 & drift_scenario %in% names(drift_lab)]
s9_static <- unique(sdr[drift_scenario %in% names(drift_lab), .(drift_scenario, delay_scenario, cum_regret_fixed_mean = static_best_regret_mean,
                                                               cum_regret_fixed_lo = NA_real_, cum_regret_fixed_hi = NA_real_)])
s9_static[, policy := "static_A"]
s9 <- rbind(s9[, .(drift_scenario, delay_scenario, policy, cum_regret_fixed_mean, cum_regret_fixed_lo, cum_regret_fixed_hi)], s9_static, use.names = TRUE)
s9[, policy := factor(policy, levels = pol9)]
s9[, scenario_label := factor(drift_lab[drift_scenario], levels = unname(drift_lab))]
s9[, delay_scenario := factor(delay_scenario, levels = c("none", "primary", "long"), labels = c("No delay", "Primary delay", "Long delay"))]
lab9 <- c(static_A = "Static deployment of arm A (the validation choice)", fcae_eb = "Fixed confidence action elimination (empirical Bernstein)",
          ucb1 = "UCB1", thompson_gauss = "Thompson sampling (Gaussian posterior)", random = "Uniform random")
p9 <- ggplot(s9, aes(x = delay_scenario, y = cum_regret_fixed_mean, colour = policy)) +
  geom_errorbar(aes(ymin = cum_regret_fixed_lo, ymax = cum_regret_fixed_hi), width = 0.25, position = position_dodge(width = 0.6), na.rm = TRUE) +
  geom_point(aes(shape = policy), size = 2.6, position = position_dodge(width = 0.6)) +
  facet_wrap(~ scenario_label, ncol = 2, scales = "free_y") +
  scale_shape_manual(values = c(static_A = 18, fcae_eb = 16, ucb1 = 16, thompson_gauss = 16, random = 16), labels = lab9[pol9]) +
  scale_colour_manual(values = pal[pol9], labels = lab9[pol9]) +
  labs(x = NULL, y = "Cumulative regret against the best fixed arm on the stream", colour = NULL, shape = NULL,
       caption = "Static deployment of arm A is shown without an interval; the regret of the other policies is the mean over 30 replicates with its 2.5 and 97.5 percentiles.") +
  theme(legend.position = "bottom") + guides(colour = guide_legend(ncol = 2), shape = guide_legend(ncol = 2))
save_fig(p9, 9, "DriftScenarios", width = 8.5, height = 7.5)

# -----------------------------------------------------------------------------
# Figure 10: composition of the reward gaps on the stream (utility, safety and cost terms)
# -----------------------------------------------------------------------------
mp <- load_result("model_performance")
ms <- mp[set == "stream" & model %in% arms$arm]
LC <- params$reward$lambda_cost; LS <- params$reward$lambda_safety; denom <- 1 + LC + LS
ref_arm <- arms$arm[arms$static_best]
prev <- ms$events[1] / ms$n[1]
ref_row <- ms[model == ref_arm]
cost_map <- setNames(arms_meta$cost, arms_meta$arm)
comp <- ms[model != ref_arm, .(arm = model,
  `Utility term (Brier loss)` = (brier - ref_row$brier) / denom,
  `Safety term (missed deaths)` = LS * prev * (fnr - ref_row$fnr) / denom,
  `Cost term (declared cost)` = LC * (cost_map[model] - cost_map[ref_arm]) / denom)]
comp_l <- melt(comp, id.vars = "arm", variable.name = "term", value.name = "value")
tot <- comp_l[, .(gap = sum(value)), by = arm]
p10 <- ggplot(comp_l, aes(x = arm, y = value, fill = term)) + geom_col(width = 0.6) +
  geom_point(data = tot, aes(x = arm, y = gap), inherit.aes = FALSE, shape = 23, size = 3, fill = "white") +
  geom_hline(yintercept = 0, colour = "grey35") +
  geom_text(data = comp_l[abs(value) > 0.002], aes(label = sprintf("%+.4f", value)), position = position_stack(vjust = 0.5), size = 3.4, colour = "white") +
  geom_text(data = tot, aes(x = arm, y = gap, label = sprintf("gap %.4f", gap)), inherit.aes = FALSE, hjust = -0.25, size = 3.4) +
  scale_fill_manual(values = c("#2e86c1", "#b9770e", "#cb4335")) +
  labs(x = sprintf("Arm compared with arm %s (the preferred arm)", ref_arm), y = "Contribution to the reward gap (unit scale)", fill = NULL,
       caption = "Diamond: total gap. Positive values favour the preferred arm.") +
  theme(legend.position = "bottom") + guides(fill = guide_legend(ncol = 1))
save_fig(p10, 10, "GapComposition", width = 6.5, height = 5.5)

# -----------------------------------------------------------------------------
# Figure 11: the alert burden weight at which the preferred arm changes
# -----------------------------------------------------------------------------
be <- load_result("false_positive_break_even")
be_na <- be[!is.na(break_even_lambda_f)]
grid_f <- seq(0, 1.6, by = 0.01)
curves <- be_na[, .(lambda_f = grid_f, gap = (raw_gap_to_best - grid_f * (false_positive_rate_best - false_positive_rate)) / (denom + grid_f)), by = arm]
pts <- isc[grepl("^false_positive_weight_", scenario) & !is.na(gap_to_best) & gap_to_best > 0,
           .(arm, lambda_f = as.numeric(sub("false_positive_weight_", "", scenario)), gap = gap_to_best)]
p11 <- ggplot(curves, aes(x = lambda_f, y = gap, colour = arm)) + geom_hline(yintercept = 0, colour = "grey35") +
  geom_line(linewidth = 0.9) + geom_point(data = pts, size = 2.4) +
  geom_vline(data = be_na, aes(xintercept = break_even_lambda_f, colour = arm), linetype = "dotted") +
  geom_text(data = be_na, aes(x = break_even_lambda_f, y = max(curves$gap) * 0.95, label = sprintf("break even %.2f", break_even_lambda_f), colour = arm),
            hjust = -0.05, size = 3.3, show.legend = FALSE) +
  scale_colour_manual(values = c(B = "#2e86c1", C = "#cb4335")) +
  labs(x = "Alert burden weight (lambda_f) on the scale of the missed death penalty", y = sprintf("Reward gap of the arm to arm %s (unit scale)", ref_arm), colour = "Arm",
       caption = "Lines: gap implied by the stream error rates; points: simulated sensitivity grid.") +
  theme(legend.position = "bottom")
save_fig(p11, 11, "AlertBurdenBreakEven", width = 7.5, height = 5)

# -----------------------------------------------------------------------------
# Figure 12: per arm sensitivity by subgroup on the stream, with Wilson intervals
# -----------------------------------------------------------------------------
sg <- load_result("arm_subgroup_sensitivity")
sg[, variable := factor(variable, levels = c("age_group", "sex_group", "race_group"), labels = c("Age group", "Sex", "Race group (administrative)"))]
sg[, level_label := sprintf("%s (%s deaths)", level, format(deaths, big.mark = ",", trim = TRUE))]
sg[, model := factor(model, levels = arms$arm)]
p12 <- ggplot(sg, aes(x = level_label, y = sensitivity, colour = model)) +
  geom_hline(yintercept = 0.8, linetype = "dashed", colour = "grey35") +
  geom_errorbar(aes(ymin = sensitivity_lo, ymax = sensitivity_hi), width = 0.25, position = position_dodge(width = 0.6)) +
  geom_point(size = 2.4, position = position_dodge(width = 0.6)) +
  facet_wrap(~ variable, ncol = 1, scales = "free_x") + scale_y_continuous(labels = percent) +
  scale_colour_manual(values = c(A = "#1e8449", B = "#2e86c1", C = "#cb4335")) +
  labs(x = NULL, y = "Sensitivity at the validation threshold (Wilson 95 percent interval)", colour = "Arm",
       caption = "Dashed line: the 80 percent sensitivity at which each threshold was set on validation data.") +
  theme(legend.position = "bottom", axis.text.x = element_text(angle = 15, hjust = 1))
save_fig(p12, 12, "SubgroupSensitivity", width = 8.5, height = 9)

# -----------------------------------------------------------------------------
# Figure 13: when the elimination decision arrives on the extended horizon
# -----------------------------------------------------------------------------
ehr <- load_result("extended_horizon_replicates")
dsc <- load_result("drift_scenario_description")
arm_idx <- function(a) match(a, arms$arm)
e13 <- rbind(
  ehr[scenario == "primary" & policy == "fcae_eb", .(case = sprintf("Primary analysis: retirement of arm %s", arms$arm[3]), step = get(paste0("elim_step_arm", 3)))],
  ehr[scenario == "arm_A_severe_from_start" & policy == "fcae_eb", .(case = "Severe degradation of arm A: retirement of arm A", step = get(paste0("elim_step_arm", arm_idx("A"))))])
e13[, case := factor(case, levels = unique(case))]
imp13 <- data.table(case = levels(e13$case),
                    step = c(isc[scenario == "utility_brier" & arm == arms$arm[3], decisions_round_robin_bernstein],
                             dsc[drift_scenario == "arm_A_severe_from_start", decisions_round_robin_bernstein]))
n_T <- as.numeric(params$simulation$extended_horizon$T)
p13 <- ggplot(e13[!is.na(step)], aes(x = step, colour = case)) + stat_ecdf(linewidth = 0.9) +
  geom_vline(xintercept = n_avail * K, linetype = "dashed", colour = "grey35") +
  geom_vline(data = imp13, aes(xintercept = step, colour = case), linetype = "dotted") +
  annotate("text", x = n_avail * K, y = 0.6, label = sprintf("stream length\n(%s decisions)", format(n_avail * K, big.mark = ",")), hjust = 1.08, size = 3.3, colour = "grey25") +
  scale_x_continuous(labels = comma, limits = c(0, n_T)) + scale_y_continuous(labels = percent) +
  scale_colour_manual(values = c("#cb4335", "#1e8449")) +
  labs(x = "Decision index at which the arm was retired (empirical Bernstein bound, 30 replicates)", y = "Share of replicates with a decision by this index",
       colour = NULL, caption = "Dotted lines: decisions implied by the sample complexity formula for each case.") +
  theme(legend.position = "bottom") + guides(colour = guide_legend(ncol = 1))
save_fig(p13, 13, "ExtendedHorizonDecisionTime", width = 8, height = 5.5)

msg("05_make_tables_figures.R done")
