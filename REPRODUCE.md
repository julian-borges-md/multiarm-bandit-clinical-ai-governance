# Reproduce the full pipeline

## Requirements
- Approved PhysioNet access to MIMIC IV
- R installed
- Internet access for initial package install
- Local MIMIC IV path configured

## Setup
1. Clone the repository
2. Open an R session in the repository root
3. Restore the R environment

```r
if (!requireNamespace("renv", quietly = TRUE)) install.packages("renv")
renv::restore()
