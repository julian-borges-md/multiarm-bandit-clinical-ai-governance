test_that("anytime Hoeffding radius controls the failure probability at the nominal level", {
  # Monte Carlo: Bernoulli(0.5) rewards, K = 3 arms, n up to 2000; the union over n and arms must fail < delta
  set.seed(42)
  K <- 3; delta <- 0.05; reps <- 400; n_max <- 2000
  fails <- 0
  for (r in seq_len(reps)) {
    bad <- FALSE
    for (a in seq_len(K)) {
      x <- rbinom(n_max, 1, 0.5)
      m <- cumsum(x) / seq_len(n_max)
      rad <- confidence_radius(seq_len(n_max), K, delta)
      if (any(abs(m - 0.5) > rad)) { bad <- TRUE; break }
    }
    fails <- fails + bad
  }
  expect_lt(fails / reps, delta)
})

test_that("radius is infinite before the first observation and decreases with n", {
  expect_true(is.infinite(confidence_radius(0, 3, 0.05)))
  r <- confidence_radius(c(1, 10, 100, 1000), 3, 0.05)
  expect_true(all(diff(r) < 0))
})

test_that("empirical Bernstein radius controls the failure probability at the nominal level", {
  set.seed(43)
  K <- 3; delta <- 0.05; reps <- 300; n_max <- 1500
  fails <- 0
  for (r in seq_len(reps)) {
    bad <- FALSE
    for (a in seq_len(K)) {
      x <- rbeta(n_max, 2, 5)                       # bounded in [0, 1], mean 2/7
      n <- seq_len(n_max); s <- cumsum(x); q <- cumsum(x^2)
      m <- s / n
      rad <- confidence_radius(n, K, delta, "bernstein", var = sample_var(n, s, q))
      if (any(abs(m - 2 / 7)[n > 1] > rad[n > 1])) { bad <- TRUE; break }
    }
    fails <- fails + bad
  }
  expect_lt(fails / reps, delta)
})

test_that("sample variance from running sums matches var()", {
  x <- runif(50)
  expect_equal(sample_var(50, sum(x), sum(x^2)), var(x), tolerance = 1e-12)
})
