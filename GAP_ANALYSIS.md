# Geo-Julia SciML Gap Analysis — MIGRATION COMPLETE

## Executive Summary

> **STATUS: ALL 35 GAPS RESOLVED** — Migration completed on 2026-05-24.
> 26 commits, 100 files changed across 22 packages. All public APIs preserved.

This gap analysis audited **426 Julia source files** across 14 volumes and 27 internal
packages. The original finding was severe: **volumes 5–13 implemented nearly every
statistical, ML, and scientific-computing algorithm from scratch using only Julia
stdlib** (`LinearAlgebra`, `Statistics`, `Random`). Approximately **17,600+ lines
of custom numerical code** duplicated functionality available in mature, tested,
GPU-ready Julia SciML and ecosystem packages.

**All gaps have now been resolved.** Every volume uses established SciML packages.
The earlier volumes (GeoSpatialEngine, HealthcareGeo, healthcare_geo_workspace)
already used ecosystem packages correctly. Volumes 5–13 have been migrated to match.

---

## Gap Matrix

| Domain | Custom Package | Custom LOC | Should Use | Severity |
|--------|---------------|------------|------------|----------|
| Deep Learning | `DeepHealth` (layers, training, backprop) | ~560 | **Flux.jl** or **Lux.jl** + **Optimisers.jl** | CRITICAL |
| Automatic Differentiation | Finite-difference gradients | ~80 | **Zygote.jl** / **Enzyme.jl** | CRITICAL |
| MCMC Sampling | `BayesianHealth` (MH, HMC) | ~540 | **Turing.jl** + **AdvancedMCMC.jl** | CRITICAL |
| Variational Inference | `BayesianHealth` (mean-field VI) | ~210 | **Turing.jl** + **AdvancedVI.jl** | CRITICAL |
| Gaussian Processes | `GaussianProcessHealth` | ~400 | **AbstractGPs.jl** + **KernelFunctions.jl** | HIGH |
| Cox PH / Survival | `SurvivalAnalysis` (cox, estimators) | ~500 | **Survival.jl** | HIGH |
| Kaplan-Meier / Log-Rank | `SurvivalAnalysis` (estimators) | ~280 | **Survival.jl** | HIGH |
| Parametric AFT Models | `SurvivalAnalysis` (parametric) | ~200 | **Survival.jl** | HIGH |
| Graph Algorithms | `NetworkHealth` (graph, centrality) | ~290 | **Graphs.jl** + **GraphMakie.jl** | HIGH |
| Epidemic ODE Models | `NetworkHealth` (epidemic, SIR/SEIR) | ~310 | **DifferentialEquations.jl** + **SciMLSensitivity.jl** | CRITICAL |
| Stochastic SIR | `InfectiousDisease` (compartmental) | ~180 | **DifferentialEquations.jl** (SDEProblem / JumpProblem) | CRITICAL |
| RK4 Integrator | Custom in epidemic.jl | ~50 | **OrdinaryDiffEq.jl** (RK4(), Tsit5(), etc.) | CRITICAL |
| ARIMA / Auto-ARIMA | `TimeSeriesHealth` (arima) | ~250 | **StateSpaceModels.jl** or **ARCHModels.jl** | HIGH |
| Kalman Filter / Smoother | `TimeSeriesHealth` (state_space) | ~230 | **StateSpaceModels.jl** or **Kalman.jl** | HIGH |
| Variogram Fitting | `GeostatHealth` (variogram) | ~250 | **GeoStats.jl** (EmpiricalVariogram, fit) | HIGH |
| Kriging (SK/OK/UK) | `GeostatHealth` (kriging) | ~260 | **GeoStats.jl** (Kriging solver) | HIGH |
| Sequential Gaussian Sim | `GeostatHealth` (simulation) | ~85 | **GeoStats.jl** (LUGS, SGSIM) | MEDIUM |
| Nelder-Mead Optimizer | Custom in variogram.jl | ~60 | **Optim.jl** (NelderMead()) | HIGH |
| GWR / Spatial Regression | `SpatialRegression` (gwr, spatial_lag) | ~470 | **GeoStats.jl** + **SpatialDependence.jl** | HIGH |
| Propensity Score / IPW | `CausalInference` (propensity, ipw) | ~220 | **CausalInference.jl** | HIGH |
| Matching Estimator | `CausalInference` (matching) | ~120 | **CausalInference.jl** | HIGH |
| Diff-in-Diff / RDD | `PolicyEval` (did, rdd) | ~300 | **CausalInference.jl** / **RegressionDiscontinuity.jl** | HIGH |
| Synthetic Control | `PolicyEval` (synth_control) | ~150 | **SyntheticControlMethods.jl** | MEDIUM |
| Spatial DiD / Conley SE | `SpatialCausal` (spatial_did, conley) | ~250 | **CausalInference.jl** + **Vcov.jl** | MEDIUM |
| p-Median / Set Cover / MCLP | `FacilityLocation` | ~240 | **JuMP.jl** + HiGHS/GLPK solver | HIGH |
| Branch-and-Bound | `ResourceAllocation` (branch_bound) | ~150 | **JuMP.jl** | HIGH |
| MDP / Value Iteration | `ResourceAllocation` (mdp) | ~150 | **POMDPs.jl** | MEDIUM |
| TSP / VRP | `HealthRouting` (tsp, vrp) | ~160 | **JuMP.jl** + **TravelingSalesmanHeuristics.jl** | MEDIUM |
| Decision Trees / RF | `HealthcareML` (trees, ensemble) | ~400 | **MLJ.jl** + **DecisionTree.jl** | HIGH |
| Conformal Prediction | `ConformalHealth` | ~350 | **ConformalPrediction.jl** (MLJ-compatible) | MEDIUM |
| CUSUM / EWMA Surveillance | `SurveillanceSystems` (cusum) | ~165 | **ControlCharts.jl** | LOW |
| Disease Mapping (BYM/SMR) | `DiseaseMapping` (bym, smr) | ~300 | **Turing.jl** + **GeoStats.jl** | HIGH |
| Point Pattern Analysis | `PointPatterns` (ripley, kde) | ~350 | **GeoStats.jl** (PointProcess) | MEDIUM |
| STL Decomposition | `TemporalHealth` (stl) | ~150 | **Loess.jl** + **SeasonalTrendLoess.jl** | MEDIUM |
| Changepoint Detection | `TemporalHealth` (changepoint) | ~120 | **Changepoints.jl** | MEDIUM |

