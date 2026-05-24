# Geo-Julia Architecture

## System Overview

Geo-Julia is a modular healthcare geospatial analytics platform organized into
14 volumes. Each volume is a self-contained package group focused on a specific
analytical domain. The `unified/` workspace brings all volumes together into a
single composable API.

```
┌─────────────────────────────────────────────────────────────┐
│                    unified/GeoJulia.jl                       │
│         Single entry point: `using GeoJulia`                │
├─────────────────────────────────────────────────────────────┤
│  Epidemiology │ Geostat │ SurvivalTS │ Causal │ Optimization│
│  (Vol 13)     │(Vol 10) │ (Vol 9)    │(Vol 11)│ (Vol 12)    │
├───────────────┼─────────┼────────────┼────────┼─────────────┤
│  DeepBayes    │ Equity  │ Inference  │   ML   │             │
│  (Vol 7)      │(Vol 8)  │ (Vol 6)    │(Vol 5) │             │
├─────────────────────────────────────────────────────────────┤
│            SciML Ecosystem Foundation                        │
│  DiffEq · Flux · Turing · GeoStats · JuMP · Graphs · GLM   │
├─────────────────────────────────────────────────────────────┤
│         Julia stdlib: LinearAlgebra · Statistics · Random    │
└─────────────────────────────────────────────────────────────┘
```

## Volume Dependency Graph

```
Vol 13 (Epidemiology) ──uses──→ OrdinaryDiffEq, Distributions
Vol 12 (Optimization)  ──uses──→ JuMP, HiGHS
Vol 11 (Causal)        ──uses──→ GLM, NearestNeighbors, Optim
Vol 10 (Geostatistics) ──uses──→ GeoStats, Variography, Clustering, KernelDensity
Vol 9  (Survival/TS)   ──uses──→ Survival, OrdinaryDiffEq, Graphs, StateSpaceModels
Vol 8  (Equity)        ──uses──→ Distances, Optim, NearestNeighbors
Vol 7  (Deep/Bayes)    ──uses──→ Flux, Zygote, Turing, MCMCChains
Vol 6  (Inference)     ──uses──→ AbstractGPs, KernelFunctions, Optim
Vol 5  (ML)            ──uses──→ DecisionTree, Graphs, SimpleWeightedGraphs
```

**No volume depends on another volume.** They compose via the unified layer.

## Package Index

