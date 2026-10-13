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