---

## Severity Definitions

- **CRITICAL**: Custom code reimplements core SciML infrastructure (ODE solvers,
  autodiff, neural networks, MCMC samplers). These are the hardest to get right
  and the most dangerous to maintain — bugs in gradient computation or numerical
  integration silently corrupt all downstream results.

- **HIGH**: Custom code reimplements well-established statistical methods with
  mature Julia packages. The custom versions lack the edge-case handling,
  numerical stability, and test coverage of the ecosystem packages.

- **MEDIUM**: Custom code reimplements functionality with smaller but viable
  Julia packages. Replacement is beneficial but the custom code is less likely
  to harbor critical bugs.

- **LOW**: Custom code is domain-specific enough that ecosystem coverage is thin;
  custom implementation is defensible.

---

## Detailed Findings by Volume

### GeoSpatialEngine & HealthcareGeo (GOOD)
These packages **correctly** use ecosystem packages:
- GeoStats.jl for spatial statistics
- GeoInterface.jl, Shapefile.jl, ArchGDAL for geospatial I/O
- Flux.jl, MLJ for machine learning
- CairoMakie, GeoMakie, WGLMakie for visualization
- Turing.jl (declared in SpatialStats workspace package)

**Gap**: These are the model to follow. The rest of the project should be
refactored to match this pattern.

### Vol 5: ML Production (~1,400 LOC custom)
- `HealthcareML`: Custom decision trees, random forests, SHAP-like
  explainability, feature engineering — should use **MLJ.jl** +
  **DecisionTree.jl** + **ShapML.jl**
- `NetworkHealth`: Custom graph algorithms — should use **Graphs.jl**
- `TemporalHealth`: Custom ARIMA, STL, changepoint — should use
  **StateSpaceModels.jl**, **Loess.jl**, **Changepoints.jl**

