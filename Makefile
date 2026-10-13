.PHONY: run synthetic test clean
run:
	Rscript analysis/R/00_run_all.R
synthetic:
	DATA_MODE=synthetic Rscript analysis/R/00_run_all.R
test:
	Rscript tests/run_tests.R
clean:
	rm -rf outputs/data outputs/models outputs/cache_raw outputs/logs
