# Table 15: extended_horizon

| scenario | policy | replicates | best_fixed_arm | cum_regret_fixed_mean | cum_regret_fixed_lo | cum_regret_fixed_hi | mean_reward_mean | mean_cost_mean | fnr_mean | eliminated_share_arm_A | eliminated_share_arm_B | eliminated_share_arm_C | median_elimination_step_arm_A | median_elimination_step_arm_B | median_elimination_step_arm_C | T |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| primary | fcae | 30.00 | A | 542.0 | 518.1 | 570.3 | 0.9043 | 0.6167 | 0.1474 | 0 | 0 | 0 |  | NA |  | 30000 |
| primary | fcae_eb | 30.00 | A | 464.4 | 419.4 | 519.2 | 0.9069 | 0.5711 | 0.1484 | 0 | 0 | 1.000 |  | NA | 22233 | 30000 |
| primary | thompson | 30.00 | A | 39.85 | 9.759 | 133.7 | 0.9211 | 0.2793 | 0.1610 | 0 | 0 | 0 |  | NA |  | 30000 |
| primary | thompson_gauss | 30.00 | A | 16.69 | 6.620 | 36.06 | 0.9218 | 0.2624 | 0.1617 | 0 | 0 | 0 |  | NA |  | 30000 |
| primary | ucb1 | 30.00 | A | 277.3 | 244.8 | 307.0 | 0.9132 | 0.4459 | 0.1533 | 0 | 0 | 0 |  | NA |  | 30000 |
| primary | random | 30.00 | A | 542.8 | 514.4 | 576.9 | 0.9043 | 0.6167 | 0.1478 | 0 | 0 | 0 |  | NA |  | 30000 |
| primary | static_best | 30.00 | A | 0 | 0 | 0 | 0.9224 | 0.2500 | 0.1624 | 0 | 0 | 0 |  | NA |  | 30000 |
| arm_A_severe_from_start | fcae | 30.00 | B | 838.1 | 754.4 | 936.3 | 0.8797 | 0.6807 | 0.1894 | 1.000 | 0 | 0 | 19784 | NA |  | 30000 |
| arm_A_severe_from_start | fcae_eb | 30.00 | B | 594.0 | 546.0 | 636.4 | 0.8879 | 0.7417 | 0.1633 | 1.000 | 0 | 0.1333 | 9570 | NA | 29130 | 30000 |
| arm_A_severe_from_start | thompson | 30.00 | B | 33.92 | 13.02 | 76.66 | 0.9065 | 0.6094 | 0.1456 | 0 | 0 | 0 |  | NA |  | 30000 |
| arm_A_severe_from_start | thompson_gauss | 30.00 | B | 15.72 | 11.27 | 21.27 | 0.9071 | 0.6026 | 0.1454 | 0 | 0 | 0 |  | NA |  | 30000 |
| arm_A_severe_from_start | ucb1 | 30.00 | B | 294.6 | 273.1 | 319.7 | 0.8978 | 0.6709 | 0.1544 | 0 | 0 | 0 |  | NA |  | 30000 |
| arm_A_severe_from_start | random | 30.00 | B | 1088 | 1042 | 1129 | 0.8714 | 0.6158 | 0.2156 | 0 | 0 | 0 |  | NA |  | 30000 |
| arm_A_severe_from_start | static_best | 30.00 | B | 2516 | 2459 | 2568 | 0.8238 | 0.2500 | 0.3654 | 0 | 0 | 0 |  | NA |  | 30000 |
