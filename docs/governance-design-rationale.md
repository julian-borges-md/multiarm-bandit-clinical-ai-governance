# Governance design rationale

## Why model selection is treated as a governance decision

Health systems increasingly hold several validated models for the same prediction task. Choosing which one to run for a given patient determines accuracy, cost and the distribution of errors across subgroups, yet the choice is usually made once, from retrospective validation metrics, and never revisited. This framework separates two accountabilities: model developers own the frozen predictive models; an institutional governance layer owns the deployment policy, the weights that encode cost and safety priorities, and the evidence threshold at which a model is retired. Nothing in the governance layer updates a model.

## Why a fixed confidence formulation

Regret minimising bandits trade exploration for reward and keep exploring indefinitely. A governance body usually asks a different question: at what point is the evidence sufficient to retire a model with a stated error probability. That is best arm identification in the fixed confidence setting. The elimination rule removes an arm only when its upper confidence bound lies below another arm's lower bound, with radii valid for every sample size and every arm, so the chance of wrongly retiring the best model is bounded by delta. The price is sample complexity: the number of outcomes needed scales with the inverse square of the reward gap. The repository reports that number explicitly (`outputs/results/implied_sample_complexity.csv`) so that an institution can plan the horizon a decision needs, rather than discovering it after the fact.

## Why the reward has three terms

Predictive quality alone cannot rank models for deployment. The composite reward adds a normalised operational cost (laboratory acquisition and computation that an arm requires) and a safety penalty for the error the institution considers most harmful (a missed death at the operating threshold). The weights are governance parameters: they are chosen by oversight bodies, documented in `config/params.yml`, and varied in sensitivity analyses. Under the primary weights the cheapest adequate model is preferred; under zero cost weight the most accurate one is. The framework makes that tradeoff explicit instead of leaving it implicit in a leaderboard.

## Why delayed feedback is modelled

In hospital mortality is known hours to days after a prediction. A policy that updates on outcomes it could not yet know would overstate what adaptive deployment can achieve. The simulator keeps a feedback queue indexed by availability time and asserts that no outcome is used early.

## Why the deployment stream is temporally external

Models are frozen on admissions from 2008 to 2019 and deployed on admissions from 2020 to 2022. Performance drift between these periods is part of what a governance layer must manage, so the evaluation includes it rather than averaging it away with a random split.

## What the framework does not do

It does not retrain or recalibrate models, does not address concept drift inside a model, and does not make clinical recommendations. It evaluates deployment behaviour in simulation, which is the ethical prerequisite for any prospective use.
