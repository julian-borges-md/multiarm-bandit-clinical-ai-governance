# analysis/R/lib/synthetic.R
# Synthetic cohort and feature generator with the same schema as the MIMIC-IV
# extraction. It exists so that the full pipeline, the tests and the CI can run
# without credentialed data. Values are not clinically meaningful and must not
# be reported as results.

VITAL_CONCEPTS <- c("heart_rate", "resp_rate", "temperature", "spo2", "sbp", "dbp", "map", "gcs")
LAB_CONCEPTS   <- c("wbc", "hemoglobin", "platelets", "sodium", "potassium", "chloride", "bicarbonate",
                    "bun", "creatinine", "glucose", "lactate", "bilirubin_total", "inr")
CORE_LABS      <- c("wbc", "hemoglobin", "platelets", "sodium", "potassium", "chloride", "bicarbonate",
                    "bun", "creatinine", "glucose")
EXT_LABS       <- c("lactate", "bilirubin_total", "inr")
STATS          <- c("mean", "min", "max", "last")

synthetic_features <- function(n_dev, n_stream, seed, validation_fraction = 0.25) {
  set.seed(seed)
  n <- n_dev + n_stream
  subject_id <- seq_len(n) + 10000L
  split <- c(sample(c("train", "val"), n_dev, replace = TRUE, prob = c(1 - validation_fraction, validation_fraction)),
             rep("stream", n_stream))
  is_stream <- split == "stream"
  age <- pmin(pmax(round(stats::rnorm(n, 65, 16)), 18), 95)
  sex <- sample(c("M", "F"), n, replace = TRUE, prob = c(0.56, 0.44))
  z <- stats::rnorm(n)                                     # latent severity
  z[is_stream] <- z[is_stream] + 0.15                      # mild distribution shift in deployment

  base <- list(heart_rate = c(88, 16), resp_rate = c(19, 5), temperature = c(37.0, 0.7), spo2 = c(96.5, 2.5),
               sbp = c(120, 20), dbp = c(65, 13), map = c(80, 14), gcs = c(13.5, 2.5))
  effect <- list(heart_rate = 7, resp_rate = 2.5, temperature = 0.15, spo2 = -1.2, sbp = -8, dbp = -4, map = -6, gcs = -1.6)
  race_group <- sample(c("White", "Black", "Hispanic or Latino", "Asian", "Other or unknown"), n, replace = TRUE,
                       prob = c(0.66, 0.10, 0.05, 0.03, 0.16))
  dt <- data.table::data.table(subject_id = subject_id, hadm_id = subject_id + 500000L, stay_id = subject_id + 900000L,
                               split = split, age = age, sex = sex, race_group = race_group,
                               anchor_year_group = ifelse(is_stream, "2020 - 2022", "2014 - 2016"), anchor_offset = 0L)
  for (v in VITAL_CONCEPTS) {
    m <- base[[v]][1] + effect[[v]] * z + stats::rnorm(n, 0, base[[v]][2])
    spread <- abs(stats::rnorm(n, 0, base[[v]][2] / 2))
    data.table::set(dt, j = paste0("vital_", v, "_mean"), value = m)
    data.table::set(dt, j = paste0("vital_", v, "_min"), value = m - spread)
    data.table::set(dt, j = paste0("vital_", v, "_max"), value = m + spread)
    data.table::set(dt, j = paste0("vital_", v, "_last"), value = m + stats::rnorm(n, 0, base[[v]][2] / 3))
  }
  lab_base <- list(wbc = c(10, 4), hemoglobin = c(11.5, 2), platelets = c(220, 90), sodium = c(138, 4.5),
                   potassium = c(4.1, 0.6), chloride = c(103, 5), bicarbonate = c(24, 4), bun = c(24, 15),
                   creatinine = c(1.2, 0.8), glucose = c(140, 45), lactate = c(2.0, 1.4), bilirubin_total = c(1.0, 1.5), inr = c(1.3, 0.5))
  lab_eff <- list(wbc = 2, hemoglobin = -0.5, platelets = -30, sodium = 0.5, potassium = 0.15, chloride = 0.5, bicarbonate = -2,
                  bun = 8, creatinine = 0.4, glucose = 15, lactate = 1.1, bilirubin_total = 0.7, inr = 0.25)
  ext_prob <- stats::plogis(-0.4 + 0.9 * z)                 # sicker patients get extended labs more often
  ext_avail <- stats::rbinom(n, 1, ext_prob) == 1
  for (l in LAB_CONCEPTS) {
    m <- lab_base[[l]][1] + lab_eff[[l]] * z + stats::rnorm(n, 0, lab_base[[l]][2])
    spread <- abs(stats::rnorm(n, 0, lab_base[[l]][2] / 3))
    miss <- if (l %in% EXT_LABS) !ext_avail else stats::rbinom(n, 1, 0.03) == 1
    vals <- list(mean = m, min = m - spread, max = m + spread, last = m + stats::rnorm(n, 0, lab_base[[l]][2] / 3))
    for (s in STATS) { x <- vals[[s]]; x[miss] <- NA_real_; data.table::set(dt, j = paste0("lab_", l, "_", s), value = x) }
  }
  lin <- -3.2 + 1.3 * z + 0.025 * (age - 65) + 0.6 * ext_avail
  lin[is_stream] <- lin[is_stream] + 0.2
  dt[, mort_hosp := stats::rbinom(.N, 1, stats::plogis(lin))]
  dt[, icu_los_hours := round(24 + stats::rexp(.N, 1 / 60), 1)]
  dt[]
}