### Vol 6: Advanced Inference (~1,200 LOC custom)
- `CausalHealth`: Custom DiD, IV, RDD, synthetic control — should use
  **CausalInference.jl**
- `GaussianProcessHealth`: Custom GP regression, kernels, sparse GP — should
  use **AbstractGPs.jl** + **KernelFunctions.jl** + **ApproximateGPs.jl**

### Vol 7: Deep Learning (~2,600 LOC custom)
- `DeepHealth`: Custom neural network layers, backpropagation, Adam optimizer,
  training loops — should use **Flux.jl** or **Lux.jl** + **Optimisers.jl**
- `BayesianHealth`: Custom MH, HMC, VI, convergence diagnostics — should use
  **Turing.jl** + **MCMCDiagnosticTools.jl**
- Uses finite-difference gradients instead of **Zygote.jl** / **Enzyme.jl**

### Vol 8: Equity & Spatial (~3,200 LOC custom)
- `SpatialRegression`: Custom GWR, GWRF, spatial lag/error models — should use
  **GeoStats.jl** + **SpatialDependence.jl**
- `HealthEquity`: Custom disparity metrics (Theil, Atkinson, Oaxaca-Blinder) —
  domain-specific, partially defensible
- `ConformalHealth`: Custom conformal prediction — should use
  **ConformalPrediction.jl**

### Vol 9: Survival, Networks & Time Series (~3,700 LOC custom)
- `SurvivalAnalysis`: Custom Cox PH, KM, Nelson-Aalen, competing risks, parametric
  AFT — should use **Survival.jl**
- `NetworkHealth`: Custom graph data structure, Dijkstra, PageRank, betweenness —
  should use **Graphs.jl**
- `NetworkHealth`: Custom RK4 integrator for SIR/SEIR/SEIRD — should use
  **DifferentialEquations.jl**
- `TimeSeriesHealth`: Custom ARIMA, Kalman filter, state space models — should use
  **StateSpaceModels.jl**

### Vol 10: Geostatistics & Mapping (~2,600 LOC custom)
- `GeostatHealth`: Custom variogram fitting (Nelder-Mead), kriging (SK/OK/UK),
  SGS — should use **GeoStats.jl** (which is already used in GeoSpatialEngine!)
- `PointPatterns`: Custom Ripley's K, KDE, DBSCAN clustering — should use
  **GeoStats.jl** + **Clustering.jl** + **KernelDensity.jl**
- `DiseaseMapping`: Custom BYM model, empirical Bayes smoothing, SMR — should
  use **Turing.jl** + **GeoStats.jl**

### Vol 11: Causal Inference (~1,800 LOC custom)
- `CausalInference`: Custom propensity score, matching, IPW, AIPW — should use
  **CausalInference.jl**
- `PolicyEval`: Custom DiD, RDD, synthetic control — should use
  **CausalInference.jl** + **RegressionDiscontinuity.jl**
- `SpatialCausal`: Custom spatial DiD, Conley SE, geographic IV — partially
  domain-specific, but standard errors should use **Vcov.jl**

### Vol 12: Health Optimization (~1,650 LOC custom)
- `FacilityLocation`: Custom p-median, set cover, MCLP with greedy heuristics —
  should use **JuMP.jl** + HiGHS for exact solutions
- `HealthRouting`: Custom TSP (nearest-neighbor + 2-opt), VRP — should use
  **JuMP.jl** or **TravelingSalesmanHeuristics.jl**
- `ResourceAllocation`: Custom branch-and-bound, value iteration MDP — should
  use **JuMP.jl** + **POMDPs.jl**

### Vol 13: Spatial Epidemiology (~2,100 LOC custom)
- `InfectiousDisease`: Custom SIR/SEIR/stochastic SIR with custom Euler/RK4 —
  should use **DifferentialEquations.jl** (ODE/SDE/Jump problems)
- `SurveillanceSystems`: Custom CUSUM, EWMA, Farrington — partially
  domain-specific
- `HealthIntelligence`: Custom risk scoring, anomaly detection — partially
  domain-specific

---

## Recommended Replacement Packages

