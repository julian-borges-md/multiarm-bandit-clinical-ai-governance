test_that("auroc matches pROC and handles ties", {
  skip_if_not_installed("pROC")
  set.seed(7)
  y <- rbinom(400, 1, 0.3); p <- round(plogis(rnorm(400, y, 1.2)), 2)
  expect_equal(auroc(y, p), as.numeric(pROC::auc(pROC::roc(y, p, quiet = TRUE))), tolerance = 1e-10)
})

test_that("threshold for sensitivity reaches the target", {
  set.seed(8)
  y <- rbinom(2000, 1, 0.2); p <- plogis(rnorm(2000, y, 1))
  thr <- threshold_for_sensitivity(y, p, 0.8)
  expect_gte(classification_at(y, p, thr)[["sensitivity"]], 0.8)
})

test_that("bootstrap interval contains the sample mean", {
  x <- rnorm(50, 1, 2)
  ci <- boot_mean_ci(x, B = 500, seed = 1)
  expect_true(ci[["lo"]] <= ci[["mean"]] && ci[["mean"]] <= ci[["hi"]])
})
