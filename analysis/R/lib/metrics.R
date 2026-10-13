# analysis/R/lib/metrics.R
# Evaluation metrics used by the training and simulation scripts.
# All functions are pure (no side effects) so they can be unit tested.

# Area under the ROC curve by the rank (Mann Whitney) formula, average ranks for ties.
auroc <- function(y, p) {
  ok <- is.finite(p) & !is.na(y)
  y <- y[ok]; p <- p[ok]
  n1 <- sum(y == 1); n0 <- sum(y == 0)
  if (n1 == 0 || n0 == 0) return(NA_real_)
  r <- rank(p, ties.method = "average")
  (sum(r[y == 1]) - n1 * (n1 + 1) / 2) / (n1 * n0)
}

# Area under the precision recall curve (step interpolation over the ranked list).
auprc <- function(y, p) {
  ok <- is.finite(p) & !is.na(y)
  y <- y[ok]; p <- p[ok]
  if (sum(y == 1) == 0) return(NA_real_)
  o <- order(p, decreasing = TRUE)
  y <- y[o]
  tp <- cumsum(y == 1)
  fp <- cumsum(y == 0)
  precision <- tp / (tp + fp)
  recall <- tp / sum(y == 1)
  # average precision: sum of precision at each positive, divided by number of positives
  sum(precision[y == 1]) / sum(y == 1)
}

brier <- function(y, p) mean((p - y)^2, na.rm = TRUE)

logit <- function(p) { p <- pmin(pmax(p, 1e-6), 1 - 1e-6); log(p / (1 - p)) }
expit <- function(z) 1 / (1 + exp(-z))

# Logistic calibration: intercept and slope of y on logit(p); slope 1 and intercept 0 is perfect.
calibration_fit <- function(y, p) {
  z <- logit(p)
  fit <- tryCatch(stats::glm(y ~ z, family = stats::binomial()), error = function(e) NULL)
  if (is.null(fit)) return(c(intercept = NA_real_, slope = NA_real_))
  cf <- stats::coef(fit)
  c(intercept = unname(cf[1]), slope = unname(cf[2]))
}

# Smallest threshold achieving at least the target sensitivity.
threshold_for_sensitivity <- function(y, p, target = 0.80) {
  pos <- sort(p[y == 1], decreasing = TRUE)
  if (length(pos) == 0) return(NA_real_)
  k <- ceiling(target * length(pos))
  pos[k]
}

classification_at <- function(y, p, thr) {
  pred <- as.integer(p >= thr)
  tp <- sum(pred == 1 & y == 1); fn <- sum(pred == 0 & y == 1)
  fp <- sum(pred == 1 & y == 0); tn <- sum(pred == 0 & y == 0)
  c(sensitivity = if (tp + fn > 0) tp / (tp + fn) else NA_real_,
    specificity = if (fp + tn > 0) tn / (fp + tn) else NA_real_,
    ppv = if (tp + fp > 0) tp / (tp + fp) else NA_real_,
    npv = if (tn + fn > 0) tn / (tn + fn) else NA_real_,
    fnr = if (tp + fn > 0) fn / (tp + fn) else NA_real_,
    alert_rate = mean(pred == 1))
}

# Percentile bootstrap of the mean of paired differences across replicates.
boot_mean_ci <- function(x, B = 2000, seed = 1, level = 0.95) {
  x <- x[is.finite(x)]
  if (length(x) < 2) return(c(mean = mean(x), lo = NA_real_, hi = NA_real_))
  set.seed(seed)
  n <- length(x)
  m <- vapply(seq_len(B), function(b) mean(x[sample.int(n, n, replace = TRUE)]), numeric(1))
  a <- (1 - level) / 2
  c(mean = mean(x), lo = unname(stats::quantile(m, a)), hi = unname(stats::quantile(m, 1 - a)))
}

summary_stats <- function(x) {
  x <- x[is.finite(x)]
  c(mean = mean(x), sd = stats::sd(x), median = stats::median(x),
    p2.5 = unname(stats::quantile(x, 0.025)), p97.5 = unname(stats::quantile(x, 0.975)), n = length(x))
}
