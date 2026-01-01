# Multi-Arm Bandit Governance for Clinical AI  
### From Static Deployment to Decision-Safe Control

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Dataset](https://img.shields.io/badge/dataset-MIMIC--IV-orange.svg)](https://physionet.org/content/mimiciv/)
[![Reproducibility](https://img.shields.io/badge/reproducibility-simulation--based-green.svg)](#reproducibility-and-ethical-use)
[![Governance](https://img.shields.io/badge/governance-decision--safety%20%7C%20audit--informed-purple.svg)](#what-makes-this-different)
[![Status](https://img.shields.io/badge/status-research-lightgrey.svg)](#)

---

## Why This Exists

Clinical AI systems rarely fail because models are inaccurate.  
They fail because **deployment is static**.

In routine practice, health systems select a single “best” model based on retrospective validation metrics and deploy it uniformly across patients, settings, and time. This implicitly assumes that a model performing well on average will perform safely across all contexts.

This assumption does not hold.

Audit and post-deployment analyses consistently show that high-performing clinical models can rely on **shortcut learning**, exhibit **context- and subgroup-specific misclassification**, and fail silently under distributional or operational shift. These are not rare edge cases. They are **systemic deployment failures**.

Yet once such risks are identified, health systems encounter a governance gap:

> **Audits diagnose risk, but they do not control deployment.**

This repository exists to close that gap.

---

## What This Repository Does

This project implements a **governance layer for clinical AI deployment** using **contextual, cost-aware multi-arm bandits**.

Instead of treating model selection as a one-time engineering decision, deployment is formalized as a **sequential decision problem**:

- Multiple validated models coexist  
- Patient context varies  
- Outcomes arrive with delay  
- Costs and harms are asymmetric  
- Known risks must constrain exploration  

At each decision point, the system selects **which model to deploy**, not to maximize accuracy in isolation, but to minimize regret under explicit safety and cost constraints.

**This is not model training.**  
**This is deployment control.**

---

## What Makes This Different

Most clinical AI research focuses on building better models.  
This repository focuses on **deploying existing models safely and accountably**.

### Key distinctions

**Audit-informed**  
Known failure modes are encoded directly into the deployment policy. The system is designed to avoid rediscovering known harms through patient exposure.

**Decision-centric**  
Evaluation targets decision-level outcomes, not only aggregate metrics that can mask context-specific failures.

**Risk-bounded exploration**  
Exploration is constrained, penalized, and eliminated with statistical confidence, rather than randomized indiscriminately.

**Governance, not experimentation**  
The policy selects among pre-approved predictive models. It does not assign treatments and does not conduct clinical trials.

> **Models predict.**  
> **This system governs which model is used, when, and for whom.**

---

## Repository Structure

This repository is organized to separate governance logic, simulation infrastructure, and evaluation artifacts.

```text
multiarm-bandit-clinical-ai-governance/
├── docs/
│   ├── governance-framework.md
│   ├── decision-safety.md
│   └── audit-integration.md
│
├── analysis/
│   └── R/
│       ├── 00_setup.R
│       ├── 01_data_inventory.R
│       ├── 02_cohort_extract.R
│       ├── 03_feature_engineering.R
│       ├── 04_model_training.R
│       ├── 05_bandit_simulation.R
│       ├── 06_evaluation.R
│       ├── 07_reporting_outputs.R
│       └── utils.R
│
├── notebooks/
│   └── scratch/
│
├── data/
│   ├── raw/
│   │   ├── README.md
│   │   └── .gitkeep
│   ├── processed/
│   │   └── .gitkeep
│   ├── cohort/
│   │   └── .gitkeep
│   └── features/
│       └── .gitkeep
│
├── output/
│   ├── figure_01_data_inventory.png
│   ├── table_01_data_inventory.csv
│   └── logs/
│       └── pipeline.log
│
├── reports/
│   ├── manuscript_figures/
│   │   └── .gitkeep
│   ├── manuscript_tables/
│   │   └── .gitkeep
│   └── supplementary/
│       └── .gitkeep
│
├── documents/
│   ├── figures/
│   │   ├── architecture/
│   │   ├── governance/
│   │   ├── methods/
│   │   └── results/
│   ├── images/
│   │   ├── diagrams/
│   │   ├── slides/
│   │   └── icons/
│   └── README.md
│
├── LICENSE
├── .gitignore
└── CITATION.cff


## Reproducibility guarantees

- All package versions are locked using renv  
- All file paths are project relative using here  


---

## Run the entire analysis in one command

From the project root:

Rscript -e 'renv::restore(); \



# Disclosure and Reproducibility Statement
This study was conducted solely by the author and received no external funding or financial support. The author declares no competing interests. All analyses were performed using publicly available, fully de identified datasets and did not involve human participants, clinical interventions, or identifiable personal data. Accordingly, institutional review board approval and informed consent were not required.
Model development and evaluation were implemented through a fully scripted and version controlled analytic pipeline designed to ensure transparency, auditability, and reproducibility. All performance estimates were derived exclusively from pooled out of fold predictions generated under five fold cross validation, thereby avoiding in sample or single split inflation. Class imbalance handling and preprocessing steps were confined strictly to training folds to prevent information leakage.
Interpretable baseline models were intentionally prioritized, and validation practices were aligned with principles articulated in FDA Good Machine Learning Practice guidance, emphasizing conservative evaluation, clear operating characteristics, and clinically inspectable behavior.
All code, analytic procedures, and intermediate outputs are publicly available to support independent replication. The author welcomes correspondence regarding methodological details, reproducibility, and potential extensions of this work.

# Corresponding Author
Julian Borges, MD, MSc Physician Scientist MS in Health Informatics Candidate Boston University Boston, MA, United States
Email: jyborges@bu.edu
