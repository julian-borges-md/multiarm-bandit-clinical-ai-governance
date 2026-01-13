# 00_setup.R
# Central configuration, paths, seeds, logging, and reproducibility controls
#
# This script is sourced by all downstream analysis steps.
# No analysis is performed here.

stopifnot(interactive() || !interactive())
