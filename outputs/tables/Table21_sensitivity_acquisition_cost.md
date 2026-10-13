# Table 21: sensitivity_acquisition_cost

| cost_model | policy | best_fixed_arm | static_best_arm | cum_regret_fixed_mean | cum_regret_fixed_lo | cum_regret_fixed_hi | static_best_regret_mean | mean_cost_mean | fnr_mean | auroc_mean | share_arm_A | share_arm_B | share_arm_C | eliminated_share_arm_A | eliminated_share_arm_B | eliminated_share_arm_C | median_elim_step_arm_A | median_elim_step_arm_B | median_elim_step_arm_C |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| fixed_per_arm | fcae | A | A | 133.4 | 126.7 | 139.5 | 0 | 0.6167 | 0.1459 | 0.8818 | 0.3333 | 0.3333 | 0.3333 | 0 | 0 | 0 | NA | NA | NA |
| fixed_per_arm | fcae_eb | A | A | 133.4 | 126.7 | 139.5 | 0 | 0.6167 | 0.1459 | 0.8818 | 0.3333 | 0.3333 | 0.3333 | 0 | 0 | 0 | NA | NA | NA |
| fixed_per_arm | fcae_strat | A | A | 133.4 | 124.0 | 143.7 | 0 | 0.6165 | 0.1463 | 0.8808 | 0.3336 | 0.3333 | 0.3331 | 0 | 0 | 0 | NA | NA | NA |
| fixed_per_arm | thompson | A | A | 31.71 | 5.616 | 99.69 | 0 | 0.3438 | 0.1572 | 0.8643 | 0.7767 | 0.1841 | 0.03917 | 0 | 0 | 0 | NA | NA | NA |
| fixed_per_arm | thompson_gauss | A | A | 12.22 | 2.995 | 22.69 | 0 | 0.2859 | 0.1606 | 0.8585 | 0.9146 | 0.07048 | 0.01496 | 0 | 0 | 0 | NA | NA | NA |
| fixed_per_arm | ucb1 | A | A | 92.93 | 82.78 | 105.5 | 0 | 0.5105 | 0.1508 | 0.8760 | 0.4814 | 0.3213 | 0.1974 | 0 | 0 | 0 | NA | NA | NA |
| fixed_per_arm | random | A | A | 133.1 | 124.6 | 140.3 | 0 | 0.6157 | 0.1476 | 0.8816 | 0.3355 | 0.3318 | 0.3327 | 0 | 0 | 0 | NA | NA | NA |
| fixed_per_arm | static_best | A | A | 0 | 0 | 0 | 0 | 0.2500 | 0.1619 | 0.8550 | 1.000 | 0 | 0 | 0 | 0 | 0 | NA | NA | NA |
| fixed_per_arm | ensemble | A | A | 295.9 | 295.9 | 295.9 | 0 | 1.000 | 0.1538 | 0.8974 | 0 | 0 | 0 | 0 | 0 | 0 | NA | NA | NA |
| fixed_per_arm | heuristic | A | A | 150.2 | 150.2 | 150.2 | 0 | 0.6110 | 0.2301 | 0.8718 | 0 | 0 | 0 | 0 | 0 | 0 | NA | NA | NA |
| acquisition_conditional | fcae | A | A | 93.20 | 87.20 | 99.22 | 0 | 0.5296 | 0.1459 | 0.8818 | 0.3333 | 0.3333 | 0.3333 | 0 | 0 | 0 | NA | NA | NA |
| acquisition_conditional | fcae_eb | A | A | 93.20 | 87.20 | 99.22 | 0 | 0.5296 | 0.1459 | 0.8818 | 0.3333 | 0.3333 | 0.3333 | 0 | 0 | 0 | NA | NA | NA |
| acquisition_conditional | fcae_strat | A | A | 93.34 | 83.91 | 103.6 | 0 | 0.5297 | 0.1463 | 0.8808 | 0.3336 | 0.3333 | 0.3331 | 0 | 0 | 0 | NA | NA | NA |
| acquisition_conditional | thompson | A | A | 32.71 | 6.333 | 84.99 | 0 | 0.3473 | 0.1574 | 0.8648 | 0.7558 | 0.1603 | 0.08384 | 0 | 0 | 0 | NA | NA | NA |
| acquisition_conditional | thompson_gauss | A | A | 13.79 | 5.884 | 27.22 | 0 | 0.2921 | 0.1594 | 0.8594 | 0.8937 | 0.07063 | 0.03569 | 0 | 0 | 0 | NA | NA | NA |
| acquisition_conditional | ucb1 | A | A | 77.52 | 70.09 | 85.17 | 0 | 0.4812 | 0.1496 | 0.8770 | 0.4425 | 0.2999 | 0.2577 | 0 | 0 | 0 | NA | NA | NA |
| acquisition_conditional | random | A | A | 93.50 | 86.80 | 99.75 | 0 | 0.5290 | 0.1460 | 0.8815 | 0.3353 | 0.3320 | 0.3327 | 0 | 0 | 0 | NA | NA | NA |
| acquisition_conditional | static_best | A | A | 0 | 0 | 0 | 0 | 0.2500 | 0.1619 | 0.8550 | 1.000 | 0 | 0 | 0 | 0 | 0 | NA | NA | NA |
| acquisition_conditional | ensemble | A | A | 175.7 | 175.7 | 175.7 | 0 | 0.7395 | 0.1538 | 0.8974 | 0 | 0 | 0 | 0 | 0 | 0 | NA | NA | NA |
| acquisition_conditional | heuristic | A | A | 122.6 | 122.6 | 122.6 | 0 | 0.5512 | 0.2301 | 0.8718 | 0 | 0 | 0 | 0 | 0 | 0 | NA | NA | NA |
