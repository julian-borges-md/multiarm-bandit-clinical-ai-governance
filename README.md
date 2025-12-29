Multi-Arm Bandit Governance for Clinical AI

Audit-Informed, Contextual, and Cost-Aware Model Deployment

Overview

Clinical artificial intelligence systems are increasingly deployed in high-stakes healthcare environments, yet deployment strategies remain largely static. Predictive models are typically selected based on retrospective validation metrics and then applied uniformly across heterogeneous patient populations, care settings, and time. This paradigm obscures systematic failure modes, including shortcut learning, subgroup-specific misclassification, and context-dependent risk that persist despite acceptable aggregate performance.

This repository implements a governance-oriented framework for real-time clinical AI deployment using contextual, cost-aware multi-arm bandits. Rather than treating model selection as a one-time engineering decision, deployment is formalized as a sequential decision problem in which the system adaptively selects among multiple validated predictive models under uncertainty, operational constraints, delayed outcome feedback, and explicit safety objectives.

The framework is explicitly audit-informed. Prior audit findings identifying shortcut learning, inequitable performance, and decision-level risk are encoded directly into the deployment policy through a structured reward function that balances predictive correctness, operational cost, and clinically meaningful safety penalties. In this way, the system closes the governance gap between diagnosing model risk and acting on it in real time.

Conceptual Contribution

This repository advances clinical AI governance by shifting the focus from model-centric evaluation to decision-centric control. It treats deployment as the primary locus of safety, accountability, and equity, and positions multi-arm bandits not as experimental tools, but as continuous governance mechanisms that regulate model exposure while minimizing patient risk.

Key principles include:

Decision safety over aggregate accuracy

Adaptive deployment rather than static model selection

Explicit encoding of cost and harm tradeoffs

Statistical guarantees aligned with ethical constraints

Repository Structure

This repository is organized to clearly separate governance logic, simulation infrastructure, and evaluation artifacts, supporting transparency, reproducibility, and extension to new clinical domains.

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


The structure is intentionally modular. Predictive models, bandit policies, reward definitions, and datasets can be swapped independently, allowing the governance layer to be reused across clinical tasks without retraining or revalidating core logic.

How This Relates to the Manuscript

This repository serves as the reference implementation for the manuscript:

“Multi-Armed Bandits for Real-Time Model Selection in Clinical AI:
Audit-Informed, Contextual, Cost-Aware Governance Using MIMIC-IV.”

The manuscript advances the claim that many clinical AI failures arise not from inadequate models, but from unsafe deployment strategies that apply a single predictive system uniformly across heterogeneous contexts. It reframes deployment as a sequential decision problem governed by decision safety, cost awareness, and audit-informed risk control.

This codebase operationalizes that claim.

Specifically:

Bandit policies implement the fixed-confidence action elimination framework described in the Methods
Reward functions encode predictive correctness, operational cost, and safety penalties motivated by audit evidence
Simulation components emulate prospective deployment with delayed outcome feedback using MIMIC-IV ICU data
Evaluation modules reproduce reported outcomes including regret, accuracy, cost, and subgroup equity

The repository is not limited to the published experiment. It is designed as a reusable governance layer applicable to alternative clinical tasks, datasets, and deployment settings.

Reproducibility and Ethical Use

Reproducibility Commitments

This repository supports computational reproducibility while respecting ethical and legal constraints of clinical data use.

All governance logic, bandit policies, and evaluation metrics are deterministic given fixed configuration files and random seeds. Reference experiment configurations are provided to enable faithful reproduction of reported results using authorized access to the underlying dataset. 
Raw clinical data are not included. Users must obtain approved access to MIMIC-IV through PhysioNet and comply with all data use agreements. Data interfaces are cleanly separated from governance logic to support reproducibility without redistributing protected data.

Ethical Framing and Intended Use

This framework is intended as a governance and decision safety mechanism, not as a clinical decision system. It does not replace clinician judgment, institutional protocols, or regulatory oversight.

Simulation is used explicitly for pre-deployment evaluation, allowing adaptive strategies to be stress-tested before any real-world use and reducing the risk of uncontrolled experimentation on patients.

Audit-Informed Deployment

