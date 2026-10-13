# Rscript tests/run_tests.R
library(testthat)
res <- testthat::test_dir("tests/testthat", reporter = "summary", stop_on_failure = TRUE)
