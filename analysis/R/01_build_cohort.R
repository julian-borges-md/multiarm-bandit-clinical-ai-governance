# analysis/R/01_build_cohort.R
# Cohort construction from MIMIC-IV v3.1 (hosp.patients, hosp.admissions, icu.icustays)
# and assignment of the development (training, validation) and deployment stream sets.
#
# Outputs (outputs/):
#   data/cohort_index_full.csv.gz      every eligible index ICU stay (patient level, not committed)
#   data/cohort_index_selected.csv.gz  stays used downstream with their split label
#   tables/Table01_cohort_flow.csv     inclusion and exclusion counts
#   tables/Table02_cohort_characteristics.csv  by split
#   figures/Figure01_CohortFlow.*
#   results/stream_meta.json           arrival rates and split sizes
#   results/stay_offset_distribution.csv  years between the anchor year and each selected stay, by split
#
# Temporal ordering. anchor_year_group is a patient attribute (the real window of the patient's
# anchor year); a stay admitted k years after the anchor year occurred in that window shifted by k.
# The development pool therefore keeps only stays whose shifted window ends before the deployment
# start year, so that every development stay precedes every deployment stay in calendar time
# (cohort.development_stay_rule = "guaranteed_before_deployment").

if (!exists("cfg", inherits = TRUE)) source(file.path("analysis", "R", "00_setup.R"))
suppressPackageStartupMessages({ library(data.table); library(ggplot2); library(scales) })
source(file.path(cfg$repo_root, "analysis", "R", "lib", "synthetic.R"))

msg("01_build_cohort.R starting (mode=%s)", cfg$data_mode)

