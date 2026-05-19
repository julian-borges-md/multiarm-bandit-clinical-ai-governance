# analysis/R/02_extract_features.R
# Feature extraction for first 24 hours of index ICU stay
# Builds evaluation cohort features from:
#   icu/chartevents + icu/d_items for vitals
#   hosp/labevents  + hosp/d_labitems for labs
# Writes outputs under cfg$output_dir (from analysis/R/00_setup.R)

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
  library(scales)
})

# -----------------------------
# 0) Load setup once
# -----------------------------
if (!exists("cfg", inherits = TRUE) || !is.list(cfg) || is.null(cfg$output_dir)) {
  source("analysis/R/00_setup.R")
}

msg("02_extract_features.R starting")
set.seed(cfg$seed)

# Validate MIMIC and derive dirs from root
cfg_validate_mimic(mustWork = TRUE)
mimic_dir <- cfg$mimic_dir
hosp_dir  <- file.path(mimic_dir, "hosp")
icu_dir   <- file.path(mimic_dir, "icu")

# Cohort outputs created by 01_build_cohort.R
cohort_eval_path <- file.path(cfg$out_data_dir, "cohort_index_eval.csv.gz")
cohort_full_path <- file.path(cfg$out_data_dir, "cohort_index_full.csv.gz")

# Raw MIMIC inputs
chartevents_gz <- file.path(icu_dir,  "chartevents.csv.gz")
d_items_gz     <- file.path(icu_dir,  "d_items.csv.gz")
labevents_gz   <- file.path(hosp_dir, "labevents.csv.gz")
d_labitems_gz  <- file.path(hosp_dir, "d_labitems.csv.gz")

stopifnot(file.exists(cohort_eval_path), file.exists(cohort_full_path))
stopifnot(file.exists(chartevents_gz), file.exists(d_items_gz))
stopifnot(file.exists(labevents_gz), file.exists(d_labitems_gz))

msg("MIMIC IV root: %s", mimic_dir)
msg("Outputs root: %s", cfg$output_dir)

# -----------------------------
# 1) Robust readers (name based column selection)
# -----------------------------
as_num <- function(x) suppressWarnings(as.numeric(x))

read_dt_cols <- function(path, cols, show_progress = FALSE) {
  stopifnot(length(path) == 1, nzchar(path))
  stopifnot(length(cols) >= 1)
  
  hdr  <- data.table::fread(path, nrows = 0, showProgress = FALSE)
  have <- names(hdr)
  miss <- setdiff(cols, have)
  if (length(miss) > 0) {
    stop(sprintf(
      "File %s missing required columns: %s\nAvailable: %s",
      basename(path),
      paste(miss, collapse = ", "),
      paste(have, collapse = ", ")
    ))
  }
  
  data.table::fread(path, select = cols, showProgress = isTRUE(show_progress))
}

read_gz_cols <- function(path_gz, cols, use_cache = TRUE, show_progress = FALSE) {
  path_gz <- sanitize_scalar_chr(path_gz, default = "")
  if (!nzchar(path_gz)) stop("read_gz_cols(): path_gz is empty.")
  if (!file.exists(path_gz)) stop(paste0("Missing file: ", path_gz))
  
  path_in <- path_gz
  if (isTRUE(use_cache)) {
    path_in <- ensure_unzipped(path_gz, cache_dir = cfg$out_cache_dir)
  }
  
  read_dt_cols(path_in, cols = cols, show_progress = show_progress)
}

# -----------------------------
# 2) Helpers for mapping and aggregation
# -----------------------------
build_item_map <- function(dict_dt, id_col, label_col, concept_patterns) {
  out <- data.table::rbindlist(
    lapply(names(concept_patterns), function(concept) {
      pats <- concept_patterns[[concept]]
      keep <- FALSE
      for (pp in pats) keep <- keep | grepl(pp, dict_dt[[label_col]], ignore.case = TRUE)
      
      ids <- unique(dict_dt[keep, get(id_col)])
      if (length(ids) == 0) {
        data.table::data.table(concept = concept, itemid = NA_integer_, label = NA_character_)
      } else {
        lab <- dict_dt[match(ids, dict_dt[[id_col]]), get(label_col)]
        data.table::data.table(concept = concept, itemid = ids, label = lab)
      }
    }),
    fill = TRUE
  )
  
  out <- out[!is.na(itemid)]
  data.table::setorder(out, concept, itemid)
  out
}

