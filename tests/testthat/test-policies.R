make_stream <- function(T, means, seed = 1) {
  set.seed(seed)
  K <- length(means)
  R <- sapply(means, function(m) pmin(pmax(rnorm(T, m, 0.15), 0), 1))
  P <- matrix(runif(T * K), T, K); y <- rbinom(T, 1, 0.2)
  list(R = R, P = P, y = y, thr = rep(0.3, K), cost = rep(0.5, K))
}

test_that("fixed confidence action elimination keeps the best arm and eliminates clearly inferior arms", {
  means <- c(0.80, 0.60, 0.40)
  best_kept <- 0; both_elim <- 0; n <- 60
  for (s in seq_len(n)) {
    st <- make_stream(3000, means, seed = s)
    set.seed(s)
    sched <- make_schedule(3000, arrival_rate = 0.65, delay_min = 6, delay_max = 72)
    res <- run_policy("fcae", st$R, st$P, st$y, st$thr, st$cost, sched, delta = 0.05, check_leakage = TRUE)
    best_kept <- best_kept + res$active_final[1]
    both_elim <- both_elim + all(!res$active_final[2:3])
    expect_equal(res$leak_violations, 0)
  }
  expect_gte(best_kept / n, 0.95)
  expect_gte(both_elim / n, 0.95)
})

test_that("empirical Bernstein elimination keeps the best arm and eliminates clearly inferior arms", {
  means <- c(0.80, 0.60, 0.40)
  best_kept <- 0; both_elim <- 0; n <- 40
  for (s in seq_len(n)) {
    st <- make_stream(3000, means, seed = 100 + s)
    set.seed(100 + s)
    sched <- make_schedule(3000, arrival_rate = 0.65, delay_min = 6, delay_max = 72)
    res <- run_policy("fcae_eb", st$R, st$P, st$y, st$thr, st$cost, sched, delta = 0.05, check_leakage = TRUE)
    best_kept <- best_kept + res$active_final[1]
    both_elim <- both_elim + all(!res$active_final[2:3])
    expect_equal(res$leak_violations, 0)
  }
  expect_gte(best_kept / n, 0.95)
  expect_gte(both_elim / n, 0.95)
})

test_that("implied sample size is finite for a positive gap and grows as the gap shrinks", {
  n_big <- implied_sample_size(0.2, 0.02, 0.02, 3, 0.05, "bernstein")
  n_small <- implied_sample_size(0.05, 0.02, 0.02, 3, 0.05, "bernstein")
  expect_true(is.finite(n_big) && n_big < n_small)
  expect_true(is.na(implied_sample_size(0, 0.02, 0.02, 3, 0.05, "hoeffding")))
})

test_that("no policy uses an outcome before its availability time", {
  st <- make_stream(1500, c(0.7, 0.6, 0.5), seed = 3)
  for (pol in c("fcae", "fcae_eb", "thompson", "ucb1", "random")) {
    set.seed(11)
    sched <- make_schedule(1500, 0.65, 6, 72)
    res <- run_policy(pol, st$R, st$P, st$y, st$thr, st$cost, sched, delta = 0.05, check_leakage = TRUE)
    expect_equal(res$leak_violations, 0)
    # feedback count can never exceed the number of decisions whose availability precedes the last decision time
    n_possible <- sum(sched$availability[-1500] <= sched$arrival[1500])
    expect_lte(res$n_feedback, n_possible)
  }
})

test_that("with zero delay every past decision is fed back before the next decision", {
  st <- make_stream(500, c(0.7, 0.5), seed = 5)
  set.seed(2)
  sched <- make_schedule(500, 0.65, 0, 0)
  res <- run_policy("ucb1", st$R, st$P, st$y, st$thr, st$cost, sched, delta = 0.05)
  expect_equal(res$n_feedback, 499)
})

test_that("static policies always deploy the requested arm and regret against the fixed best is non negative", {
  st <- make_stream(800, c(0.7, 0.6, 0.5), seed = 9)
  sched <- make_schedule(800, 0.65, 6, 72)
  res <- run_policy("static_A", st$R, st$P, st$y, st$thr, st$cost, sched, static_arm = 2L)
  expect_true(all(res$chosen == 2L))
  ctx <- data.table::data.table(age_ge_65 = rbinom(800, 1, 0.5), sex = sample(c("M", "F"), 800, TRUE))
  m <- run_metrics(res, st$R, st$y, ctx, best_fixed_arm = which.max(colSums(st$R)))
  expect_gte(m$scalar[["cum_regret_fixed"]], 0)
  expect_gte(m$scalar[["cum_regret_oracle"]], m$scalar[["cum_regret_fixed"]])
})

