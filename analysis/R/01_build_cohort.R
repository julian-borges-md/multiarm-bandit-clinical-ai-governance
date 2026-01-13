# analysis/R/01_build_cohort.R
# cohort build using MIMIC-IV v3.1 hosp + icu tables
# Produces cohort index files, cohort flow table, cohort summary table, and 2 figures
# All outputs are saved under cfg$output_dir (absolute path enforced in 00_setup.R)

msg("01_build_cohort.R starting (real MIMIC-IV v3.1)")

set.seed(cfg$seed)

# -----------------------------
# 1) Paths
# -----------------------------
mimic_dir <- normalizePath(
  "/Users/FxMED/Documents/rSTUDIO/machine learning/Users/FxMED/Downloads/multiarm-bandit-clinical-ai-governance/data/mimic-iv-3.1",
  mustWork = TRUE
)

hosp_dir <- file.path(mimic_dir, "hosp")
icu_dir  <- file.path(mimic_dir, "icu")

patients_path   <- file.path(hosp_dir, "patients.csv.gz")
admissions_path <- file.path(hosp_dir, "admissions.csv.gz")
icustays_path   <- file.path(icu_dir,  "icustays.csv.gz")

if (!file.exists(patients_path)) stop(paste("Missing:", patients_path))
if (!file.exists(admissions_path)) stop(paste("Missing:", admissions_path))
if (!file.exists(icustays_path)) stop(paste("Missing:", icustays_path))

msg(paste0("MIMIC-IV root: ", mimic_dir))
msg(paste0("Outputs root: ", cfg$output_dir))

# -----------------------------
# 2) Read core tables (minimal columns only)
# -----------------------------
msg("Reading patients, admissions, icustays")

patients <- data.table::fread(
  patients_path,
  select = c("subject_id", "gender", "anchor_age", "anchor_year", "anchor_year_group", "dod"),
  showProgress = FALSE
)

admissions <- data.table::fread(
  admissions_path,
  select = c("subject_id", "hadm_id", "admittime", "dischtime", "deathtime", "hospital_expire_flag"),
  showProgress = FALSE
)

icustays <- data.table::fread(
  icustays_path,
  select = c("subject_id", "hadm_id", "stay_id", "intime", "outtime"),
  showProgress = FALSE
)

# -----------------------------
# 3) Standardize time columns
# -----------------------------
msg("Parsing timestamps")

time_cols_adm <- c("admittime", "dischtime", "deathtime")
for (cc in time_cols_adm) admissions[, (cc) := as.POSIXct(get(cc), tz = "UTC")]

time_cols_icu <- c("intime", "outtime")
for (cc in time_cols_icu) icustays[, (cc) := as.POSIXct(get(cc), tz = "UTC")]

patients[, dod := as.POSIXct(dod, tz = "UTC")]

# -----------------------------
# 4) Derive age at admission (MIMIC anchor age logic)
# -----------------------------
msg("Deriving age at admission from anchor fields")

get_anchor_year_from_group <- function(x) {
  # expected format: "2011 - 2013"
  out <- suppressWarnings(as.integer(substr(x, 1, 4)))
  out
}

patients[, anchor_year_from_group := get_anchor_year_from_group(anchor_year_group)]
patients[, anchor_year_final := data.table::fifelse(!is.na(anchor_year), anchor_year, anchor_year_from_group)]

adm <- merge(
  admissions,
  patients[, .(subject_id, gender, anchor_age, anchor_year_final)],
  by = "subject_id",
  all.x = TRUE
)

adm[, admit_year := as.integer(format(admittime, "%Y"))]
adm[, age_at_admit := anchor_age + (admit_year - anchor_year_final)]

# Sex label consistent with manuscript
adm[, sex := data.table::fifelse(gender %chin% c("M", "F"), gender, NA_character_)]

# -----------------------------
# 5) Join ICU stays to admissions
# -----------------------------
msg("Joining ICU stays with admissions")

cohort0 <- merge(
  icustays,
  adm[, .(subject_id, hadm_id, admittime, dischtime, deathtime, hospital_expire_flag, age_at_admit, sex)],
  by = c("subject_id", "hadm_id"),
  all.x = TRUE
)

# Derived lengths
cohort0[, icu_los_hours := as.numeric(difftime(outtime, intime, units = "hours"))]
cohort0[, hosp_los_days := as.numeric(difftime(dischtime, admittime, units = "days"))]

# Hospital mortality
# Primary: hospital_expire_flag; secondary: deathtime if provided
cohort0[, mort_hosp := as.integer(hospital_expire_flag == 1L)]
cohort0[, deathtime_final := deathtime]
cohort0[mort_hosp == 0L & !is.na(deathtime_final), mort_hosp := 1L]