agg_events <- function(dt, id_col, time_col, value_col, concept_col) {
  data.table::setorderv(dt, c(id_col, concept_col, time_col))
  dt[
    ,
    .(
      value_mean = mean(get(value_col), na.rm = TRUE),
      value_min  = suppressWarnings(min(get(value_col), na.rm = TRUE)),
      value_max  = suppressWarnings(max(get(value_col), na.rm = TRUE)),
      value_last = get(value_col)[.N]
    ),
    by = c(id_col, concept_col)
  ]
}

to_wide <- function(agg_dt, id_col, prefix) {
  long <- data.table::melt(
    agg_dt,
    id.vars = c(id_col, "concept"),
    measure.vars = c("value_mean", "value_min", "value_max", "value_last"),
    variable.name = "stat",
    value.name = "value"
  )
  long[, feature := paste(prefix, concept, sub("^value_", "", stat), sep = "_")]
  data.table::dcast(long, stats::as.formula(paste(id_col, "~ feature")), value.var = "value")
}

# -----------------------------
# 3) Load cohort and define ICU 24 hour windows
# -----------------------------
msg("Loading cohort index files")

cohort_eval <- data.table::fread(cohort_eval_path, showProgress = FALSE)
cohort_full <- data.table::fread(cohort_full_path, showProgress = FALSE)

time_cols <- c("admittime", "dischtime", "intime", "outtime", "deathtime")
for (cc in intersect(time_cols, names(cohort_eval))) cohort_eval[, (cc) := as.POSIXct(get(cc), tz = "UTC")]
for (cc in intersect(time_cols, names(cohort_full))) cohort_full[, (cc) := as.POSIXct(get(cc), tz = "UTC")]

win_eval <- cohort_eval[, .(
  subject_id, hadm_id, stay_id,
  intime,
  win_start = intime,
  win_end   = intime + 24 * 3600
)]

# -----------------------------
# 4) Vitals dictionary (d_items)
# -----------------------------
msg("Reading ICU dictionary d_items and building vital sign map")

d_items <- read_gz_cols(d_items_gz, cols = c("itemid", "label"), use_cache = FALSE)

vital_patterns <- list(
  heart_rate  = c("^heart rate$", "heart rate"),
  resp_rate   = c("^respiratory rate$", "respiratory rate", "resp rate"),
  temperature = c("^temperature", "temp"),
  spo2        = c("spo2", "o2 saturation", "oxygen saturation"),
  sbp         = c("systolic blood pressure", "^sbp$"),
  dbp         = c("diastolic blood pressure", "^dbp$"),
  map         = c("\\bmean arterial pressure\\b", "^map$"),
  gcs_total   = c("gcs total", "glasgow coma scale total")
)

vital_map <- build_item_map(d_items, "itemid", "label", vital_patterns)
save_data(vital_map, "feature_item_map_vitals")

# -----------------------------
# 5) Vitals from chartevents (PATCHED: join then filter, no non-equi on=)
# -----------------------------
msg("Reading ICU chartevents and extracting first 24 hour vitals for eval cohort")

chartevents_csv <- ensure_unzipped(chartevents_gz, cache_dir = cfg$out_cache_dir)
chartevents <- read_dt_cols(
  chartevents_csv,
  cols = c("stay_id", "charttime", "itemid", "valuenum"),
  show_progress = FALSE
)

chartevents[, charttime := as.POSIXct(charttime, tz = "UTC")]
chartevents[, valuenum  := as_num(valuenum)]

# Keep only eval stays early to reduce work
eval_stays <- unique(win_eval$stay_id)
chartevents <- chartevents[stay_id %in% eval_stays]

# Keep only itemids of interest
vital_itemids <- unique(vital_map$itemid)
chartevents <- chartevents[itemid %in% vital_itemids]

# Join on stay_id to bring window columns, then filter by time
setkey(win_eval, stay_id)
setkey(chartevents, stay_id)

vitals_join <- chartevents[
  win_eval,
  on = "stay_id",
  nomatch = 0L,
  allow.cartesian = TRUE
]

vitals_win <- vitals_join[charttime >= win_start & charttime <= win_end]

# Attach concept
vitals_win <- merge(
  vitals_win,
  vital_map[, .(itemid, concept)],
  by = "itemid",
  all.x = TRUE
)

vitals_agg <- agg_events(
  dt = vitals_win[!is.na(concept) & !is.na(valuenum)],
  id_col = "stay_id",
  time_col = "charttime",
  value_col = "valuenum",
  concept_col = "concept"
)

vitals_wide <- to_wide(vitals_agg, id_col = "stay_id", prefix = "vital")

