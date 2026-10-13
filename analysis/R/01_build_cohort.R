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
#   results/stream_meta.json           arrival rate and split sizes

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
  save_data(feats[, .(subject_id, hadm_id, stay_id, split, age, sex, anchor_year_group, mort_hosp, icu_los_hours)],
            "cohort_index_selected")
  save_data(feats, "features")
  flow <- data.table(step = c("Synthetic stays generated", "Development", "Deployment stream"),
                     n_remaining = c(nrow(feats), sum(feats$split != "stream"), sum(feats$split == "stream")),
                     n_excluded = 0L)
  save_table(flow, 1, "cohort_flow")
  write_json_result(list(mode = "synthetic", arrival_rate_per_hour = 0.65,
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
                    select = c("subject_id", "hadm_id", "admittime", "dischtime", "deathtime", "hospital_expire_flag"), showProgress = FALSE)
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

# -----------------------------------------------------------------------------
# 3) ICU stays joined to admissions
# -----------------------------------------------------------------------------
cohort0 <- merge(icustays,
                 adm[, .(subject_id, hadm_id, admittime, dischtime, deathtime, hospital_expire_flag, age_at_admit, sex, anchor_year_group)],
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
                                age = as.integer(round(age_at_admit)), sex, anchor_year_group, mort_hosp,
                                icu_los_hours, hosp_los_days)]
save_data(cohort_index_full, "cohort_index_full")

# -----------------------------------------------------------------------------
# 5) Development and deployment split (subject level, temporal by anchor year group)
# -----------------------------------------------------------------------------
dev_groups <- params$cohort$development_year_groups
dep_groups <- params$cohort$deployment_year_groups
dev_pool <- cohort_index_full[anchor_year_group %chin% dev_groups]
dep_pool <- cohort_index_full[anchor_year_group %chin% dep_groups]
msg("Development pool: %d stays (%d subjects); deployment pool: %d stays (%d subjects)",
    nrow(dev_pool), uniqueN(dev_pool$subject_id), nrow(dep_pool), uniqueN(dep_pool$subject_id))

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

dep_pool <- dep_pool[sample.int(.N)]
dep_one <- dep_pool[, .SD[1], by = subject_id]
stream_n <- min(params$cohort$stream_n, nrow(dep_one))
stream_sel <- dep_one[sample.int(.N, stream_n)]
stream_sel[, split := "stream"]

selected <- rbind(dev_sel, stream_sel)
stopifnot(length(intersect(selected[split != "stream", subject_id], selected[split == "stream", subject_id])) == 0)
stopifnot(!anyDuplicated(selected$stay_id))
save_data(selected, "cohort_index_selected")

flow <- rbind(flow, data.table(step = c("Development set sampled (train plus validation)", "Deployment stream sampled"),
                               n_remaining = c(nrow(dev_sel), nrow(stream_sel)), n_excluded = NA_integer_))
save_table(flow, 1, "cohort_flow")

# -----------------------------------------------------------------------------
# 6) Characteristics by split and arrival rate
# -----------------------------------------------------------------------------
chars <- selected[, .(n = .N, subjects = uniqueN(subject_id), mortality = mean(mort_hosp),
                      age_mean = mean(age), age_sd = sd(age), female = mean(sex == "F"),
                      icu_los_median_h = median(icu_los_hours), icu_los_iqr_h = IQR(icu_los_hours),
                      hosp_los_median_d = median(hosp_los_days), hosp_los_iqr_d = IQR(hosp_los_days)),
                  by = split][order(factor(split, levels = c("train", "val", "stream")))]
save_table(chars, 2, "cohort_characteristics")

span_hours <- 15 * 365.25 * 24                      # MIMIC-IV covers admissions from 2008 to 2022
arrival_rate <- if (!is.null(params$delay$arrival_rate_per_hour)) params$delay$arrival_rate_per_hour else nrow(cohort_index_full) / span_hours
write_json_result(list(mode = "mimic", arrival_rate_per_hour = arrival_rate, n_eligible = nrow(cohort_index_full),
                       n_train = sum(selected$split == "train"), n_val = sum(selected$split == "val"),
                       n_stream = sum(selected$split == "stream"),
                       development_year_groups = dev_groups, deployment_year_groups = dep_groups), "stream_meta")

p1 <- ggplot(flow[!is.na(n_excluded)], aes(x = factor(step, levels = rev(step)), y = n_remaining)) +
  geom_col(fill = "grey35") + coord_flip() + scale_y_continuous(labels = comma) +
  labs(x = NULL, y = "ICU stays remaining") + theme_minimal(base_size = 11)
save_fig(p1, 1, "CohortFlow", width = 8, height = 4)

msg("01_build_cohort.R done")
}