# -----------------------------
# 6) Cohort flow tracking
# -----------------------------
flow <- data.table(step = character(), n_remaining = integer(), n_excluded = integer())

add_flow <- function(step_label, before_n, after_n) {
  flow <<- rbind(flow, data.table(step = step_label, n_remaining = after_n, n_excluded = before_n - after_n))
}

flow <- rbind(
  flow,
  data.table(step = "Start ICU stays (joined)", n_remaining = nrow(cohort0), n_excluded = 0L)
)

# -----------------------------
# 7) Inclusion and exclusion criteria (aligned with manuscript)
# -----------------------------
msg("Applying inclusion and exclusion criteria")

# A) Non missing timestamps
before <- nrow(cohort0)
cohort <- cohort0[!is.na(admittime) & !is.na(dischtime) & !is.na(intime) & !is.na(outtime)]
add_flow("Non missing admission and ICU times", before, nrow(cohort))

# B) Valid ordering
before <- nrow(cohort)
cohort <- cohort[outtime > intime & dischtime >= admittime]
add_flow("Valid time ordering", before, nrow(cohort))

# C) Adult only (>= 18)
before <- nrow(cohort)
cohort <- cohort[!is.na(age_at_admit) & age_at_admit >= 18]
add_flow("Adult only (age >= 18)", before, nrow(cohort))

# D) Plausible ICU LOS: 1 hour to 60 days
before <- nrow(cohort)
cohort <- cohort[icu_los_hours >= 1 & icu_los_hours <= (60 * 24)]
add_flow("ICU LOS within 1 hour and 60 days", before, nrow(cohort))

# E) Index ICU stay per hospital admission (first ICU stay per hadm_id)
data.table::setorder(cohort, subject_id, hadm_id, intime, stay_id)
before <- nrow(cohort)
cohort <- cohort[, .SD[1], by = .(subject_id, hadm_id)]
add_flow("Index ICU stay per admission", before, nrow(cohort))

# Deterministic sequential ordering for simulated deployment stream
data.table::setorder(cohort, intime, stay_id)

# -----------------------------
# 8) Build cohort index full
# -----------------------------
msg("Building cohort_index_full")

cohort_index_full <- cohort[, .(
  subject_id, hadm_id, stay_id,
  admittime, dischtime, intime, outtime,
  age = as.integer(round(age_at_admit)),
  sex,
  mort_hosp,
  deathtime = deathtime_final,
  icu_los_hours,
  hosp_los_days
)]

save_data(cohort_index_full, "cohort_index_full")

# -----------------------------
# 9) Evaluation cohort sampling (stratified by hospital mortality)
# -----------------------------
msg("Sampling evaluation cohort (stratified by mortality)")

eval_n <- min(cfg$eval_n, nrow(cohort_index_full))

cohort_index_full[, mort_str := factor(mort_hosp)]
eval_ids <- cohort_index_full[
  ,
  .SD[sample.int(.N, size = ceiling(eval_n * .N / nrow(cohort_index_full)), replace = FALSE)],
  by = mort_str
]

eval_ids <- eval_ids[1:eval_n][, mort_str := NULL]
data.table::setorder(eval_ids, intime, stay_id)

save_data(eval_ids, "cohort_index_eval")

# -----------------------------
# 10) Tables for manuscript
# -----------------------------
msg("Saving manuscript tables (flow and cohort summary)")

save_table(flow, 1, "cohort_flow")

desc <- cohort_index_full[, .(
  n = .N,
  mort_rate = mean(mort_hosp, na.rm = TRUE),
  age_mean = mean(age, na.rm = TRUE),
  age_sd = sd(age, na.rm = TRUE),
  icu_los_med_h = median(icu_los_hours, na.rm = TRUE),
  icu_los_iqr_h = IQR(icu_los_hours, na.rm = TRUE),
  hosp_los_med_d = median(hosp_los_days, na.rm = TRUE),
  hosp_los_iqr_d = IQR(hosp_los_days, na.rm = TRUE)
)]

save_table(desc, 2, "cohort_summary")

# -----------------------------
# 11) Figures for manuscript
# -----------------------------
msg("Saving manuscript figures (flow and age distribution)")

p1 <- ggplot(flow, aes(x = reorder(step, n_remaining), y = n_remaining)) +
  geom_col() +
  coord_flip() +
  scale_y_continuous(labels = scales::comma) +
  labs(title = "Cohort flow", x = NULL, y = "Remaining ICU stays")

save_fig(p1, 1, "CohortFlow")

p2 <- ggplot(cohort_index_full, aes(x = age)) +
  geom_histogram(bins = 40) +
  labs(title = "Age distribution", x = "Age at admission", y = "Count")

save_fig(p2, 2, "AgeDistribution")

msg("01_build_cohort.R done (real MIMIC-IV v3.1)")