| Volume | Package | Purpose | Key Functions |
|--------|---------|---------|---------------|
| 5 | HealthcareML | Decision trees, RF, GBM, SHAP | `fit!`, `predict`, `cross_validate`, `shap_values` |
| 5 | NetworkHealth | Healthcare referral networks | `betweenness_centrality`, `pagerank`, `louvain_communities` |
| 5 | TemporalHealth | STL, ARIMA, changepoints | `stl_decompose`, `arima_fit`, `detect_changepoints` |
| 6 | CausalHealth | DiD, IV, RDD, synth control | `did_estimate`, `iv_2sls`, `rd_estimate`, `synthetic_control` |
| 6 | GaussianProcessHealth | GP regression, sparse GP | `gp_fit`, `gp_predict`, `optimize_hyperparams!` |
| 7 | DeepHealth | Neural networks, training | `build_mlp`, `train!`, `predict_access`, `alert_sepsis` |
| 7 | BayesianHealth | MCMC, VI, model comparison | `sample_chains`, `vi_fit`, `waic`, `bayes_factor` |
| 8 | SpatialRegression | GWR, spatial lag/error | `gwr_fit`, `spatial_lag_fit`, `spatial_error_fit` |
| 8 | HealthEquity | Fairness, disparities | `fairness_audit`, `gini_coefficient`, `oaxaca_blinder` |
| 8 | ConformalHealth | Conformal prediction, CQR | `conformal_fit`, `conformal_predict`, `cqr_fit` |
| 9 | SurvivalAnalysis | Cox, KM, competing risks | `kaplan_meier`, `cox_fit`, `parametric_fit` |
| 9 | NetworkHealth | Epidemic networks, SIR | `build_graph`, `sir_model`, `dijkstra`, `pagerank` |
| 9 | TimeSeriesHealth | ARIMA, Kalman, outbreak | `arima_fit`, `auto_arima`, `dlm_fit`, `cusum_detect` |
| 10 | GeostatHealth | Kriging, variograms | `empirical_variogram`, `ordinary_kriging`, `sgs_simulate` |
| 10 | PointPatterns | KDE, Ripley's K, DBSCAN | `kde2d`, `ripley_k`, `dbscan`, `knox_test` |
| 10 | DiseaseMapping | SMR, BYM, spatial scan | `smr`, `bym_fit`, `eb_smooth`, `spatial_scan` |
| 11 | CausalInference | PSM, IPW, AIPW | `ps_fit`, `ipw_ate`, `aipw_ate`, `nn_match` |
| 11 | PolicyEval | DiD, RDD, synth control | `did_2x2`, `rdd_fit`, `synth_control` |
| 11 | SpatialCausal | Spatial DiD, Conley SEs | `spatial_did`, `conley_se`, `geo_iv_2sls` |
| 12 | FacilityLocation | p-median, MCLP, set cover | `p_median`, `mclp`, `set_cover`, `cap_flp` |
| 12 | HealthRouting | TSP, VRP, MEXCLP | `tsp_nn`, `vrp_cw`, `mexclp` |
| 12 | ResourceAllocation | IP, MDP, stochastic prog | `bip_branch_bound`, `value_iteration`, `two_stage_sp` |
| 13 | InfectiousDisease | SIR/SEIR/spatial ODE | `sir`, `seir`, `spatial_sir`, `r0_from_params` |
| 13 | SurveillanceSystems | CUSUM, EWMA, Farrington | `cusum`, `ewma`, `farrington`, `temporal_scan` |
| 13 | HealthIntelligence | Risk scores, anomaly, HNI | `composite_risk_score`, `health_needs_index`, `lof` |

## Use-Case Scenarios

### Disease Surveillance Pipeline
```
InfectiousDisease → SurveillanceSystems → GeostatHealth → TimeSeriesHealth → PolicyEval
```
Model disease spread, detect outbreaks, map spatial risk, forecast trajectory, evaluate interventions.

### Healthcare Access Analysis
```
HealthcareML → SpatialRegression → HealthEquity → FacilityLocation → HealthRouting
```
Predict access barriers, model geographic variation, audit equity, optimize facility placement, route patients.

### Clinical Trial Evaluation
```
SurvivalAnalysis → CausalInference → ConformalHealth → BayesianHealth
```
Survival curves, causal effects, uncertainty quantification, Bayesian model comparison.

### Rural Health Network Analysis
```
NetworkHealth → GaussianProcessHealth → DiseaseMapping → ResourceAllocation
```
Map referral networks, predict spatial patterns, identify hotspots, allocate resources.

## Running the Unified Workspace

```bash
cd unified
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. examples/pandemic_response_pipeline.jl
julia --project=. test/integration_test.jl
```

Or in Julia REPL:
```julia
using GeoJulia

# All 26 packages available through submodules:
GeoJulia.Epidemiology.sir(100000, 10, 0.3, 0.1)
GeoJulia.Geostat.ordinary_kriging(z, coords, vm)
GeoJulia.Causal.did_2x2(y, treat, post)

# Or use top-level re-exports:
result = sir(100000, 10, 0.3, 0.1)
```

## Technology Stack

| Layer | Technology |
|-------|-----------|
| Language | Julia 1.10+ |
| ODE/SDE | DifferentialEquations.jl (SciML) |
| Neural Networks | Flux.jl + Zygote.jl |
| Bayesian | Turing.jl + MCMCChains |
| Geostatistics | GeoStats.jl + Variography |
| Optimization | JuMP.jl + HiGHS |
| Graphs | Graphs.jl |
| Time Series | StateSpaceModels.jl |
| Statistics | GLM.jl, Survival.jl, Distributions.jl |
| ML | DecisionTree.jl, KernelFunctions.jl |
| Web UI | Genie.jl + Stipple + Vue.js |
| Deployment | Docker + Kubernetes + GitHub Actions |
