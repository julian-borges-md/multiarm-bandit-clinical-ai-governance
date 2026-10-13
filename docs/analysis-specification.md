# Analysis specification (version 3.0.0)

This document is the binding specification of the analysis implemented in `analysis/R`. Every parameter named here is read from `config/params.yml`; the manuscript Methods section is derived from this document.

## 1. Data

MIMIC-IV v3.1 (PhysioNet, https://doi.org/10.13026/kpb9-mt58). Tables used: `hosp.patients`, `hosp.admissions`, `icu.icustays` (cohort), `icu.chartevents` with `icu.d_items` (vital signs), `hosp.labevents` with `hosp.d_labitems` (laboratory tests). No other table is read.

## 2. Cohort

| Rule | Value |
|---|---|
| Unit | Index ICU stay per hospital admission (first stay by ICU admission time) |
| Age | 18 years or older at hospital admission (anchor age plus admission year minus anchor year) |
| Timestamps | Complete admission, discharge, ICU in and out times; ICU out after in; discharge not before admission; sex recorded |
| ICU length of stay | 24 hours to 60 days, so the 24 hour feature window is fully observed and no outcome occurs inside it |
| Outcome | In hospital mortality (`hospital_expire_flag`, or a recorded death time within the admission) |
| Development pool | Subjects with anchor year group 2008 to 2010, 2011 to 2013, 2014 to 2016 or 2017 to 2019; only stays whose real calendar window (anchor year group shifted by the years between the anchor year and the admission) ends before 2020, so that every development stay precedes every deployment stay |
| Deployment pool | Subjects with anchor year group 2020 to 2022 (every stay in or after 2020; disjoint subjects); drawn with its own seed |
| Development set | One random index stay per subject; 20,000 stays sampled; 25 percent of subjects to validation |
| Validation halves | Half of validation subjects for early stopping, the other half for calibration, thresholds and the choice of the static arm |
| Deployment stream | One random index stay per subject from the deployment pool, up to 10,000 stays (all 7,383 available in v3.1) |

Cross patient chronological ordering is not recoverable in MIMIC-IV because dates are shifted per patient; the stream is therefore ordered by a seeded random permutation in each replicate.

## 3. Features

First 24 hours after ICU admission. Vital signs (itemids verified against `d_items`): heart rate 220045; respiratory rate 220210; temperature 223761 (Fahrenheit, converted) and 223762; SpO2 220277; systolic 220179 and 220050; diastolic 220180 and 220051; mean arterial pressure 220181 and 220052; Glasgow Coma Scale total from components 220739, 223900 and 223901 recorded at the same time. Laboratory tests (itemids verified against `d_labitems`): white blood cells 51301; hemoglobin 51222; platelets 51265; sodium 50983; potassium 50971; chloride 50902; bicarbonate 50882; urea nitrogen 51006; creatinine 50912; glucose 50931; lactate 50813; total bilirubin 50885; INR 51237. Values outside physiologic ranges listed in `02_extract_features.R` are dropped. Each concept yields mean, minimum, maximum and last value. Missing laboratory concepts carry an indicator; numeric gaps are filled with training medians.

## 4. Arms

| Arm | Learner | Inputs | Cost c_a |
|---|---|---|---|
| A | Ridge logistic regression (glmnet, alpha 0, lambda by 10 fold cross validation) | Age, sex, vital signs | 0.25 |
| B | Gradient boosted trees (xgboost, depth 4, eta 0.05, early stopping on the validation half) | A plus core laboratory panel (10 tests) and their missing indicators | 0.60 |
| C | Random forest (ranger, 500 trees; candidate variables per split and minimum node size selected by log loss on the early stopping half from a grid of nine settings) | B plus lactate, bilirubin and INR and their indicators | 1.00 |

Each arm is calibrated by Platt scaling on the calibration half and frozen. Operating thresholds tau_a give 80 percent sensitivity on the calibration half. The static deployment comparator is the arm with the highest mean composite reward on the calibration half.

## 5. Reward

For patient t, arm a, calibrated probability p, label y:

r_raw = (1 minus (p minus y)^2) minus lambda_c c_a minus lambda_s s_a minus lambda_f f_a, with s_a = 1 if y = 1 and p < tau_a, else 0, and f_a = 1 if y = 0 and p at or above tau_a, else 0.

r = (r_raw + lambda_c + lambda_s + lambda_f) / (1 + lambda_c + lambda_s + lambda_f), which lies in [0, 1] for every arm because c_a is at most 1. Primary weights lambda_c = 0.10, lambda_s = 0.50 and lambda_f = 0. The cost c_a is an arm constant (0.25, 0.60, 1.00) in the primary analysis and a per decision value under acquisition conditional costing (arm C charged at arm B's cost when the extended panel is absent from the record).

## 6. Delayed feedback

Arrivals follow a Poisson process with rate equal to the eligible cohort size divided by the hours in 2008 to 2022 (database rate). The stream own rate (stream size over the three year anchor window) and the guaranteed recent rate (eligible stays whose real window lies at or after 2020, over three years) are recorded in stream_meta.json; calendar horizons are reported at the database rate and at the stream own rate. The delay of each outcome is uniform on 6 to 72 hours. A policy may use the outcome of decision s when deciding t only if arrival_s + delay_s is at or before arrival_t. The simulator counts violations; the pipeline stops if any occur.

## 7. Policies

| Key | Policy |
|---|---|
| fcae | Fixed confidence action elimination, Hoeffding radius sqrt(log(4 K n^2 / delta) / (2 n)), round robin over active arms |
| fcae_eb | Same with the empirical Bernstein radius sqrt(2 V_n L / n) + 7 L / (3 (n minus 1)), L = log(16 K n^2 / delta) |
| fcae_strat | Empirical Bernstein elimination run separately in four strata (all three extended laboratory tests observed by age 65), confidence delta / 4 per stratum |
| thompson | Beta Bernoulli Thompson sampling with Bernoulli sampled rewards |
| thompson_gauss | Thompson sampling with a Gaussian posterior on each arm mean (running mean and sample variance); arms without feedback first |
| ucb1 | UCB1 index mean + sqrt(2 log n_feedback / n_a) |
| random | Uniform random arm |
| static_best, static_A, static_B, static_C | Fixed arm |
| ensemble | Equal weight average of the three probabilities, cost 1.00, own threshold |
| heuristic | Arm A first; escalation to arm C when p_A is at or above tau_A; cost additive |

Elimination rule: arm i leaves the active set when UCB_i < max over other active j of LCB_j. The radii are valid simultaneously for all n and all K arms, so the probability that the best arm is ever eliminated is at most delta (0.05).

## 8. Replication and inference

100 seeded replicates (order, arrivals, delays, policy randomness). Primary metric: cumulative regret against the best fixed arm in hindsight on the stream. Secondary: regret against the per decision oracle, mean reward, deployed prediction AUROC and Brier score, false negative rate at the operating thresholds, mean cost, exploration share by decile, elimination times, sensitivity gaps by age group and sex. Paired differences across replicates against static deployment with 2,000 resample percentile bootstrap intervals. Sensitivity: lambda_c in {0, 0.10, 0.20} by lambda_s in {0, 0.50, 1.00}; delta in {0.01, 0.05, 0.10}; delay none, 6 to 72 h, 24 to 168 h; 30 replicates each. Implied sample complexity: exact smallest n per arm (bisection) at which the observed gap exceeds the sum of the two radii, the outcomes per arm available under round robin (floor(T / K)), the shortfall factor and the confidence level at which the available sample would suffice; patient level percentile bootstrap (1,000 resamples of the stream with replacement) of the arm means, gaps and implied sample sizes. Subgroup metrics: signed sensitivity gaps (under 65 minus 65 and over; female minus male), share weighted experienced disparity, sensitivity range across race groups with at least 30 deaths; per arm subgroup sensitivities with Wilson intervals. Further sensitivity analyses (30 replicates each): false positive weight in {0.10, 0.20, 0.40} with the break even weight; cost vectors compressed (0.45, 0.60, 0.75), expanded (0.10, 0.55, 1.00) and equal (0.60); acquisition conditional costing; drift scenarios (Gaussian noise on the logit of arm A, standard deviation 1.5 for a moderate loss of discrimination and 4.0 for a broken model, from the start or from one third of the stream) under no, primary and long delay; development window restricted to the 2017 to 2019 anchor group (separate run, PARAMS_FILE=config/params_recent_window.yml). Utility functional sensitivity: the primary analysis at the primary weights repeated with binary correctness at the operating threshold in place of one minus the Brier loss (30 replicates, same seeds as the primary replicates), with the implied sample complexity recomputed under that utility. Extended horizon: 30,000 decisions resampled with replacement, 30 replicates.
