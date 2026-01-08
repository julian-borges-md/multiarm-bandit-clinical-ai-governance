# Multi Armed Bandit Based Adaptive Model Selection for Clinical AI Governance
### From Static Deployment to Decision Safe Control

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Dataset](https://img.shields.io/badge/dataset-PhysioNet%20MIMIC--IV-orange.svg)](https://physionet.org/content/mimiciv/)
[![Study Type](https://img.shields.io/badge/study-simulation%20based%20governance-green.svg)](#overview)
[![Reproducibility](https://img.shields.io/badge/reproducibility-version%20locked%20pipeline-brightgreen.svg)](#reproducibility)
[![Focus](https://img.shields.io/badge/focus-deployment%20governance%20and%20decision%20safety-purple.svg)](#design-principles)
[![Status](https://img.shields.io/badge/status-research-lightgrey.svg)](#)

---

## Overview

This repository provides a software framework for simulation based evaluation of deployment governance strategies in clinical artificial intelligence systems. The framework implements contextual, cost aware multi armed bandit methods to support adaptive model selection among multiple pre trained and validated predictive models.

The project focuses on deployment governance, not model development. It enables evaluation of how model selection policies behave under uncertainty, delayed outcome feedback, and explicit safety and cost constraints.

This resource is intended for methodological research, audit informed governance studies, and reproducible evaluation of adaptive deployment strategies in health informatics and other safety critical domains.

---

## Why This Repository Exists

Clinical AI systems are commonly deployed using static model selection strategies, where a single model is chosen using retrospective validation metrics and applied uniformly across contexts. Audit and post deployment analyses have shown that such strategies can mask context specific misclassification patterns, shortcut learning, and operational failure modes.

Audit methods can identify risks, but audits alone do not provide a mechanism for controlling model exposure during deployment. This repository supports systematic investigation of adaptive deployment governance mechanisms using sequential decision making frameworks.

Core premise: model selection is a governance problem, distinct from model training and distinct from clinical intervention.

---

## What the Software Provides

The framework implements multi armed bandit governance logic that treats model selection as a sequential decision process:

- Multiple validated predictive models coexist
- Patient and operational context varies
- Outcome feedback may be delayed
- Operational costs and safety considerations are explicit
- Exposure is governed by predefined rules and confidence thresholds

At each simulated decision point, the system selects which model to deploy according to a fixed confidence, audit informed policy. The objective is not to optimize accuracy in isolation. The objective is to evaluate decision level behavior under governance defined constraints.

This software does not provide clinical decision support and is not intended for real time patient care.

---

## Design Principles

**Governance oriented**  
Evaluates deployment control policies rather than predictive performance alone.

**Audit informed**  
Encodes known failure patterns and safety priorities into reward design and policy constraints.

**Decision level evaluation**  
Measures regret, exposure, safety, cost, and subgroup consistency across sequential decisions.

**Simulation first**  
Uses retrospective simulation as an ethical prerequisite prior to any consideration of live deployment.

**Reproducible by design**  
Uses deterministic cohort selection, fixed random seeds, and version locked environments.

---

## Outputs You Should Expect

When you run the full pipeline, the repository produces decision logs, metrics, figures, and tables that map directly to the manuscript.

### Main figures (recommended)
- Figure 1: Governance architecture diagram
- Figure 2: Cumulative regret curves across strategies
- Figure 3: Safety outcomes (false negative rate or cumulative false negatives)
- Figure 4: Cost efficiency (mean cost and cumulative cost)
- Figure 5: Subgroup performance and disparity (age and sex; optional race and ethnicity if stable)
- Figure 6: Governance behavior (arm selection proportions and exploration proxy)

### Main tables (recommended)
- Table 1: Cohort characteristics and outcome prevalence
- Table 2: Summary metrics (regret, accuracy, false negative rate, cost, disparity measures)

All artifacts are generated from scripts and saved as both machine readable and publication ready formats.

---

## Repository Structure

```text
multiarm-bandit-clinical-ai-governance/
├── docs/                         Conceptual documentation and governance rationale
├── config/                       Reward weights, delay parameters, seeds, thresholds
├── scripts/
│   ├── cohort/                   Cohort construction and eligibility filters
│   ├── features/                 Feature extraction and preprocessing
│   ├── models/                   Model training, calibration, and inference wrappers
│   ├── governance/               Bandit policy and delayed feedback queue
│   ├── evaluation/               Metrics, subgroup analyses, comparators
│   └── reproduce_all.R           Single entry point to reproduce all outputs
├── figures/
│   ├── main/                     Manuscript figures
│   └── supplement/               Supplementary figures
├── tables/
│   ├── main/                     Manuscript tables
│   └── supplement/               Supplementary tables
├── outputs/
│   ├── decision_logs/            Per decision audit logs for the simulation stream
│   └── metrics/                  Computed metrics and intermediate summaries
├── notebooks/                    Optional exploration notebooks
├── data/
│   └── README.md                 Placeholder only; no data are included
├── LICENSE
├── CITATION.cff
└── README.md

## Data Access and Requirements

This repository does not contain clinical data.

To reproduce the analyses, users must obtain independent, approved access to PhysioNet datasets such as MIMIC IV and comply with all applicable data use agreement requirements. Cohort construction, feature extraction, and simulation are performed locally by the user after access approval and completion of required training.

---

## Reproducibility

Reproducibility is implemented through the following measures:

- Version locked R environment using `renv`  
- Project relative file paths to ensure portability  
- Fully scripted cohort construction, feature extraction, governance simulation, and evaluation pipelines  
- Fixed random seeds for patient sampling, delayed outcome feedback, and other stochastic components  
- Persisted identifier lists for evaluation cohorts to enable exact reruns  

Together, these measures support transparent, auditable reproduction by qualified users with approved data access.

---

## Intended Use and Limitations

This software is intended for:

- Simulation based evaluation of deployment governance strategies  
- Methodological research in adaptive and sequential decision systems  
- Audit and safety oriented clinical informatics research  

This software is **not** intended for clinical deployment, real time decision support, or patient care. Any extension beyond retrospective simulation requires independent validation, formal governance review, and appropriate institutional oversight.

---

## Ethics and Compliance

This project involves secondary analysis of fully deidentified electronic health record data accessed under approved PhysioNet credentialing. No new data collection was performed. The work is limited to retrospective simulation and does not involve patient intervention or prospective deployment.

Users are responsible for complying with all dataset credentialing, training, and data use agreement requirements.

---

## License

This project is released under the terms specified in the `LICENSE` file.

---

## Citation

If you use this repository in academic work, please cite both this repository and the MIMIC IV resource. Citation metadata is provided in `CITATION.cff`.

---

## Author

**Julian Borges, MD, MS**  
MS Health Informatics 2027  
Department of Computer Science  
Boston University Metropolitan College  

Clinician Scientist  
Harvard Medical School Global Clinical Scholars Research Training Program, cohort 2025  

Email: jyborges@bu.edu  
Phone: 617-895-8403
