# Vol 11 — Causal Inference & Health Policy Evaluation

## Overview

This volume develops pure-Julia tools for causal inference and policy
evaluation in healthcare settings. It covers propensity score methods,
difference-in-differences, synthetic control, regression discontinuity,
and spatial causal inference with geographic instruments.

## Packages

### CausalInference.jl

| Module | Methods |
|--------|---------|
| `propensity.jl` | Logistic PS via Newton-Raphson; trimming; overlap diagnostics |
| `ipw.jl` | Horwitz-Thompson ATE; Hajek ATE; AIPW; overlap weights |
| `matching.jl` | Greedy NN PS matching; caliper; ATT; balance table (SMD) |
| `report.jl` | CausalReport combining all estimators |

### PolicyEval.jl

| Module | Methods |
|--------|---------|
| `did.jl` | 2×2 DiD; event study (TWFE); parallel trends test; staggered DiD |
| `synth_control.jl` | Synthetic control via Frank-Wolfe; RMSPE; placebo inference |
| `rdd.jl` | Local linear/polynomial RDD; IK bandwidth; McCrary density test |
| `report.jl` | PolicyReport combining all estimators |

### SpatialCausal.jl

| Module | Methods |
|--------|---------|
| `spatial_did.jl` | Spatial DiD with treatment radius & spillover buffer zones |
| `conley.jl` | Conley (1999) spatial HAC SE with Bartlett kernel |
| `geo_iv.jl` | Geographic IV (distance instrument); 2SLS; weak instrument test |
| `report.jl` | SpatialCausalReport |

## Key Formulas

### Propensity Score / IPW
- PS: σ(Xβ) estimated via logistic regression Newton-Raphson
- Hajek ATE: μ₁/norm - μ₀/norm with normalisation
- AIPW: E[μ̂₁ - μ̂₀ + D(y-μ̂₁)/e - (1-D)(y-μ̂₀)/(1-e)]
- Overlap: w = e(1-e) optimal weights

### DiD
- 2×2: (Ȳ₁₁-Ȳ₁₀) - (Ȳ₀₁-Ȳ₀₀)
- TWFE event study: unit+time FE within-demeaned OLS
- Staggered: Callaway-Sant'Anna ATT(g,t) aggregation

### Synthetic Control
- Frank-Wolfe: w ← (1-γ)w + γeₛ on probability simplex
- RMSPE ratio: post/pre as placebo inference statistic

### RDD
- Local linear: separate polynomial each side, test intercept jump
- IK bandwidth: h* = (σ²/B²n)^{1/5} from pilot regression

### Spatial Causal
- Spatial DiD: unit/time FE + D·Post + S·Post interactions
- Conley SE: Ω = Σᵢⱼ K(dᵢⱼ/h)·ε̂ᵢε̂ⱼxᵢxⱼ'; sandwich estimator
- 2SLS: D̂ from first stage; β₂SLS from second stage with sandwich SE