Audit findings are treated as prior knowledge that constrains deployment behavior. Known risks are encoded directly into reward structures and safety penalties rather than rediscovered through patient exposure.

Data Governance and Privacy

All workflows assume compliance with institutional review board requirements, deidentification standards, and local privacy regulations. No identifiable patient data are required.

Clinical Safety Disclaimer

This repository provides research software intended solely for methodological development, simulation, and governance research. It is not a medical device, not a clinical decision support system, and not intended for direct clinical use.

No component has been reviewed or approved by the U.S. Food and Drug Administration. Any real-world use would require regulatory authorization, institutional approval, and continuous monitoring.

Human oversight is assumed at all stages. Automated model selection does not transfer accountability away from clinicians or institutions. Simulation results do not substitute for prospective validation. Users are responsible for regulatory, ethical, and institutional compliance.

Post-Deployment Monitoring and Drift Detection

Adaptive governance does not end at deployment. Consistent with FDA Good Machine Learning Practice, any real-world application of this framework must be accompanied by continuous post-deployment monitoring to detect performance degradation, emerging bias, and changes in clinical context.

Continuous Performance Monitoring

Post-deployment monitoring should track both decision-level outcomes and policy behavior over time, including predictive performance, safety-weighted outcomes, operational cost, and model selection frequencies stratified by patient subgroups.

Distribution and Context Drift

Clinical environments are nonstationary. Changes in practice patterns, patient demographics, measurement protocols, or documentation standards can induce distribution drift that degrades model reliability.

Outcome Drift and Label Stability

Outcome definitions may evolve due to changes in coding practices or clinical guidelines. Such label drift can invalidate reward signals and undermine confidence estimates.

Policy Behavior Auditing

Governance requires auditing policy behavior itself, including exploration rates, arm elimination events, confidence bound widths, and responsiveness to new evidence.

Safeguards and Intervention Thresholds

Operational deployment should define explicit thresholds for human intervention, including policy suspension, rollback to static deployment, or retraining of component models.

Feedback Loops and Documentation

Monitoring outputs should be logged, documented, and reviewed as part of routine AI governance processes. All changes should be version-controlled and auditable.

Governance Versus Experimentation

This framework should not be conflated with online clinical experimentation.

All candidate models are assumed to be independently validated and clinically acceptable prior to deployment. The bandit policy governs model selection among approved options, not patient treatment assignment.

Exploration is constrained, safety-aware, and bounded by audit-informed penalties. Inferior options are eliminated with statistical confidence, minimizing exposure over time.

The appropriate question is not whether adaptive deployment constitutes experimentation, but whether static deployment in the presence of known risks is ethically defensible.

Limitations and Assumptions

This repository implements a governance framework for adaptive clinical AI deployment. Its conclusions and guarantees are subject to the following limitations.

Simulation-Based Evaluation

All reference results are derived from retrospective simulation using deidentified clinical data. Simulation cannot fully capture real-world workflows or clinician behavior and is intended as pre-deployment stress testing, not evidence of clinical effectiveness.

Dependence on Prevalidated Models

The framework assumes candidate models are independently developed, validated, and calibrated. It does not correct for fundamentally unsafe or poorly specified models.

Reward Specification and Normative Choices

Reward functions encode normative institutional judgments about cost and harm. Mis-specification may lead to undesirable behavior and requires careful governance.

Context Representation

Omitted variables, delayed measurements, or context drift may degrade performance or bias deployment decisions.

Delayed and Noisy Outcomes

Extreme delays, missing outcomes, or measurement error may impair learning and increase uncertainty.

Statistical Guarantees and Practical Validity

Statistical confidence does not equate to clinical safety. Guarantees apply only under stated assumptions.

Generalizability

Results obtained using MIMIC-IV may not generalize across institutions or populations.

Governance Is Not Automation

This framework supports adaptive control but does not replace human accountability, clinical oversight, or regulatory compliance.

License

This project is licensed under the Apache License 2.0, permitting reuse and extension for research, policy, and commercial applications with appropriate attribution.

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Dataset](https://img.shields.io/badge/dataset-MIMIC--IV-orange.svg)](https://physionet.org/content/mimiciv/)
[![Reproducibility](https://img.shields.io/badge/reproducibility-simulation--based-green.svg)](#reproducibility-and-ethical-use)

