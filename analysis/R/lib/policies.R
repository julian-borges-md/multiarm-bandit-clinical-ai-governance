# analysis/R/lib/policies.R
# Governance policies, composite reward, delayed feedback queue and the
# sequential simulator. Pure functions: no file access, no global state.
#
# Notation (matches the manuscript):
#   K arms, T decisions. P[t, a] is the calibrated mortality probability of arm a
#   for the t-th patient of the stream, y[t] the in hospital mortality label,
#   thr[a] the operating threshold of arm a, cost[a] its normalised cost.
#   r_raw[t, a] = (1 - (P[t, a] - y[t])^2) - lambda_c * cost[a] - lambda_s * FN[t, a]
#   r[t, a]     = (r_raw[t, a] + lambda_c + lambda_s) / (1 + lambda_c + lambda_s)   in [0, 1]

# -----------------------------------------------------------------------------
# Reward
# -----------------------------------------------------------------------------
composite_reward <- function(p, y, thr, cost, lambda_c, lambda_s) {
  fn <- as.numeric(y == 1 & p < thr)
  r_raw <- (1 - (p - y)^2) - lambda_c * cost - lambda_s * fn
  (r_raw + lambda_c + lambda_s) / (1 + lambda_c + lambda_s)
}

reward_matrix <- function(P, y, thr, cost, lambda_c, lambda_s) {
  K <- ncol(P)
  R <- matrix(NA_real_, nrow = nrow(P), ncol = K, dimnames = dimnames(P))
  for (a in seq_len(K)) R[, a] <- composite_reward(P[, a], y, thr[a], cost[a], lambda_c, lambda_s)
  R
}

# -----------------------------------------------------------------------------
# Confidence radii for rewards in [0, 1], valid simultaneously for all n and all K arms
# (union bound over arms and over n with sum 1/n^2 < 2), so that the probability that
# any estimate ever leaves its interval is at most delta.
#   hoeffding : sqrt( log(4 K n^2 / delta) / (2 n) )                         (Hoeffding 1963)
#   bernstein : sqrt( 2 V_n L / n ) + 7 L / (3 (n - 1)),  L = log(16 K n^2 / delta)
#               with V_n the sample variance                                 (Maurer and Pontil 2009)
# -----------------------------------------------------------------------------
confidence_radius <- function(n, K, delta, method = c("hoeffding", "bernstein"), var = NULL) {
  method <- match.arg(method)
  m <- pmax(n, 1)
  if (method == "hoeffding") {
    r <- sqrt(log(4 * K * m^2 / delta) / (2 * m))
    r[n <= 0] <- Inf
  } else {
    if (is.null(var)) stop("bernstein radius needs the sample variance")
    L <- log(16 * K * m^2 / delta)
    v <- pmax(var, 0); v[is.na(v)] <- 0.25
    r <- sqrt(2 * v * L / m) + 7 * L / (3 * pmax(m - 1, 1))
    r[n <= 1] <- Inf
  }
  r
}

sample_var <- function(n, s, q) {
  # unbiased sample variance from count, sum and sum of squares
  out <- (q / pmax(n, 1) - (s / pmax(n, 1))^2) * n / pmax(n - 1, 1)
  out[n <= 1] <- NA_real_
  pmax(out, 0)
}

# -----------------------------------------------------------------------------
# Delayed feedback schedule
#   arrival[t]: decision time (hours) of patient t; availability[t] = arrival + delay
# -----------------------------------------------------------------------------
make_schedule <- function(T, arrival_rate, delay_min, delay_max) {
  gaps <- stats::rexp(T, rate = arrival_rate)
  arrival <- cumsum(gaps)
  delay <- if (delay_max > 0) stats::runif(T, delay_min, delay_max) else rep(0, T)
  list(arrival = arrival, availability = arrival + delay, delay = delay)
}

