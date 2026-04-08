# Vol 9 — Survival Analysis, Healthcare Networks & Time-Series Outbreak Detection

## Scope

Three production-ready pure-Julia packages covering the three pillars of
epidemiological time-dynamics:

1. **SurvivalAnalysis.jl** — Kaplan-Meier, Nelson-Aalen, Cox PH, parametric
   AFT (Weibull/Exponential/Log-logistic), competing risks (Fine-Gray)
2. **NetworkHealth.jl** — graph primitives, PageRank, betweenness centrality,
   SIR/SEIR/SEIRD epidemic ODE solver, R₀ estimation, facility network analysis
3. **TimeSeriesHealth.jl** — ARIMA(p,d,q), Kalman filter/smoother (DLM),
   CUSUM outbreak detection, Farrington algorithm, Poisson EWMA, forecast PI

## Package Architecture

### SurvivalAnalysis.jl
- `src/estimators.jl`  — KM, Nelson-Aalen, log-rank & Wilcoxon tests
- `src/cox.jl`         — Cox PH partial likelihood; Newton-Raphson; Breslow
- `src/parametric.jl`  — Weibull/Exponential/Log-logistic MLE; shape/scale CIs
- `src/competing.jl`   — Fine-Gray; cumulative incidence function (CIF)
- `src/report.jl`      — SurvivalReport, median survival table

### NetworkHealth.jl
- `src/graph.jl`           — HealthGraph (adj list + weights); degree, BFS, betweenness, PageRank
- `src/epidemic.jl`        — SIR/SEIR/SEIRD ODE (RK4); R₀; herd immunity threshold
- `src/facility_network.jl`— patient flow matrix; catchment area; referral centrality
- `src/report.jl`          — NetworkReport; epidemic summary

### TimeSeriesHealth.jl
- `src/arima.jl`      — difference operator; Yule-Walker ACF/PACF; MLE ARMA; auto_arima AIC
- `src/state_space.jl`— local-level DLM; Kalman predict/update/smooth; hyperparameter EM
- `src/outbreak.jl`   — CUSUM (Page 1954); Farrington regression (Poisson GLM + Winsorized weights); Poisson EWMA
- `src/forecast.jl`   — h-step ARIMA/DLM forecast; PI bootstrap; rolling cross-validation
- `src/report.jl`     — TimeSeriesReport; outbreak summary table

## Chapters

- **Ch 51** — Survival Analysis: estimating and comparing time-to-event
- **Ch 52** — Healthcare Networks and Epidemic Modelling
- **Ch 53** — Time-Series Forecasting and Outbreak Detection

## Test Counts

- SurvivalAnalysis unit tests:  20 testsets
- NetworkHealth unit tests:     18 testsets
- TimeSeriesHealth unit tests:  20 testsets
- Integration testsets:         20 testsets (+ 4 cross-package)

## Pure-Julia Constraint

No Survival.jl, Graphs.jl, or TimeSeries.jl dependencies. All algorithms
implemented from scratch: partial likelihood, RK4 ODE, Kalman equations,
CUSUM, Farrington Poisson regression.
