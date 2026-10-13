test_that("synthetic features have the extraction schema and disjoint splits", {
  f <- synthetic_features(600, 200, seed = 1)
  expected <- c(paste0("vital_", rep(VITAL_CONCEPTS, each = 4), "_", STATS), paste0("lab_", rep(LAB_CONCEPTS, each = 4), "_", STATS))
  expect_true(all(expected %in% names(f)))
  expect_equal(sum(f$split == "stream"), 200)
  expect_equal(length(intersect(f[split != "stream", subject_id], f[split == "stream", subject_id])), 0)
  expect_true(all(f$mort_hosp %in% c(0, 1)))
})
