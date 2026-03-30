# Vol 13 Bootstrap Specification
## Spatial Epidemiology: Surveillance, Disease Modelling & Health Intelligence

### Overview

Volume 13 builds the surveillance, modelling, and intelligence layer on top of
the geographic and causal foundations from Vols 10–12. It addresses three
complementary operational needs: *detecting* outbreaks in real time, *modelling*
epidemic dynamics and spatial spread, and *stratifying* populations for targeted
health interventions.

---

### Package 1: SurveillanceSystems.jl

**Scope**: CUSUM, EWMA, Farrington, CDC EARS, Temporal Scan, ensemble alerting

#### CUSUM (Page 1954)
- One-sided: `S_t = max(0, S_{t-1} + x_t - μ₀ - k)`
- Two-sided: tracks both upper and lower deviations
- Reset variant: resets S to 0 after each alert (successive outbreak detection)
- Hawkins-Olwell default: `h = 5σ₀`, `k = σ₀/2`

#### EWMA (Roberts 1959)
- `Z_t = λx_t + (1-λ)Z_{t-1}`, `Z_0 = μ₀`
- Asymptotic control limits + warm-up adjustment
- λ ∈ (0,1]; L = control limit width

#### Farrington (1996)
- Quasi-Poisson log-linear regression on baseline weeks
- Overdispersion φ from Pearson χ²
- Upper threshold: `μ̂ · exp(z_{1-α} · √(φ/μ̂))`

#### CDC EARS (Hutwagner 2003)
- C1: no lag; C2: g-day lag; C3: rolling 3-day C2 sum
- Default threshold: 3 SD units

#### Temporal Scan (Kulldorff 1997)
- Poisson LLR over all windows of length ≤ max_window
- Monte Carlo p-value (199–999 simulations)
- Prospective variant: cluster ends fixed at T

#### API
```julia
cusum(x; μ₀, σ₀, k, h, two_sided) -> CUSUMResult
cusum_reset(x; μ₀, σ₀, k, h) -> CUSUMResult
ewma(x; λ, L, μ₀, σ₀) -> EWMAResult
farrington(x; baseline_weeks, alpha) -> FarringtonResult
ears(x; baseline_days, lag, threshold) -> EARSResult
temporal_scan(x; max_window, n_sim, rng) -> TemporalScanResult
prospective_scan(x; window, n_sim, rng) -> NamedTuple
combine_alerts(results...) -> Vector{Bool}
sensitivity_specificity(alerts, truth) -> NamedTuple
calibrate_threshold(x, truth; method, alpha) -> NamedTuple
```

---

### Package 2: InfectiousDisease.jl

**Scope**: SIR, SEIR, stochastic SIR, spatial patch model, R₀ estimation

#### SIR (Kermack & McKendrick 1927)
- ODE: S' = -βSI/N, I' = βSI/N - γI, R' = γI
- Euler (1st order) and RK4 (4th order)
- Conservation: S+I+R = N enforced by renormalisation

#### SEIR
- Adds exposed compartment E; σ = 1/incubation_period
- RK4 integration

#### Stochastic SIR (τ-leaping)
- Poisson increments for infection and recovery events
- Captures fade-out probability for small populations

#### Spatial SIR (patch model)
- n-patch coupled ODEs
- Gravity matrix: M_{ij} ∝ N_i·N_j/d²_{ij}
- Row-normalised to coupling_strength parameter

#### R₀ estimation
- From growth rate r: R₀ = (γ+r)/γ (Wallinga & Lipsitch 2007)
- From final attack rate: solve 1-A = exp(-R₀·A) via Newton
- From parameters: R₀ = β/γ

#### API
```julia
sir(N, I₀, β, γ; t_end, dt, method) -> SIRResult
seir(N, E₀, I₀, β, σ, γ; t_end, dt) -> SEIRResult
sir_stochastic(N, I₀, β, γ; t_end, dt, rng) -> SIRResult
spatial_sir(N, I₀, coords, β, γ; coupling_strength, gravity, t_end, dt) -> SpatialSIRResult
r0_from_growth(I_series; γ, dt, n_early) -> NamedTuple
r0_from_sir(S_end, N) -> NamedTuple
herd_immunity_threshold(R₀) -> Float64
effective_r0(R₀, p_immune) -> Float64
attack_rate_prediction(R₀) -> Float64
doubling_time(r) -> Float64
estimate_serial_interval(si; n_boot, rng) -> NamedTuple
```

---

### Package 3: HealthIntelligence.jl

**Scope**: Risk scoring, HNI, anomaly detection, segmentation, predictive risk

#### Composite Risk Score
- Z-standardise each domain; weighted sum; quantile bands

#### Health Needs Index
- Three domains: access + deprivation + burden
- Rescaled to [0,100]; ranked

#### Risk-Adjusted Outcomes
- Unit-level SMR = O/E; Byar 95% CI
- High/low outlier flagging

#### LOF (Breunig et al. 2000)
- k-distance; reachability distance; local reachability density
- LOF > threshold → outlier

#### Isolation Forest (Liu et al. 2008)
- n_trees random isolation trees on subsamples
- Anomaly score = 2^(-E[path]/c(n))

#### k-Means
- Lloyd's algorithm; k-means++ initialisation
- Silhouette coefficient for cluster quality

#### Predictive Risk (Logistic)
- L2-regularised IRLS; C-statistic; Brier score; calibration slope

#### API
```julia
composite_risk_score(X; weights, n_bands) -> RiskScoreResult
health_needs_index(access, deprivation, burden; weights) -> HealthNeedsIndex
risk_adjusted_outcomes(observed, expected) -> NamedTuple
lof(X; k, threshold) -> LOFResult
isolation_forest(X; n_trees, subsample, threshold, rng) -> IForestResult
health_event_anomaly(events, baseline; threshold_sd) -> NamedTuple
kmeans(X, k; max_iter, n_restarts, rng) -> KMeansResult
predictive_risk(X, y; λ, max_iter) -> PredictiveRiskResult
```

---

### Integration Test Requirements

1. **SIR → Surveillance**: epidemic incidence time series fed to CUSUM/EWMA
2. **Spatial SIR → Risk Scoring**: attack rates per patch fed to composite scorer
3. **Surveillance → Anomaly**: alert counts across counties as features for IForest
4. **End-to-end ND**: 5-region spatial epidemic → surveillance → R₀ estimation → HNI

---

### ND Context

- **Population**: 779,261 (5 regions); 53 counties for intelligence
- **Epidemic scenario**: ILI β=0.35, γ=0.10 (R₀=3.5), seed in Northwest
- **Surveillance**: 104 weeks of weekly ILI counts; two outbreak events
- **Intelligence**: 5 health domains; 53 counties; $12M intervention budget