# -----------------------------------------------------------------------------
# Simulator
#   policy: one of "fcae", "fcae_strat", "thompson", "ucb1", "random",
#           "static_A" ... (static_<arm key>), "ensemble", "heuristic"
#   R: T x K reward matrix for the arms; P, thr, cost as above
#   extra: list with ensemble/heuristic quantities (p_ens, thr_ens, cost_ens, p_heur, thr_heur, cost_heur, used_heur)
#   stratum: integer vector (1..S) for stratified elimination
#   schedule: from make_schedule(); feedback for decision s is usable at decision t iff availability[s] <= arrival[t]
# Returns a list with per decision vectors and policy diagnostics.
# -----------------------------------------------------------------------------
run_policy <- function(policy, R, P, y, thr, cost, schedule, delta = 0.05,
                       stratum = NULL, extra = NULL, static_arm = NA_integer_,
                       trace_every = 10, check_leakage = FALSE) {
  T <- nrow(R); K <- ncol(R)
  arrival <- schedule$arrival; avail <- schedule$availability
  ord_v <- order(avail)                      # feedback events in availability order
  ptr <- 1L

  chosen <- integer(T)
  dep_p <- numeric(T); dep_thr <- numeric(T); dep_cost <- numeric(T); dep_r <- numeric(T)

  # learning state
  n_a <- rep(0, K); s_a <- rep(0, K); q_a <- rep(0, K)
  active <- rep(TRUE, K)
  bound <- if (policy == "fcae") "hoeffding" else "bernstein"
  is_fcae <- policy %in% c("fcae", "fcae_eb")
  elim_step <- rep(NA_integer_, K)
  rr_ptr <- 0L                                # round robin pointer for fcae
  S <- if (!is.null(stratum)) max(stratum) else 1L
  n_sa <- matrix(0, S, K); s_sa <- matrix(0, S, K); q_sa <- matrix(0, S, K); active_s <- matrix(TRUE, S, K)
  rr_s <- rep(0L, S)
  elim_step_s <- matrix(NA_integer_, S, K)
  alpha <- rep(1, K); beta <- rep(1, K)       # Thompson
  n_feedback <- 0L
  leak_violations <- 0L

  trace <- if (policy %in% c("fcae", "fcae_eb", "ucb1", "thompson")) {
    vector("list", ceiling(T / trace_every))
  } else NULL
  tr_i <- 0L

  for (t in seq_len(T)) {
    # 1) incorporate every feedback that has become available by the time of decision t
    while (ptr <= T) {
      s <- ord_v[ptr]
      if (avail[s] > arrival[t]) break
      if (s >= t) break                       # not decided yet (only possible with zero delay)
      a <- chosen[s]
      if (a >= 1L && a <= K) {                # arm based policies only
        r <- R[s, a]
        n_a[a] <- n_a[a] + 1; s_a[a] <- s_a[a] + r; q_a[a] <- q_a[a] + r^2
        if (policy == "fcae_strat") { st <- stratum[s]; n_sa[st, a] <- n_sa[st, a] + 1; s_sa[st, a] <- s_sa[st, a] + r; q_sa[st, a] <- q_sa[st, a] + r^2 }
        if (policy == "thompson") { b <- stats::rbinom(1, 1, r); alpha[a] <- alpha[a] + b; beta[a] <- beta[a] + 1 - b }
        n_feedback <- n_feedback + 1L
        if (check_leakage && avail[s] > arrival[t]) leak_violations <- leak_violations + 1L
      }
      ptr <- ptr + 1L
    }

    # 2) elimination step (fixed confidence action elimination)
    if (is_fcae && sum(active) > 1) {
      idx <- which(active & n_a > 0)
      if (length(idx) > 1) {
        m <- s_a[idx] / n_a[idx]
        rad <- confidence_radius(n_a[idx], K, delta, bound, var = sample_var(n_a[idx], s_a[idx], q_a[idx]))
        ucb <- m + rad; lcb <- m - rad
        for (k in seq_along(idx)) {
          other_max_lcb <- max(lcb[-k])
          if (ucb[k] < other_max_lcb) { active[idx[k]] <- FALSE; elim_step[idx[k]] <- t }
        }
      }
    }
    if (policy == "fcae_strat") {
      st <- stratum[t]
      if (sum(active_s[st, ]) > 1) {
        idx <- which(active_s[st, ] & n_sa[st, ] > 0)
        if (length(idx) > 1) {
          m <- s_sa[st, idx] / n_sa[st, idx]
          rad <- confidence_radius(n_sa[st, idx], K, delta / S, "bernstein", var = sample_var(n_sa[st, idx], s_sa[st, idx], q_sa[st, idx]))
          ucb <- m + rad; lcb <- m - rad
          for (k in seq_along(idx)) {
            if (ucb[k] < max(lcb[-k])) { active_s[st, idx[k]] <- FALSE; elim_step_s[st, idx[k]] <- t }
          }
        }
      }
    }

    # 3) select
    a_t <- NA_integer_
    if (is_fcae) {
      act <- which(active)
      rr_ptr <- rr_ptr + 1L
      a_t <- act[((rr_ptr - 1L) %% length(act)) + 1L]
    } else if (policy == "fcae_strat") {
      st <- stratum[t]
      act <- which(active_s[st, ])
      rr_s[st] <- rr_s[st] + 1L
      a_t <- act[((rr_s[st] - 1L) %% length(act)) + 1L]
    } else if (policy == "thompson") {
      draws <- stats::rbeta(K, alpha, beta)
      a_t <- which.max(draws)
    } else if (policy == "ucb1") {
      if (any(n_a == 0)) a_t <- which(n_a == 0)[1] else {
        idx_u <- s_a / n_a + sqrt(2 * log(max(n_feedback, 1)) / n_a)
        a_t <- which.max(idx_u)
      }
    } else if (policy == "random") {
      a_t <- sample.int(K, 1)
    } else if (startsWith(policy, "static")) {
      a_t <- static_arm
    } else if (policy == "ensemble") {
      a_t <- 0L
    } else if (policy == "heuristic") {
      a_t <- 0L
    } else stop("Unknown policy: ", policy)

    chosen[t] <- a_t
    if (a_t >= 1L) {
      dep_p[t] <- P[t, a_t]; dep_thr[t] <- thr[a_t]; dep_cost[t] <- cost[a_t]; dep_r[t] <- R[t, a_t]
    } else if (policy == "ensemble") {
      dep_p[t] <- extra$p_ens[t]; dep_thr[t] <- extra$thr_ens; dep_cost[t] <- extra$cost_ens; dep_r[t] <- extra$r_ens[t]
    } else {
      dep_p[t] <- extra$p_heur[t]; dep_thr[t] <- extra$thr_heur[t]; dep_cost[t] <- extra$cost_heur[t]; dep_r[t] <- extra$r_heur[t]
    }

    # 4) trace of estimates (sparse)
    if (!is.null(trace) && (t %% trace_every == 0L)) {
      tr_i <- tr_i + 1L
      m <- ifelse(n_a > 0, s_a / pmax(n_a, 1), NA_real_)
      rad <- confidence_radius(n_a, K, delta, bound, var = sample_var(n_a, s_a, q_a))
      trace[[tr_i]] <- data.table::data.table(t = t, arm = seq_len(K), n = n_a, mean = m,
                                              lcb = m - rad, ucb = m + rad, active = active)
    }
  }

  list(chosen = chosen, p = dep_p, thr = dep_thr, cost = dep_cost, reward = dep_r,
       elim_step = elim_step, elim_step_strat = elim_step_s, active_final = active,
       n_feedback = n_feedback, leak_violations = leak_violations,
       trace = if (!is.null(trace)) data.table::rbindlist(trace[seq_len(tr_i)]) else NULL)
}

