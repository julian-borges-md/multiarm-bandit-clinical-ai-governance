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

This repository provides a software framework for simulation based evaluation of **deployment governance strategies** in clinical artificial intelligence systems. The framework implements **contextual, cost aware multi armed bandit methods** to support adaptive model selection among multiple pre trained and validated predictive models.

The project explicitly focuses on **deployment governance rather than model development**. It enables systematic evaluation of how model selection policies behave under uncertainty, delayed outcome feedback, and explicitly defined safety and operational cost constraints.

This resource is intended for methodological research, audit informed governance studies, and reproducible evaluation of adaptive deployment strategies in health informatics and other safety critical domains.

- The repository evaluates **deployment governance**, not predictive model development  
- Reported outcomes focus on **decision safety, operational efficiency, and equity**, not clinical efficacy  
- Results are derived from **retrospective simulation using United States based clinical data**  
- Adaptive behavior is governed by **fixed confidence, audit informed policies** under delayed outcome feedback  

---

## Why This Repository Exists

Clinical AI systems are commonly deployed using **static model selection strategies**, where a single model is chosen using retrospective validation metrics and applied uniformly across patients, settings, and time. Audit and post deployment analyses have shown that such strategies can obscure **context specific misclassification patterns, shortcut learning, and operational failure modes**, even when aggregate performance appears acceptable.

Audit methods can diagnose these risks, but audits alone do not provide a mechanism for **controlling model exposure during deployment**. This repository exists to support systematic investigation of **adaptive deployment governance mechanisms** using sequential decision making frameworks.

**Core premise:**  
Model selection is a governance problem, distinct from model training and distinct from clinical intervention.

---

## What the Software Provides

The framework implements governance logic that treats model selection as a **sequential decision process**:

- Multiple validated predictive models coexist  
- Patient and operational context varies across decisions  
- Outcome feedback may be delayed  
- Operational costs and safety priorities are explicit  
- Model exposure is governed by predefined rules and confidence thresholds  

At each simulated decision point, the system selects which model to deploy according to a **fixed confidence, audit informed policy**. The objective is not to optimize predictive accuracy in isolation, but to evaluate **decision level behavior under governance defined constraints**, including safety, cost, and equity considerations.

This software does **not** provide clinical decision support and is **not** intended for real time patient care.

---

## Design Principles

**Governance oriented**  
Evaluates deployment control policies rather than predictive performance alone.

**Audit informed**  
Encodes known failure patterns, safety priorities, and cost constraints into reward design and policy structure.

**Decision level evaluation**  
Measures regret, exposure, safety outcomes, operational cost, and subgroup performance consistency across sequential decisions.

**Simulation first**  
Uses retrospective simulation as an ethical and methodological prerequisite prior to any consideration of live deployment.

**Reproducible by design**  
Implements deterministic cohort selection, fixed random seeds, and version locked environments to support auditability.

---

## Health Impact and Care Process Relevance

Although this framework evaluates deployment governance rather than clinical intervention, the simulated outcomes correspond directly to health relevant and care process impacts. Reductions in clinically harmful false negative predictions reflect fewer missed high risk patients during deployment. Reduced cumulative regret indicates improved reliability of AI assisted decisions over time. Lower operational cost per prediction reflects avoidance of unnecessary resource utilization. Improved subgroup performance consistency reflects reduced inequitable exposure to unsafe model behavior.

These effects represent **measurable improvements in decision safety, efficiency, and equity** at the population level within a United States based critical care cohort.

---

## Outputs You Should Expect

Running the full pipeline produces decision logs, metrics, figures, and tables that map directly to the associated manuscript.

### Main figures (recommended)
- Figure 1: Governance architecture diagram  
- Figure 2: Cumulative regret curves across deployment strategies  
- Figure 3: Safety outcomes (false negative rate or cumulative false negatives)  
- Figure 4: Cost efficiency (mean and cumulative operational cost)  
- Figure 5: Subgroup performance and disparity (age and sex; optional race and ethnicity if stable)  
- Figure 6: Governance behavior (arm selection proportions and exploration proxy)  

### Main tables (recommended)
- Table 1: Cohort characteristics and outcome prevalence  
- Table 2: Summary metrics (regret, accuracy, false negative rate, cost, disparity measures)  

All artifacts are generated programmatically and saved in both machine readable and publication ready formats.

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

To reproduce the analyses, users must obtain independent, approved access to PhysioNet datasets such as MIMIC IV and comply with all applicable data use agreement requirements. Cohort construction, feature extraction, and governance simulation are performed locally after access approval and completion of required training.

---

## Reproducibility

Reproducibility is implemented through the following measures:

- Version locked R environments using `renv`  
- Project relative file paths to ensure portability across systems  
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

This software is **not intended** for clinical deployment, real time decision support, or patient care. Any extension beyond retrospective simulation requires independent validation, formal governance review, and appropriate institutional oversight.

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
MS Health Informatics ’27  
Department of Computer Science  
Boston University Metropolitan College  

Clinician Scientist  
Harvard Medical School GCSRT ’25  
Email: jyborges@bu.edu  
Phone: 617-895-8403

---

## Appendix A. Reproducibility and Ethical Use

This repository is designed to support **transparent, auditable, and responsible evaluation** of adaptive deployment governance strategies for clinical artificial intelligence systems.

### Reproducibility Commitments

The project adheres to established best practices for reproducible computational research, including:

- Deterministic cohort construction using persisted identifiers  
- Fully scripted analytic pipelines with no manual intervention  
- Fixed random seeds for all stochastic components, including sampling and delayed outcome feedback  
- Version locked software environments using `renv` to ensure dependency stability  
- Programmatic generation of all figures, tables, and summary metrics  

These measures enable qualified investigators with approved data access to independently reproduce all reported results without access to the original analytic environment.

### Ethical Use Statement

This software is intended **exclusively for research, audit, and governance evaluation purposes**. It is not a clinical decision support system and must not be used to guide patient care.

Any extension beyond retrospective simulation, including shadow deployment or prospective evaluation, requires:

- Independent institutional review  
- Formal clinical AI governance approval  
- Compliance with applicable regulatory, ethical, and data protection standards  

The authors explicitly discourage use of this framework for live clinical decision making without appropriate validation and oversight.

---

## Appendix B. Code Availability Statement

### Code Availability

All code used for cohort construction, feature extraction, predictive model inference, governance policy implementation, delayed feedback simulation, and evaluation of performance, safety, operational cost, and subgroup equity metrics is publicly available in this repository:

**GitHub Repository:**  
https://github.com/julian-borges-md/multiarm-bandit-clinical-ai-governance

The repository includes:

- A comprehensive `README.md` describing project scope, governance rationale, and repository structure  
- Fully scripted pipelines for cohort construction, governance simulation, and evaluation  
- Scripts used to generate all figures and tables reported in the associated manuscript  
- Configuration files specifying governance parameters, confidence thresholds, and fixed random seeds  
- Version locked software environments to support deterministic reproduction  

Because the underlying clinical dataset contains protected health information and cannot be redistributed, raw patient level data are not included. Reproduction of results using real clinical data requires independent credentialed access to the MIMIC IV database through PhysioNet and completion of all required training and data use agreements.

This approach is consistent with FAIR principles and best practices for reproducible clinical AI research involving restricted access datasets.

---
