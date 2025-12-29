# Multi-Arm Bandit Governance for Clinical AI  
### From Static Deployment to Decision-Safe Control

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Dataset](https://img.shields.io/badge/dataset-MIMIC--IV-orange.svg)](https://physionet.org/content/mimiciv/)
[![Reproducibility](https://img.shields.io/badge/reproducibility-simulation--based-green.svg)](#reproducibility-and-ethical-use)
[![Governance](https://img.shields.io/badge/governance-decision--safety%20%7C%20audit--informed-purple.svg)](#what-makes-this-different)
[![Status](https://img.shields.io/badge/status-research-lightgrey.svg)](#)

---

## Why This Exists

Clinical AI rarely fails because models are inaccurate.  
It fails because **deployment is static**.

Health systems routinely select a single “best” model based on retrospective validation metrics and deploy it uniformly across patients, settings, and time. This assumes that a model that performs well on average will perform safely everywhere.

In practice, this assumption breaks.

Audit studies repeatedly show that high-performing clinical models can rely on **shortcut learning**, exhibit **subgroup-specific misclassification**, and fail silently when context shifts. These are not edge cases. They are **systemic deployment failures**.

Yet once these failures are identified, health systems face a governance gap:

> **Audits diagnose risk, but they do not control deployment.**

This repository exists to close that gap.

---

## What This Repository Does

This project implements a **governance layer for clinical AI deployment** using  
**contextual, cost-aware multi-arm bandits**.

Instead of treating model selection as a one-time engineering decision, deployment is formalized as a **sequential decision problem**:

- Multiple validated models coexist  
- Patient context varies  
- Outcomes arrive with delay  
- Costs and harms are asymmetric  
- Known risks must constrain exploration  

At each decision point, the system selects **which model to deploy**, not to maximize accuracy in isolation, but to **minimize regret under explicit safety and cost constraints**.

**This is not model training.**  
**This is deployment control.**

---

## What Makes This Different

Most clinical AI research focuses on building better models.  
This repository focuses on **using existing models safely once they are deployed**.

### Key distinctions

**Audit-informed**  
Known failure modes are encoded directly into the deployment policy. The system does not rediscover known harms through patient exposure.

**Decision-centric**  
Evaluation focuses on decision-level outcomes rather than aggregate accuracy metrics.

**Risk-aware exploration**  
Exploration is bounded, penalized, and eliminated with statistical confidence — not randomized indiscriminately.

**Governance, not experimentation**  
The policy selects among pre-approved models. It does not assign treatments or conduct clinical trials.

> **Models predict.**  
> **This system decides which model should be trusted, when, and for whom.**

---

## Repository Structure

This repository is organized to clearly separate **governance logic**, **simulation infrastructure**, and **evaluation artifacts**.

```text
multiarm-bandit-clinical-ai-governance/
├── docs/
│   ├── governance-framework.md
│   ├── decision-safety.md
│   └── audit-integration.md
│
├── bandit/
│   ├── policies/
│   ├── rewards/
│   ├── confidence/
│   └── utils/
│
├── simulation/
│   ├── data_interface.py
│   ├── context_builder.py
│   ├── delayed_feedback.py
│   └── run_simulation.py
│
├── models/
│   ├── logistic_regression.py
│   ├── gradient_boosting.py
│   └── neural_network.py
│
├── evaluation/
│   ├── metrics.py
│   ├── subgroup_analysis.py
│   └── reporting.py
│
├── experiments/
│   └── mimic_iv_icu_mortality.yaml
│
├── README.md
├── LICENSE
├── .gitignore
└── CITATION.cff