test_that("gap bootstrap reproduces the full sample gaps on average and is deterministic for a seed", {
  set.seed(5)
  T <- 4000; K <- 3
  R <- cbind(pmin(pmax(rnorm(T, 0.80, 0.15), 0), 1), pmin(pmax(rnorm(T, 0.75, 0.15), 0), 1), pmin(pmax(rnorm(T, 0.65, 0.15), 0), 1))
  gb1 <- gap_bootstrap(R, K, delta = 0.05, B = 200, seed = 3)
  gb2 <- gap_bootstrap(R, K, delta = 0.05, B = 200, seed = 3)
  expect_identical(gb1, gb2)
  expect_equal(dim(gb1), c(200, 1 + 4 * K))
  mu <- colMeans(R); gaps <- mu[which.max(mu)] - mu
  expect_equal(unname(colMeans(gb1[, paste0("gap_", 1:K)])), unname(gaps), tolerance = 0.01)
  expect_true(mean(gb1[, "best"] == 1) > 0.9)
  n3 <- gb1[, "n_bernstein_3"]
  expect_true(all(is.finite(n3)))
  expect_true(all(gb1[, "n_hoeffding_3"] >= n3 | is.na(gb1[, "n_hoeffding_3"])))
  expect_true(all(is.na(gb1[gb1[, "best"] == 1, "n_bernstein_1"])))
})

test_that("implied sample size is the exact smallest n (agrees with a brute force scan)", {
  gap <- 0.04; va <- 0.0214; vb <- 0.0266; K <- 3; delta <- 0.05
  for (m in c("hoeffding", "bernstein")) {
    n_star <- implied_sample_size(gap, va, vb, K, delta, m)
    f <- function(n) confidence_radius(n, K, delta, m, var = va) + confidence_radius(n, K, delta, m, var = vb)
    expect_lt(f(n_star), gap)
    expect_gte(f(n_star - 1), gap)
  }
})

test_that("required delta is consistent with the implied sample size", {
  gap <- 0.04; va <- 0.0214; vb <- 0.0266; K <- 3
  for (m in c("hoeffding", "bernstein")) {
    n_star <- implied_sample_size(gap, va, vb, K, 0.05, m)
    d_req <- required_delta(gap, va, vb, K, n_star, m)
    # at n_star observations the required confidence level is at or just below 0.05
    expect_lte(d_req, 0.05)
    expect_gt(required_delta(gap, va, vb, K, n_star - 50, m), d_req)
  }
  expect_true(required_delta(0.01, va, vb, K, 100, "hoeffding") > 1)   # no admissible level
})

test_that("Gaussian posterior Thompson sampling converges on the best arm and leaks no feedback", {
  means <- c(0.80, 0.70, 0.60)
  share_best <- 0
  for (s in 1:10) {
    st <- make_stream(3000, means, seed = 300 + s)
    set.seed(300 + s)
    sched <- make_schedule(3000, 0.65, 6, 72)
    res <- run_policy("thompson_gauss", st$R, st$P, st$y, st$thr, st$cost, sched, delta = 0.05, check_leakage = TRUE)
    expect_equal(res$leak_violations, 0)
    share_best <- share_best + mean(res$chosen[2001:3000] == 1)
  }
  expect_gt(share_best / 10, 0.8)
})

test_that("signed subgroup gaps and the experienced disparity are computed as defined", {
  st <- make_stream(600, c(0.7, 0.6), seed = 9)
  P <- st$P; y <- st$y; thr <- rep(0.3, 2)
  set.seed(1)
  sched <- make_schedule(600, 0.65, 0, 0)
  res <- run_policy("static_A", st$R, P, y, thr, st$cost, sched, static_arm = 1L)
  ctx <- data.table::data.table(age_ge_65 = rep(0:1, length.out = 600), sex = rep(c("F", "M"), each = 300), race_group = "White")
  m <- run_metrics(res, st$R, y, ctx, 1L, thin = 600, arm_gap = list(age = c(0.1, 0.3), sex = c(0.05, 0.2)))
  pos <- y == 1; dep <- P[, 1] >= 0.3
  expect_equal(unname(m$scalar["tpr_gap_age_signed"]), mean(dep[pos & ctx$age_ge_65 == 0]) - mean(dep[pos & ctx$age_ge_65 == 1]))
  expect_equal(unname(m$scalar["tpr_gap_sex_signed"]), mean(dep[pos & ctx$sex == "F"]) - mean(dep[pos & ctx$sex == "M"]))
  expect_equal(unname(m$scalar["experienced_gap_age"]), 0.1)   # every decision on arm 1
})
