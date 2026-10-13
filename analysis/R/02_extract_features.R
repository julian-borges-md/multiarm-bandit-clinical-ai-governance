# analysis/R/02_extract_features.R
# First 24 hour features for every selected stay (training, validation, stream)
# from icu.chartevents (vitals) and hosp.labevents (laboratory tests).
# Extraction uses DuckDB with predicate pushdown on the PhysioNet csv.gz files,
# so the 3.5 GB chartevents file is never decompressed to disk or loaded whole.
#
# Outputs:
#   data/features.csv.gz                 one row per selected stay (patient level, not committed)
#   results/feature_item_map.csv         itemids and labels used, verified against the dictionaries
#   tables/Table03_feature_missingness.csv  missing proportion per feature by split

if (!exists("cfg", inherits = TRUE)) source(file.path("analysis", "R", "00_setup.R"))
suppressPackageStartupMessages({ library(data.table); library(DBI); library(duckdb) })
source(file.path(cfg$repo_root, "analysis", "R", "lib", "synthetic.R"))   # concept name constants

msg("02_extract_features.R starting (mode=%s)", cfg$data_mode)
if (identical(cfg$data_mode, "synthetic")) {
  msg("Synthetic mode: features were written by 01_build_cohort.R; nothing to do")
} else {

cfg_validate_mimic(mustWork = TRUE)
selected <- load_data("cohort_index_selected")
for (cc in c("intime", "outtime", "admittime", "dischtime")) selected[, (cc) := as.POSIXct(get(cc), tz = "UTC")]
W <- params$features$window_hours
win <- selected[, .(stay_id, hadm_id, win_start = intime, win_end = intime + W * 3600)]

# -----------------------------------------------------------------------------
# 1) Item maps (explicit itemids, verified against the dictionaries at run time)
# -----------------------------------------------------------------------------
vital_items <- data.table(
  concept = c("heart_rate", "resp_rate", "temperature", "temperature", "spo2", "sbp", "sbp", "dbp", "dbp", "map", "map",
              "gcs_eye", "gcs_verbal", "gcs_motor"),
  itemid  = c(220045L, 220210L, 223761L, 223762L, 220277L, 220179L, 220050L, 220180L, 220051L, 220181L, 220052L,
              220739L, 223900L, 223901L),
  expect  = c("heart rate", "respiratory rate", "temperature fahrenheit", "temperature celsius", "o2 saturation|spo2",
              "blood pressure systolic", "blood pressure systolic", "blood pressure diastolic", "blood pressure diastolic",
              "blood pressure mean", "blood pressure mean", "gcs - eye", "gcs - verbal", "gcs - motor"))
lab_items <- data.table(
  concept = c("wbc", "hemoglobin", "platelets", "sodium", "potassium", "chloride", "bicarbonate", "bun", "creatinine",
              "glucose", "lactate", "bilirubin_total", "inr"),
  itemid  = c(51301L, 51222L, 51265L, 50983L, 50971L, 50902L, 50882L, 51006L, 50912L, 50931L, 50813L, 50885L, 51237L),
  expect  = c("white blood cells", "hemoglobin", "platelet count", "sodium", "potassium", "chloride", "bicarbonate",
              "urea nitrogen", "creatinine", "glucose", "lactate", "bilirubin, total", "inr"))

d_items <- fread(mimic_file("icu", "d_items.csv.gz"), select = c("itemid", "label"), showProgress = FALSE)
d_lab   <- fread(mimic_file("hosp", "d_labitems.csv.gz"), select = c("itemid", "label", "fluid"), showProgress = FALSE)
vital_items <- merge(vital_items, d_items, by = "itemid", all.x = TRUE)
lab_items   <- merge(lab_items, d_lab, by = "itemid", all.x = TRUE)
bad_v <- vital_items[is.na(label) | !mapply(function(l, e) grepl(e, tolower(l)), label, expect)]
bad_l <- lab_items[is.na(label) | !mapply(function(l, e) grepl(e, tolower(l)), label, expect)]
if (nrow(bad_v) > 0 || nrow(bad_l) > 0) {
  print(rbind(bad_v, bad_l, fill = TRUE))
  stop_log("Item map verification failed: a dictionary label does not match its expected concept")
}
item_map <- rbind(vital_items[, .(source = "icu.chartevents", concept, itemid, label)],
                  lab_items[, .(source = "hosp.labevents", concept, itemid, label)])
save_result(item_map, "feature_item_map")

# plausibility ranges (values outside are treated as recording errors and dropped)
ranges <- list(heart_rate = c(1, 300), resp_rate = c(1, 80), temperature = c(25, 45), spo2 = c(1, 100), sbp = c(20, 300),
               dbp = c(5, 200), map = c(10, 250), gcs = c(3, 15),
               wbc = c(0.1, 500), hemoglobin = c(1, 25), platelets = c(1, 2000), sodium = c(100, 180), potassium = c(1, 12),
               chloride = c(60, 150), bicarbonate = c(2, 60), bun = c(1, 300), creatinine = c(0.1, 40), glucose = c(10, 2000),
               lactate = c(0.1, 40), bilirubin_total = c(0.05, 80), inr = c(0.5, 20))

# -----------------------------------------------------------------------------
# 2) DuckDB extraction with pushdown
# -----------------------------------------------------------------------------
con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
DBI::dbExecute(con, sprintf("SET threads TO %d", cfg$duckdb_threads))
DBI::dbExecute(con, sprintf("SET memory_limit = '%s'", cfg$duckdb_memory))
duckdb::duckdb_register(con, "stays", as.data.frame(win))

sql_path <- function(p) gsub("'", "''", p)

t0 <- Sys.time()
msg("Extracting vitals from chartevents (DuckDB, %d stays)", nrow(win))
q_vit <- sprintf(
  "SELECT c.stay_id, c.charttime, c.itemid, c.valuenum
     FROM read_csv('%s', header = true, types = {'charttime': 'TIMESTAMP', 'storetime': 'TIMESTAMP'}) c
     JOIN stays s ON c.stay_id = s.stay_id
    WHERE c.itemid IN (%s) AND c.valuenum IS NOT NULL
      AND c.charttime >= s.win_start AND c.charttime <= s.win_end",
  sql_path(mimic_file("icu", "chartevents.csv.gz")), paste(vital_items$itemid, collapse = ","))
vit <- as.data.table(DBI::dbGetQuery(con, q_vit))
msg("chartevents rows retained: %d (%.1f min)", nrow(vit), as.numeric(difftime(Sys.time(), t0, units = "mins")))

t0 <- Sys.time()
msg("Extracting laboratory tests from labevents (DuckDB)")
q_lab <- sprintf(
  "SELECT s.stay_id, l.charttime, l.itemid, l.valuenum
     FROM read_csv('%s', header = true, types = {'charttime': 'TIMESTAMP', 'storetime': 'TIMESTAMP'}) l
     JOIN stays s ON l.hadm_id = s.hadm_id
    WHERE l.itemid IN (%s) AND l.valuenum IS NOT NULL
      AND l.charttime >= s.win_start AND l.charttime <= s.win_end",
  sql_path(mimic_file("hosp", "labevents.csv.gz")), paste(lab_items$itemid, collapse = ","))
lab <- as.data.table(DBI::dbGetQuery(con, q_lab))
msg("labevents rows retained: %d (%.1f min)", nrow(lab), as.numeric(difftime(Sys.time(), t0, units = "mins")))

# -----------------------------------------------------------------------------
# 3) Harmonise concepts and aggregate
# -----------------------------------------------------------------------------
vit <- merge(vit, vital_items[, .(itemid, concept)], by = "itemid")
vit[itemid == 223761L, valuenum := (valuenum - 32) * 5 / 9]           # Fahrenheit to Celsius
gcs <- vit[concept %chin% c("gcs_eye", "gcs_verbal", "gcs_motor")]
vit <- vit[!concept %chin% c("gcs_eye", "gcs_verbal", "gcs_motor")]
if (nrow(gcs) > 0) {
  gcs_w <- dcast(gcs[, .(v = valuenum[1]), by = .(stay_id, charttime, concept)], stay_id + charttime ~ concept, value.var = "v")
  need <- c("gcs_eye", "gcs_verbal", "gcs_motor")
  for (cc in setdiff(need, names(gcs_w))) data.table::set(gcs_w, j = cc, value = NA_real_)
  gcs_tot <- gcs_w[!is.na(gcs_eye) & !is.na(gcs_verbal) & !is.na(gcs_motor),
                   .(stay_id, charttime, itemid = NA_integer_, valuenum = gcs_eye + gcs_verbal + gcs_motor, concept = "gcs")]
  vit <- rbind(vit, gcs_tot, use.names = TRUE)
}
lab <- merge(lab, lab_items[, .(itemid, concept)], by = "itemid")

apply_ranges <- function(dt) {
  dt[, lo := vapply(concept, function(k) ranges[[k]][1], numeric(1))]
  dt[, hi := vapply(concept, function(k) ranges[[k]][2], numeric(1))]
  out <- dt[is.finite(valuenum) & valuenum >= lo & valuenum <= hi]
  out[, c("lo", "hi") := NULL]
  out
}
n_v0 <- nrow(vit); vit <- apply_ranges(vit); n_l0 <- nrow(lab); lab <- apply_ranges(lab)
msg("Plausibility filter dropped %d vital and %d laboratory rows", n_v0 - nrow(vit), n_l0 - nrow(lab))

agg_wide <- function(dt, prefix) {
  setorder(dt, stay_id, concept, charttime)
  agg <- dt[, .(mean = mean(valuenum), min = min(valuenum), max = max(valuenum), last = valuenum[.N]), by = .(stay_id, concept)]
  long <- melt(agg, id.vars = c("stay_id", "concept"), variable.name = "stat", value.name = "value")
  long[, feature := paste(prefix, concept, stat, sep = "_")]
  dcast(long, stay_id ~ feature, value.var = "value")
}
vitals_wide <- agg_wide(vit, "vital")
labs_wide   <- agg_wide(lab, "lab")

# -----------------------------------------------------------------------------
# 4) Assemble, guarantee every expected column, save
# -----------------------------------------------------------------------------
baseline <- selected[, .(subject_id, hadm_id, stay_id, split, age, sex, race_group, anchor_year_group, anchor_offset, mort_hosp, icu_los_hours)]
features <- merge(baseline, vitals_wide, by = "stay_id", all.x = TRUE)
features <- merge(features, labs_wide, by = "stay_id", all.x = TRUE)
expected <- c(paste0("vital_", rep(VITAL_CONCEPTS, each = 4), "_", STATS), paste0("lab_", rep(LAB_CONCEPTS, each = 4), "_", STATS))
for (cc in setdiff(expected, names(features))) data.table::set(features, j = cc, value = NA_real_)
setcolorder(features, c(names(baseline), expected))
save_data(features, "features")

miss <- features[, lapply(.SD, function(x) mean(is.na(x))), by = split, .SDcols = expected]
miss_long <- melt(miss, id.vars = "split", variable.name = "feature", value.name = "missing_rate")
miss_wide <- dcast(miss_long, feature ~ split, value.var = "missing_rate")
save_table(miss_wide, 3, "feature_missingness")
msg("features: %d rows, %d columns", nrow(features), ncol(features))
msg("02_extract_features.R done")
}
