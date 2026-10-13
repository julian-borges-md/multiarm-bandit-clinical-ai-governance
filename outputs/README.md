# outputs

| Folder | Committed | Content |
|---|---|---|
| tables/ | yes | Manuscript tables (CSV and Markdown preview), including the run manifest table |
| results/ | yes | Machine readable results: strategy summaries, paired differences, regret curves, sensitivity grids, run manifest |
| figures/ | yes | Manuscript figures (PNG 300 dpi and PDF) |
| data/ | no | Patient level derived data (cohort indices, features, stream predictions) |
| models/ | no | Frozen model objects |
| cache_raw/, logs/ | no | Intermediate files and run logs |

Nothing committed here contains patient level information; every file is an aggregate over at least hundreds of stays.
