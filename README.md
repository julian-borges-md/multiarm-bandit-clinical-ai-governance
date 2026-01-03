# Multi Armed Bandit Based Adaptive Model Selection for Clinical AI Governance  
### From Static Deployment to Decision Safe Control

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Dataset](https://img.shields.io/badge/dataset-PhysioNet%20MIMIC--IV-orange.svg)](https://physionet.org/content/mimiciv/)
[![Study Type](https://img.shields.io/badge/study-simulation--based%20governance-green.svg)](#overview)
[![Reproducibility](https://img.shields.io/badge/reproducibility-version--locked%20pipeline-brightgreen.svg)](#reproducibility)
[![Governance](https://img.shields.io/badge/focus-deployment%20governance%20%7C%20decision--safety-purple.svg)](#design-principles)
[![Status](https://img.shields.io/badge/status-research-lightgrey.svg)](#)

---

## Overview

This repository provides a **software framework for simulation based evaluation of deployment governance strategies in clinical artificial intelligence systems**. The framework implements **contextual, cost aware multi armed bandit methods** to support adaptive model selection among multiple pre trained and validated predictive models.

The software is designed to study **deployment governance**, not model development. It enables researchers to evaluate how different model selection policies behave under uncertainty, delayed outcome feedback, and explicit safety and cost constraints.

This resource is intended for **methodological research, audit informed governance studies, and reproducible evaluation of adaptive deployment strategies** in health informatics and other safety critical domains.

---

## Why This Repository Exists

Clinical AI systems are commonly deployed using **static model selection strategies**, where a single model is chosen based on retrospective validation metrics and applied uniformly across contexts. Evidence from auditing and post deployment analyses has shown that such strategies can mask **context specific misclassification patterns, shortcut learning, and operational failure modes**.

While audit methods can identify these risks, they do not provide a mechanism for **controlling model exposure during deployment**. This repository was developed to support systematic investigation of **adaptive deployment governance mechanisms** using sequential decision making frameworks.

The central premise is that **model selection itself is a governance problem**, distinct from model training or clinical intervention.

---

## What the Software Provides

The framework implements **multi armed bandit based governance logic** that treats model selection as a sequential decision process:

- Multiple validated predictive models coexist  
- Patient and operational context varies  
- Outcome feedback may be delayed  
- Operational costs and safety considerations are explicit  
- Exploration is constrained by predefined governance rules  

At each simulated decision point, the system selects **which model to deploy** according to a fixed confidence, audit informed policy. The objective is not to optimize predictive accuracy in isolation, but to evaluate **decision level behavior under governance defined constraints**.

**This software does not train models and does not perform clinical decision making.**

---

## Design Principles

**Governance oriented**  
The framework evaluates deployment control policies rather than predictive performance alone.

**Audit informed**  
Known failure patterns and safety considerations can be encoded into reward definitions and elimination rules.

**Decision level evaluation**  
Evaluation focuses on decision sequences, regret, and exposure patterns rather than aggregate metrics.

**Simulation first**  
All analyses are conducted using retrospective simulation to enable ethical evaluation prior to any clinical consideration.

---

## Repository Structure

```text
multiarm-bandit-clinical-ai-governance/
├── docs/                     # Conceptual documentation and governance rationale
├── analysis/
│   └── R/                    # Simulation pipeline and evaluation scripts
├── notebooks/                # Development and exploratory notebooks (optional)
├── data/
│   └── README.md             # Placeholder only; no data are included
├── output/                   # Generated artifacts (not for redistribution)
├── reports/                  # Manuscript figures and tables (optional)
├── LICENSE
├── CITATION.cff
└── README.md
No patient level data are included in this repository.

Data Access and Requirements
This repository does not contain clinical data.

Users must obtain independent, approved access to credentialed PhysioNet datasets such as MIMIC IV to reproduce simulations. All cohort construction and feature extraction steps are performed locally by the user after data access approval.

Reproducibility
Package versions are locked using renv

All paths are project relative

Simulation scripts are fully scripted and version controlled

These measures are intended to support transparent, auditable reproduction by qualified users.

Intended Use and Limitations
This software is intended for:

Simulation based evaluation of deployment governance strategies

Methodological research in adaptive decision systems

Audit and safety oriented informatics research

This software is not intended for clinical deployment, real time decision support, or patient care. Any extension beyond retrospective simulation requires independent validation, governance review, and institutional oversight.

Ethics and Compliance
This project involves secondary use of fully deidentified electronic health record data accessed under approved PhysioNet credentialing. No new data collection was performed. Because the work is limited to retrospective simulation and does not involve patient intervention or prospective deployment, institutional review board approval and informed consent were not required.

License
This project is released under the terms specified in the LICENSE file.

Correspondence
Julian Borges, MD, MSc
Physician Scientist
MS in Health Informatics Candidate
Boston University
Boston, MA, United States
Email: jyborges@bu.edu
