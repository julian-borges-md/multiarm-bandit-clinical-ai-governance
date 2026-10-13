# Table 26: drift_scenario_description

| drift_scenario | arm | logit_noise_sd | decisions_affected | auroc_before | auroc_after | brier_before | brier_after | sensitivity_before | sensitivity_after | best_arm_after | gap_drifted_arm_after | sd_reward_drifted_arm | n_per_arm_hoeffding | n_per_arm_bernstein | decisions_round_robin_bernstein | outcomes_available_per_arm |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| arm_A_moderate_from_start | A | 1.500 | 7383 | 0.8550 | 0.7522 | 0.08781 | 0.1148 | 0.8381 | 0.7505 | B | 0.005649 | 0.1882 | 2172490 | 271060 | 813180 | 2461 |
| arm_A_moderate_from_third | A | 1.500 | 4923 | 0.8578 | 0.7621 | 0.08589 | 0.1129 | 0.8398 | 0.7658 | B | 0.003396 | 0.1848 | 6385390 | 735132 | 2205400 | 1641 |
| arm_A_severe_from_start | A | 4.000 | 7383 | 0.8550 | 0.6255 | 0.08781 | 0.2328 | 0.8381 | 0.6263 | B | 0.08457 | 0.2611 | 6437 | 3060 | 9180 | 2461 |
| arm_A_severe_from_third | A | 4.000 | 4923 | 0.8578 | 0.6381 | 0.08589 | 0.2285 | 0.8398 | 0.6502 | B | 0.08042 | 0.2565 | 7187 | 3292 | 9876 | 1641 |