# -----------------------------------------------------------------------------
# Composite (non learning) strategies: ensemble average and heuristic escalation
# -----------------------------------------------------------------------------
make_extra <- function(P, y, thr, cost, lambda_c, lambda_s, thr_ens, arm_low = 1L, arm_high = ncol(P)) {
  p_ens <- rowMeans(P)
  cost_ens <- max(cost)
  r_ens <- composite_reward(p_ens, y, thr_ens, cost_ens, lambda_c, lambda_s)
  escalate <- P[, arm_low] >= thr[arm_low]
  p_heur <- ifelse(escalate, P[, arm_high], P[, arm_low])
  thr_heur <- ifelse(escalate, thr[arm_high], thr[arm_low])
  cost_heur <- ifelse(escalate, cost[arm_low] + cost[arm_high], cost[arm_low])
  r_heur <- composite_reward(p_heur, y, thr_heur, cost_heur, lambda_c, lambda_s)
  list(p_ens = p_ens, thr_ens = thr_ens, cost_ens = cost_ens, r_ens = r_ens,
       p_heur = p_heur, thr_heur = thr_heur, cost_heur = cost_heur, r_heur = r_heur, escalate = escalate)
}

# -----------------------------------------------------------------------------
# Per run metrics
# -----------------------------------------------------------------------------
run_metrics <- function(res, R, y, ctx, best_fixed_arm, thin = 10) {
  T <- length(res$chosen); K <- ncol(R)
  oracle <- apply(R, 1, max)
  fixed <- R[, best_fixed_arm]
  inc_fixed <- fixed - res$reward
  inc_oracle <- oracle - res$reward
  cum_fixed <- cumsum(inc_fixed)
  cum_oracle <- cumsum(inc_oracle)

  dep_pred_pos <- res$p >= res$thr
  pos <- y == 1
  fnr <- if (sum(pos) > 0) mean(!dep_pred_pos[pos]) else NA_real_
  tpr_by <- function(g) {
    lv <- sort(unique(g))
    sapply(lv, function(l) { i <- pos & g == l; if (sum(i) == 0) NA_real_ else mean(dep_pred_pos[i]) })
  }
  gap <- function(v) { v <- v[!is.na(v)]; if (length(v) < 2) NA_real_ else unname(max(v) - min(v)) }
  tpr_age <- tpr_by(ctx$age_ge_65); tpr_sex <- tpr_by(ctx$sex)
  shares <- sapply(seq_len(K), function(a) mean(res$chosen == a))

  # exploration proxy: share of pulls on arms other than the arm dominating the last decile
  last_block <- res$chosen[(floor(0.9 * T) + 1):T]
  dominant <- if (all(last_block == 0L)) NA_integer_ else as.integer(names(which.max(table(last_block[last_block > 0]))))
  deciles <- ceiling(seq_len(T) / (T / 10))
  explore_by_decile <- sapply(1:10, function(d) { i <- deciles == d; if (is.na(dominant)) NA_real_ else mean(res$chosen[i] != dominant) })

  list(
    scalar = c(
      cum_regret_fixed = cum_fixed[T], cum_regret_oracle = cum_oracle[T],
      mean_reward = mean(res$reward), mean_cost = mean(res$cost),
      auroc = auroc(y, res$p), brier = brier(y, res$p), fnr = fnr, alert_rate = mean(dep_pred_pos),
      tpr_gap_age = gap(tpr_age), tpr_gap_sex = gap(tpr_sex),
      explore_first_decile = explore_by_decile[1], explore_last_decile = explore_by_decile[10],
      n_feedback = res$n_feedback, leak_violations = res$leak_violations,
      stats::setNames(shares, paste0("share_arm", seq_len(K))),
      stats::setNames(as.numeric(res$elim_step), paste0("elim_step_arm", seq_len(K)))
    ),
    curve = data.table::data.table(t = seq(thin, T, by = thin),
                                   cum_regret_fixed = cum_fixed[seq(thin, T, by = thin)],
                                   cum_regret_oracle = cum_oracle[seq(thin, T, by = thin)],
                                   cum_cost = cumsum(res$cost)[seq(thin, T, by = thin)]),
    explore_by_decile = explore_by_decile,
    dominant = dominant
  )
}

# -----------------------------------------------------------------------------
# Implied sample complexity: smallest per arm sample size at which a suboptimal arm
# would be eliminated by the best arm, given the observed gap and variances.
# -----------------------------------------------------------------------------
implied_sample_size <- function(gap, var_arm, var_best, K, delta, method, n_max = 1e7) {
  if (!is.finite(gap) || gap <= 0) return(NA_real_)
  n <- 2
  while (n <= n_max) {
    r <- confidence_radius(n, K, delta, method, var = var_arm) + confidence_radius(n, K, delta, method, var = var_best)
    if (r < gap) return(n)
    n <- ceiling(n * 1.05) + 1
  }
  Inf
}