# -----------------------------
# 6) Labs dictionary (d_labitems)
# -----------------------------
msg("Reading hosp dictionary d_labitems and building lab map")

d_lab <- read_gz_cols(d_labitems_gz, cols = c("itemid", "label"), use_cache = FALSE)

lab_patterns <- list(
  wbc             = c("\\bwbc\\b", "white blood cell"),
  hemoglobin      = c("hemoglobin", "\\bhgb\\b"),
  platelets       = c("platelet"),
  sodium          = c("\\bsodium\\b", "\\bna\\b"),
  potassium       = c("\\bpotassium\\b", "\\bk\\b"),
  chloride        = c("\\bchloride\\b", "\\bcl\\b"),
  bicarbonate     = c("bicarbonate", "\\bhco3\\b"),
  bun             = c("\\bbun\\b", "urea nitrogen"),
  creatinine      = c("creatinine"),
  glucose         = c("glucose"),
  lactate         = c("lactate"),
  bilirubin_total = c("bilirubin, total", "total bilirubin"),
  inr             = c("\\binr\\b", "international normalized ratio")
)

lab_map <- build_item_map(d_lab, "itemid", "label", lab_patterns)
save_data(lab_map, "feature_item_map_labs")

# -----------------------------
# 7) Labs from labevents (PATCHED: join then filter)
# -----------------------------
msg("Reading hosp labevents and extracting first 24 hour labs for eval cohort")

labevents_csv <- ensure_unzipped(labevents_gz, cache_dir = cfg$out_cache_dir)
labevents <- read_dt_cols(
  labevents_csv,
  cols = c("hadm_id", "charttime", "itemid", "valuenum"),
  show_progress = FALSE
)

labevents[, charttime := as.POSIXct(charttime, tz = "UTC")]
labevents[, valuenum  := as_num(valuenum)]

# Reduce to eval hadm_ids
eval_hadm <- unique(win_eval$hadm_id)
labevents <- labevents[hadm_id %in% eval_hadm]

# Reduce to itemids of interest
lab_itemids <- unique(lab_map$itemid)
labevents <- labevents[itemid %in% lab_itemids]

hadm_win <- win_eval[, .(hadm_id, stay_id, win_start, win_end)]
setkey(hadm_win, hadm_id)
setkey(labevents, hadm_id)

labs_join <- labevents[
  hadm_win,
  on = "hadm_id",
  nomatch = 0L,
  allow.cartesian = TRUE
]

labs_win <- labs_join[charttime >= win_start & charttime <= win_end]

labs_win <- merge(
  labs_win,
  lab_map[, .(itemid, concept)],
  by = "itemid",
  all.x = TRUE
)

labs_agg <- agg_events(
  dt = labs_win[!is.na(concept) & !is.na(valuenum) & !is.na(stay_id)],
  id_col = "stay_id",
  time_col = "charttime",
  value_col = "valuenum",
  concept_col = "concept"
)

labs_wide <- to_wide(labs_agg, id_col = "stay_id", prefix = "lab")

# -----------------------------
# 8) Combine baseline + vitals + labs
# -----------------------------
msg("Combining baseline, vitals, and labs into features_eval")

baseline <- cohort_eval[, .(
  subject_id, hadm_id, stay_id,
  age, sex,
  mort_hosp
)]

features_eval <- merge(baseline, vitals_wide, by = "stay_id", all.x = TRUE)
features_eval <- merge(features_eval, labs_wide,  by = "stay_id", all.x = TRUE)

# -----------------------------
# 9) Missingness summary and artifacts
# -----------------------------
msg("Computing missingness summary for eval features")

feature_cols <- setdiff(names(features_eval), c("subject_id", "hadm_id", "stay_id", "sex", "mort_hosp"))
miss <- data.table(
  feature = feature_cols,
  missing_rate = sapply(feature_cols, function(cc) mean(is.na(features_eval[[cc]])))
)
setorder(miss, -missing_rate)

save_table(miss, 3, "feature_missingness_eval")

p_miss <- ggplot(miss, aes(x = reorder(feature, missing_rate), y = missing_rate)) +
  geom_col() +
  coord_flip() +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
  labs(title = "Feature missingness in evaluation cohort", x = NULL, y = "Missing rate")

save_fig(p_miss, 3, "FeatureMissingness_Eval")

save_data(features_eval, "features_eval")

msg("features_eval rows: %s", nrow(features_eval))
msg("features_eval columns: %s", ncol(features_eval))
msg("02_extract_features.R done")
