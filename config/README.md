# config

| File | Tracked | Purpose |
|---|---|---|
| params.yml | yes | Every analytic parameter: seeds, cohort rules, arms, reward weights, confidence level, delays, replicate counts, sensitivity grids |
| paths_template.yml | yes | Template for local paths |
| paths.yml | no (.gitignore) | Local MIMIC-IV root and optional output directory |

Changing any value in params.yml changes the run manifest hash recorded with every output.
