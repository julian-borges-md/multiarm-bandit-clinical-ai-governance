test_that("composite reward is bounded in [0, 1] for arm costs at most 1", {
  set.seed(1)
  p <- runif(5000); y <- rbinom(5000, 1, 0.3)
  for (lc in c(0, 0.1, 0.2)) for (ls in c(0, 0.5, 1)) {
    r <- composite_reward(p, y, thr = 0.3, cost = 1, lc, ls)
    expect_true(all(r >= 0 & r <= 1))
  }
})

test_that("safety penalty applies only to false negatives and cost lowers reward", {
  r_fn <- composite_reward(p = 0.1, y = 1, thr = 0.3, cost = 0, lambda_c = 0, lambda_s = 0.5)
  r_tp <- composite_reward(p = 0.9, y = 1, thr = 0.3, cost = 0, lambda_c = 0, lambda_s = 0.5)
  r_fp <- composite_reward(p = 0.9, y = 0, thr = 0.3, cost = 0, lambda_c = 0, lambda_s = 0.5)
  expect_lt(r_fn, r_tp)
  expect_equal(r_fp, (1 - 0.81 + 0.5) / 1.5)
  r_cheap <- composite_reward(0.5, 0, 0.3, cost = 0.25, 0.1, 0)
  r_dear  <- composite_reward(0.5, 0, 0.3, cost = 1.00, 0.1, 0)
  expect_gt(r_cheap, r_dear)
})

test_that("reward matrix matches the scalar definition", {
  P <- matrix(c(0.2, 0.8, 0.5, 0.1), 2, 2); y <- c(1, 0)
  R <- reward_matrix(P, y, thr = c(0.3, 0.3), cost = c(0.25, 1), 0.1, 0.5)
  expect_equal(R[1, 1], composite_reward(0.2, 1, 0.3, 0.25, 0.1, 0.5))
  expect_equal(R[2, 2], composite_reward(0.1, 0, 0.3, 1, 0.1, 0.5))
})

test_that("accuracy utility equals binary correctness at the operating threshold and stays in [0, 1]", {
  r_tp <- composite_reward(p = 0.9, y = 1, thr = 0.3, cost = 0, lambda_c = 0, lambda_s = 0.5, utility = "accuracy")
  r_fn <- composite_reward(p = 0.1, y = 1, thr = 0.3, cost = 0, lambda_c = 0, lambda_s = 0.5, utility = "accuracy")
  r_tn <- composite_reward(p = 0.1, y = 0, thr = 0.3, cost = 0, lambda_c = 0, lambda_s = 0.5, utility = "accuracy")
  r_fp <- composite_reward(p = 0.9, y = 0, thr = 0.3, cost = 0, lambda_c = 0, lambda_s = 0.5, utility = "accuracy")
  expect_equal(r_tp, 1)
  expect_equal(r_tn, 1)
  expect_equal(r_fp, 0.5 / 1.5)
  expect_equal(r_fn, 0)
  set.seed(2)
  p <- runif(5000); y <- rbinom(5000, 1, 0.3)
  r <- composite_reward(p, y, thr = 0.3, cost = 1, 0.2, 1, utility = "accuracy")
  expect_true(all(r >= 0 & r <= 1))
  expect_lte(length(unique(r)), 3)   # correct, false positive and false negative are the only outcomes at one cost
  R <- reward_matrix(matrix(p[1:10], 5, 2), y[1:5], thr = c(0.3, 0.3), cost = c(0.25, 1), 0.1, 0.5, utility = "accuracy")
  expect_equal(R[1, 2], composite_reward(p[6], y[1], 0.3, 1, 0.1, 0.5, utility = "accuracy"))
})