# -----------------------------------------------------------------------------
# Synthetic mode: write features directly and stop
# -----------------------------------------------------------------------------
if (identical(cfg$data_mode, "synthetic")) {
  feats <- synthetic_features(params$synthetic$n_development, params$synthetic$n_stream,
                              seed = params$reproducibility$seed_synthetic,
                              validation_fraction = params$cohort$validation_fraction)
  save_data(feats[, .(subject_id, hadm_id, stay_id, split, age, sex, race_group, anchor_year_group, anchor_offset, mort_hosp, icu_los_hours)],
            "cohort_index_selected")
  save_data(feats, "features")
  flow <- data.table(step = c("Synthetic stays generated", "Development", "Deployment stream"),
                     n_remaining = c(nrow(feats), sum(feats$split != "stream"), sum(feats$split == "stream")),
                     n_excluded = 0L)
  save_table(flow, 1, "cohort_flow")
  write_json_result(list(mode = "synthetic", arrival_rate_per_hour = 0.65, arrival_rate_database = 0.65, arrival_rate_stream_own = 0.65,
                         arrival_rate_recent_guaranteed = 0.65, development_stay_rule = "synthetic",
                         n_train = sum(feats$split == "train"), n_val = sum(feats$split == "val"),
                         n_stream = sum(feats$split == "stream")), "stream_meta")
  msg("01_build_cohort.R done (synthetic)")
} else {

cfg_validate_mimic(mustWork = TRUE)
set.seed(params$reproducibility$seed_split)

# -----------------------------------------------------------------------------
# 1) Core tables
# -----------------------------------------------------------------------------
msg("Reading patients, admissions, icustays")
patients <- fread(mimic_file("hosp", "patients.csv.gz"),
                  select = c("subject_id", "gender", "anchor_age", "anchor_year", "anchor_year_group", "dod"), showProgress = FALSE)
admissions <- fread(mimic_file("hosp", "admissions.csv.gz"),
                    select = c("subject_id", "hadm_id", "admittime", "dischtime", "deathtime", "hospital_expire_flag", "race"), showProgress = FALSE)
icustays <- fread(mimic_file("icu", "icustays.csv.gz"),
                  select = c("subject_id", "hadm_id", "stay_id", "intime", "outtime"), showProgress = FALSE)

for (cc in c("admittime", "dischtime", "deathtime")) admissions[, (cc) := as.POSIXct(get(cc), tz = "UTC")]
for (cc in c("intime", "outtime")) icustays[, (cc) := as.POSIXct(get(cc), tz = "UTC")]

# -----------------------------------------------------------------------------
# 2) Age at admission (anchor logic) and sex
# -----------------------------------------------------------------------------
adm <- merge(admissions, patients[, .(subject_id, gender, anchor_age, anchor_year, anchor_year_group)], by = "subject_id", all.x = TRUE)
adm[, admit_year := as.integer(format(admittime, "%Y"))]
adm[, age_at_admit := anchor_age + (admit_year - anchor_year)]
adm[, sex := fifelse(gender %chin% c("M", "F"), gender, NA_character_)]
# years between the anchor year and the admission, and the real calendar window of the admission
adm[, anchor_offset := admit_year - anchor_year]
adm[, real_year_lo := as.integer(substr(anchor_year_group, 1, 4)) + anchor_offset]
adm[, real_year_hi := real_year_lo + 2L]
# race as recorded on the admission, grouped into five categories (the field is self reported or
# administratively assigned and is used descriptively only)
race_group <- function(x) {
  x <- toupper(trimws(x))
  fcase(startsWith(x, "WHITE"), "White",
        startsWith(x, "BLACK"), "Black",
        startsWith(x, "HISPANIC") | startsWith(x, "SOUTH AMERICAN") | startsWith(x, "PORTUGUESE"), "Hispanic or Latino",
        startsWith(x, "ASIAN"), "Asian",
        default = "Other or unknown")
}
adm[, race_group := race_group(race)]

# -----------------------------------------------------------------------------
# 3) ICU stays joined to admissions
# -----------------------------------------------------------------------------
cohort0 <- merge(icustays,
                 adm[, .(subject_id, hadm_id, admittime, dischtime, deathtime, hospital_expire_flag, age_at_admit, sex, anchor_year_group,
                         anchor_offset, real_year_lo, real_year_hi, race_group)],
                 by = c("subject_id", "hadm_id"), all.x = TRUE)
cohort0[, icu_los_hours := as.numeric(difftime(outtime, intime, units = "hours"))]
cohort0[, hosp_los_days := as.numeric(difftime(dischtime, admittime, units = "days"))]
cohort0[, mort_hosp := as.integer(hospital_expire_flag == 1L)]
cohort0[mort_hosp == 0L & !is.na(deathtime), mort_hosp := 1L]

# -----------------------------------------------------------------------------
# 4) Inclusion and exclusion (flow tracked)
# -----------------------------------------------------------------------------
flow <- data.table(step = "ICU stays joined to admissions", n_remaining = nrow(cohort0), n_excluded = 0L)
add_flow <- function(label, before, after) flow <<- rbind(flow, data.table(step = label, n_remaining = after, n_excluded = before - after))

b <- nrow(cohort0); cohort <- cohort0[!is.na(admittime) & !is.na(dischtime) & !is.na(intime) & !is.na(outtime) & !is.na(sex)]
add_flow("Complete timestamps and sex", b, nrow(cohort))

b <- nrow(cohort); cohort <- cohort[outtime > intime & dischtime >= admittime]
add_flow("Valid time ordering", b, nrow(cohort))

b <- nrow(cohort); cohort <- cohort[!is.na(age_at_admit) & age_at_admit >= params$cohort$age_min]
add_flow(sprintf("Age %d or older", params$cohort$age_min), b, nrow(cohort))

b <- nrow(cohort)
cohort <- cohort[icu_los_hours >= params$cohort$icu_los_min_hours & icu_los_hours <= params$cohort$icu_los_max_days * 24]
add_flow(sprintf("ICU length of stay %d h to %d d (feature window fully observed)", params$cohort$icu_los_min_hours, params$cohort$icu_los_max_days), b, nrow(cohort))

setorder(cohort, subject_id, hadm_id, intime, stay_id)
b <- nrow(cohort); cohort <- cohort[, .SD[1], by = .(subject_id, hadm_id)]
add_flow("Index ICU stay per hospital admission", b, nrow(cohort))

b <- nrow(cohort); cohort <- cohort[!is.na(anchor_year_group)]
add_flow("Anchor year group available", b, nrow(cohort))

cohort_index_full <- cohort[, .(subject_id, hadm_id, stay_id, admittime, dischtime, intime, outtime,
                                age = as.integer(round(age_at_admit)), sex, race_group, anchor_year_group,
                                anchor_offset, real_year_lo, real_year_hi, mort_hosp, icu_los_hours, hosp_los_days)]
save_data(cohort_index_full, "cohort_index_full")

# -----------------------------------------------------------------------------
# 5) Development and deployment split (subject level, temporal by anchor year group)
# -----------------------------------------------------------------------------
dev_groups <- params$cohort$development_year_groups
dep_groups <- params$cohort$deployment_year_groups
dev_pool_all <- cohort_index_full[anchor_year_group %chin% dev_groups]
dep_pool <- cohort_index_full[anchor_year_group %chin% dep_groups]
dep_start <- as.integer(params$cohort$deployment_start_year)
stay_rule <- if (is.null(params$cohort$development_stay_rule)) "any" else params$cohort$development_stay_rule
dev_pool <- if (identical(stay_rule, "guaranteed_before_deployment")) dev_pool_all[real_year_hi < dep_start] else dev_pool_all
stopifnot(all(dep_pool$real_year_lo >= dep_start))
msg("Development pool: %d of %d stays retained under rule '%s' (%d subjects); deployment pool: %d stays (%d subjects)",
    nrow(dev_pool), nrow(dev_pool_all), stay_rule, uniqueN(dev_pool$subject_id), nrow(dep_pool), uniqueN(dep_pool$subject_id))

# Subjects present in both pools (anchor_year_group is subject level, so this should be empty)
overlap <- intersect(dev_pool$subject_id, dep_pool$subject_id)
if (length(overlap) > 0) stop_log("Subject overlap between pools: %d", length(overlap))

# Sample development stays (one random stay is enough per subject to limit within subject correlation)
dev_pool <- dev_pool[sample.int(.N)]
dev_one <- dev_pool[, .SD[1], by = subject_id]
dev_n <- min(params$cohort$development_n, nrow(dev_one))
dev_sel <- dev_one[sample.int(.N, dev_n)]
val_subjects <- sample(dev_sel$subject_id, size = round(params$cohort$validation_fraction * dev_n))
dev_sel[, split := fifelse(subject_id %in% val_subjects, "val", "train")]

# the deployment stream is drawn with its own seed so that it does not depend on the size of the
# development pool or on the development sampling
set.seed(params$reproducibility$seed_split + 1L)
dep_pool <- dep_pool[sample.int(.N)]
dep_one <- dep_pool[, .SD[1], by = subject_id]
stream_n <- min(params$cohort$stream_n, nrow(dep_one))
stream_sel <- dep_one[sample.int(.N, stream_n)]
stream_sel[, split := "stream"]

selected <- rbind(dev_sel, stream_sel)
stopifnot(length(intersect(selected[split != "stream", subject_id], selected[split == "stream", subject_id])) == 0)
stopifnot(!anyDuplicated(selected$stay_id))
if (identical(stay_rule, "guaranteed_before_deployment")) stopifnot(max(selected[split != "stream", real_year_hi]) < min(selected[split == "stream", real_year_lo]))
save_data(selected, "cohort_index_selected")
offsets <- selected[, .N, by = .(split, anchor_offset)][order(split, anchor_offset)]
save_result(offsets, "stay_offset_distribution")

flow <- rbind(flow, data.table(step = c("Development pool (patients anchored 2008 to 2019)",
                                        sprintf("Development pool: stays whose real calendar window ends before %d", dep_start),
                                        "Development set sampled (train plus validation)",
                                        sprintf("Deployment pool (patients anchored %d to %d)", dep_start, dep_start + 2L),
                                        "Deployment stream sampled"),
                               n_remaining = c(nrow(dev_pool_all), nrow(dev_pool), nrow(dev_sel), nrow(dep_pool), nrow(stream_sel)),
                               n_excluded = c(NA_integer_, nrow(dev_pool_all) - nrow(dev_pool), NA_integer_, NA_integer_, NA_integer_)))
save_table(flow, 1, "cohort_flow")

# -----------------------------------------------------------------------------
# 6) Characteristics by split and arrival rate
# -----------------------------------------------------------------------------
chars <- selected[, .(n = .N, subjects = uniqueN(subject_id), mortality = mean(mort_hosp),
                      age_mean = mean(age), age_sd = sd(age), female = mean(sex == "F"),
                      icu_los_median_h = median(icu_los_hours), icu_los_iqr_h = IQR(icu_los_hours),
                      hosp_los_median_d = median(hosp_los_days), hosp_los_iqr_d = IQR(hosp_los_days),
                      race_white = mean(race_group == "White"), race_black = mean(race_group == "Black"),
                      race_hispanic = mean(race_group == "Hispanic or Latino"), race_asian = mean(race_group == "Asian"),
                      race_other_unknown = mean(race_group == "Other or unknown"),
                      stays_within_anchor_year = mean(anchor_offset == 0)),
                  by = split][order(factor(split, levels = c("train", "val", "stream")))]
save_table(chars, 2, "cohort_characteristics")

# Arrival rates. The database rate divides every eligible stay by the 15 year span of MIMIC-IV
# (2008 to 2022). The stream own rate divides the stream by the three year deployment window; it
# understates institutional accrual because stays of patients anchored before the deployment window
# who were admitted during it belong to earlier anchor groups by construction. The guaranteed recent
# rate counts every eligible stay whose real window lies entirely at or after the deployment start.
span_hours <- 15 * 365.25 * 24
rate_database <- nrow(cohort_index_full) / span_hours
rate_stream_own <- nrow(stream_sel) / (3 * 365.25 * 24)
n_recent <- cohort_index_full[real_year_lo >= dep_start, .N]
rate_recent_guaranteed <- n_recent / (3 * 365.25 * 24)
arrival_rate <- if (!is.null(params$delay$arrival_rate_per_hour)) params$delay$arrival_rate_per_hour else rate_database
write_json_result(list(mode = "mimic", arrival_rate_per_hour = arrival_rate, arrival_rate_database = rate_database,
                       arrival_rate_stream_own = rate_stream_own, arrival_rate_recent_guaranteed = rate_recent_guaranteed,
                       n_eligible_recent_guaranteed = n_recent, n_eligible = nrow(cohort_index_full),
                       n_development_pool_all = nrow(dev_pool_all), n_development_pool_retained = nrow(dev_pool),
                       development_stay_rule = stay_rule, deployment_start_year = dep_start,
                       n_train = sum(selected$split == "train"), n_val = sum(selected$split == "val"),
                       n_stream = sum(selected$split == "stream"),
                       development_year_groups = dev_groups, deployment_year_groups = dep_groups), "stream_meta")

flow_fig <- copy(flow)[, stage := fifelse(grepl("pool|sampled", step), "Analysis sets", "Eligibility")]
p1 <- ggplot(flow_fig, aes(x = factor(step, levels = rev(step)), y = n_remaining, fill = stage)) +
  geom_col() + coord_flip() + scale_y_continuous(labels = comma) +
  scale_fill_manual(values = c("Eligibility" = "grey35", "Analysis sets" = "#1b4f72")) +
  labs(x = NULL, y = "ICU stays", fill = NULL) + theme_minimal(base_size = 11) + theme(legend.position = "bottom")
save_fig(p1, 1, "CohortFlow", width = 8, height = 4)

msg("01_build_cohort.R done")
}
