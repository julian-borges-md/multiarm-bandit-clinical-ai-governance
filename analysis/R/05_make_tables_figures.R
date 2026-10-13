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
main_pols <- c("fcae", "fcae_eb", "fcae_strat", "thompson", "ucb1", "random", "static_best", "ensemble", "heuristic")
theme_set(theme_minimal(base_size = 11))
pal <- c("fcae" = "#1b4f72", "fcae_eb" = "#5dade2", "fcae_strat" = "#2e86c1", "thompson" = "#b9770e", "ucb1" = "#7d6608",
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
  sensitivity_gap_sex = fmt_ci(tpr_gap_sex_mean, tpr_gap_sex_p2.5, tpr_gap_sex_p97.5, 3)
)]
shares <- summ[, c("policy", paste0("share_arm", seq_len(K), "_mean")), with = FALSE]
setnames(shares, paste0("share_arm", seq_len(K), "_mean"), paste0("share_arm_", arms$arm))
t5 <- merge(t5, shares, by = "policy", sort = FALSE)
save_table(t5, 5, "strategy_summary")

# -----------------------------------------------------------------------------
# Table 6: paired differences versus static best and versus FCAE
# -----------------------------------------------------------------------------
t6 <- pd[metric %in% c("cum_regret_fixed", "mean_reward", "mean_cost", "fnr", "auroc", "tpr_gap_age", "tpr_gap_sex"),
         .(reference, policy, metric, mean_policy = round(mean_policy, 4), mean_reference = round(mean_reference, 4),
           difference = fmt_ci(diff_mean, diff_lo, diff_hi, 4), relative_pct = round(relative_pct, 1),
           share_of_replicates_lower = round(share_lower, 2))]
save_table(t6, 6, "paired_differences")

# -----------------------------------------------------------------------------
# Table 7: elimination and exploration
# -----------------------------------------------------------------------------
dec_w <- dcast(dec[policy %in% c("fcae", "fcae_eb", "fcae_strat", "thompson", "ucb1")], policy ~ decile, value.var = "explore_share_mean")
setnames(dec_w, as.character(1:10), paste0("decile_", 1:10))
save_table(dec_w, 7, "exploration_by_decile")
save_table(elim, 8, "elimination_summary")
isc <- load_result("implied_sample_complexity")
ext <- load_result("extended_horizon_summary")
save_table(ext[, lapply(.SD, function(x) if (is.numeric(x)) signif(x, 4) else x)], 15, "extended_horizon")
save_table(isc[, lapply(.SD, function(x) if (is.numeric(x)) signif(x, 4) else x)], 14, "implied_sample_complexity")

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
save_table(strat[, .(model, ext_lab_available, age_ge_65, n, events, auroc = round(auroc, 3), brier = round(brier, 4),
                     fnr = round(fnr, 3), mean_reward = round(mean_reward, 4))], 13, "stream_performance_by_stratum")

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
  tr[, bound := ifelse(policy == "fcae", "Hoeffding bound", "Empirical Bernstein bound")]
  p3a <- ggplot(tr[!is.na(mean) & is.finite(lcb)], aes(x = t, colour = arm_key, fill = arm_key)) +
    geom_ribbon(aes(ymin = pmax(lcb, 0), ymax = pmin(ucb, 1)), alpha = 0.15, colour = NA) +
    geom_line(aes(y = mean), linewidth = 0.8) + facet_wrap(~ bound, ncol = 1) +
    labs(x = "Sequential ICU admissions", y = "Estimated composite reward with confidence bounds", colour = "Arm", fill = "Arm") +
    theme(legend.position = "bottom")
  save_fig(p3a, 3, "FCAE_ConfidenceBounds", width = 8, height = 7)
}
dec_m <- dec[policy %in% c("fcae", "fcae_eb", "fcae_strat", "thompson", "ucb1")]
dec_m[, policy := factor(policy, levels = c("fcae", "fcae_eb", "fcae_strat", "thompson", "ucb1"))]
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

msg("05_make_tables_figures.R done")