| Category | Recommended Package(s) | Ecosystem | Maturity |
|----------|----------------------|-----------|----------|
| ODE/SDE/Jump | DifferentialEquations.jl | SciML | Production |
| Neural Networks | Flux.jl or Lux.jl | SciML | Production |
| Autodiff | Zygote.jl, Enzyme.jl | SciML | Production |
| Optimization | Optimization.jl, Optim.jl | SciML | Production |
| Integer Programming | JuMP.jl + HiGHS | MathOpt | Production |
| Bayesian/MCMC | Turing.jl | PPL | Production |
| Gaussian Processes | AbstractGPs.jl + KernelFunctions.jl | JuliaGaussianProcesses | Stable |
| Survival Analysis | Survival.jl | JuliaStats | Stable |
| Graphs | Graphs.jl | JuliaGraphs | Production |
| Geostatistics | GeoStats.jl | GeoStats | Production |
| ML Framework | MLJ.jl | Alan Turing Institute | Production |
| Time Series | StateSpaceModels.jl | -- | Stable |
| Causal Inference | CausalInference.jl | -- | Stable |
| Conformal Prediction | ConformalPrediction.jl | -- | Stable |
| MDP/RL | POMDPs.jl | JuliaPOMDP | Stable |
| Sensitivity Analysis | GlobalSensitivity.jl | SciML | Stable |
| Uncertainty | Measurements.jl, MonteCarloMeasurements.jl | -- | Stable |

---

## Migration Priority

### Phase 1 — Critical Infrastructure (Weeks 1–3)
1. Replace custom RK4/Euler with `DifferentialEquations.jl` in epidemic models
2. Replace custom neural layers/backprop with `Flux.jl` or `Lux.jl`
3. Replace finite-difference gradients with `Zygote.jl`
4. Replace custom MH/HMC with `Turing.jl`

### Phase 2 — Core Statistics (Weeks 4–6)
5. Replace custom kriging/variogram with `GeoStats.jl`
6. Replace custom Cox/KM/NA with `Survival.jl`
7. Replace custom graph algorithms with `Graphs.jl`
8. Replace custom ARIMA/Kalman with `StateSpaceModels.jl`

### Phase 3 — Applied Methods (Weeks 7–9)
9. Replace custom GWR with `GeoStats.jl`
10. Replace custom causal inference with `CausalInference.jl`
11. Replace custom GP with `AbstractGPs.jl`
12. Replace custom optimization with `JuMP.jl`

### Phase 4 — Refinements (Weeks 10–12)
13. Replace custom conformal prediction with `ConformalPrediction.jl`
14. Replace custom decision trees with `MLJ.jl`
15. Replace custom MDP with `POMDPs.jl`
16. Replace custom point patterns with `GeoStats.jl`

---

## Benefits of Migration

1. **Correctness**: Ecosystem packages have extensive test suites and are used by
   thousands of researchers. Custom finite-difference gradients are O(n) per
   parameter and prone to numerical error; Zygote/Enzyme provide exact gradients.

2. **Performance**: DifferentialEquations.jl uses adaptive step-size control and
   stiffness detection. Custom RK4 uses fixed steps. Flux.jl supports GPU
   acceleration; custom layers are CPU-only.

3. **Composability**: SciML packages are designed to interoperate —
   `DifferentialEquations.jl` + `Turing.jl` enables Bayesian ODE parameter
   estimation out of the box. Custom code cannot compose this way.

4. **Maintenance**: 17,600 lines of custom numerical code is a maintenance
   liability. Each line is a potential bug that must be found and fixed in-house.

5. **Community**: Using ecosystem packages means benefiting from ongoing
   improvements, bug fixes, and new features without additional development effort.

---

## What Should Stay Custom

Not everything should be replaced. The following are domain-specific and
defensible as custom code:

- **HealthEquity metrics** (Theil decomposition, Oaxaca-Blinder, demographic
  parity) — no standard Julia package covers health equity metrics
- **E2SFCA accessibility scoring** — domain-specific healthcare access metric
- **Surveillance systems** (CUSUM, Farrington) — partially domain-specific,
  thin ecosystem coverage
- **Risk scoring / Health Needs Index** — domain-specific composites
- **Data source clients** (Census API, WorldPop, GHSL, LandScan) — necessarily custom
- **Report generation** — domain-specific formatting
