#=
Pandemic Response Pipeline — Cross-Volume Composition Example
=============================================================

Demonstrates how Geo-Julia volumes compose into a unified workflow:
  Vol 13 → Epidemic modeling & surveillance
  Vol 10 → Spatial interpolation & disease mapping
  Vol 9  → Time series forecasting & network analysis
  Vol 11 → Causal policy evaluation
  Vol 12 → Facility optimization for response

Scenario: A respiratory illness is spreading through a 50-county region.
We model transmission, detect outbreaks, forecast spread, evaluate
intervention policies, and optimize testing facility placement.
=#

using Random, Statistics, LinearAlgebra

# Load volume packages directly (or use `using GeoJulia` for the unified API)
include("../src/vol13_imports.jl")  # InfectiousDisease, SurveillanceSystems, HealthIntelligence
include("../src/vol10_imports.jl")  # GeostatHealth, DiseaseMapping, PointPatterns
include("../src/vol9_imports.jl")   # SurvivalAnalysis, TimeSeriesHealth, NetworkHealth
include("../src/vol11_imports.jl")  # CausalInference, PolicyEval, SpatialCausal
include("../src/vol12_imports.jl")  # FacilityLocation, HealthRouting, ResourceAllocation

rng = MersenneTwister(42)
println("=" ^ 70)
println("  PANDEMIC RESPONSE PIPELINE — Cross-Volume Integration Demo")
println("=" ^ 70)

# ═══════════════════════════════════════════════════════════════════════
# PHASE 1: Epidemic Modeling (Vol 13 — InfectiousDisease)
# ═══════════════════════════════════════════════════════════════════════
println("\n▶ PHASE 1: Epidemic Modeling (Vol 13)")
println("-" ^ 50)

N = 500_000
sir_result = sir(N, 50, 0.35, 0.12; t_end=300.0, dt=1.0)
seir_result = seir(N, 20, 30, 0.35, 0.2, 0.12; t_end=300.0, dt=1.0)

R0 = r0_from_params(0.35, 0.12)
hit = herd_immunity_threshold(R0)
println("  SIR R₀ = $(round(R0, digits=2)), Herd Immunity Threshold = $(round(hit*100, digits=1))%")
println("  Peak infection: $(round(maximum(sir_result.I)*100, digits=1))% at day $(argmax(sir_result.I))")
println("  Final attack rate: $(round((1 - sir_result.S[end])*100, digits=1))%")

# Stochastic simulation for uncertainty
stoch_result = sir_stochastic(N, 50, 0.35, 0.12; t_end=300.0, dt=1.0, rng=rng)
println("  Stochastic peak: $(round(maximum(stoch_result.I)*100, digits=1))%")

# ═══════════════════════════════════════════════════════════════════════
# PHASE 2: Outbreak Surveillance (Vol 13 — SurveillanceSystems)
# ═══════════════════════════════════════════════════════════════════════
println("\n▶ PHASE 2: Outbreak Surveillance (Vol 13)")
println("-" ^ 50)

# Simulate daily case counts with outbreak starting at day 60
baseline_rate = 15.0
n_days = 180
cases = [rand(rng, round(Int, baseline_rate + (t > 60 ? 3.0 * exp(0.03*(t-60)) : 0))) for t in 1:n_days]
cases = max.(cases, 0)

cusum_r = cusum(Float64.(cases); μ₀=baseline_rate, σ₀=sqrt(baseline_rate), k=1.0, h=5.0)
ewma_r = ewma(Float64.(cases); λ=0.2, L=2.7, μ₀=baseline_rate, σ₀=sqrt(baseline_rate))

first_cusum = findfirst(cusum_r.alerts)
first_ewma = findfirst(ewma_r.alerts)
println("  CUSUM first alert: day $(something(first_cusum, "none"))")
println("  EWMA first alert: day $(something(first_ewma, "none"))")
println("  True outbreak start: day 60")
println("  Detection lag: $(something(first_cusum, 999) - 60) days (CUSUM)")

# ═══════════════════════════════════════════════════════════════════════
# PHASE 3: Spatial Disease Mapping (Vol 10 — GeostatHealth + DiseaseMapping)
# ═══════════════════════════════════════════════════════════════════════
println("\n▶ PHASE 3: Spatial Disease Mapping (Vol 10)")
println("-" ^ 50)

# Simulate 50 counties with observed/expected case counts
n_counties = 50
county_coords = hcat(rand(rng, n_counties) * 200, rand(rng, n_counties) * 150)
expected_cases = rand(rng, 20:80, n_counties)
# Higher risk in eastern quadrant
risk_multiplier = [1.0 + 1.5 * (county_coords[i,1] > 120) for i in 1:n_counties]
observed_cases = [rand(rng, round(Int, expected_cases[i] * risk_multiplier[i])) for i in 1:n_counties]

# SMR computation
smr_results = batch_smr(observed_cases, expected_cases)
high_risk = sum(r.smr > 1.5 for r in smr_results)
println("  Counties with SMR > 1.5: $high_risk / $n_counties")

# Empirical Bayes smoothing
eb_result = eb_smooth(observed_cases, expected_cases)
println("  EB smoothed range: $(round(minimum(eb_result.smoothed), digits=2)) — $(round(maximum(eb_result.smoothed), digits=2))")

# Kriging on smoothed rates
rates = eb_result.smoothed
ev = empirical_variogram(county_coords, rates; n_lags=12)
vm = fit_variogram(ev; model=:spherical)
println("  Variogram: sill=$(round(vm.sill, digits=4)), range=$(round(vm.range, digits=1)), nugget=$(round(vm.nugget, digits=4))")

ok_model = ordinary_kriging(rates, county_coords, vm)
# Predict at 5 new locations
new_locs = hcat(rand(rng, 5) * 200, rand(rng, 5) * 150)
preds, vars = ok_predict(ok_model, new_locs)
println("  Kriging predictions at 5 new sites: $(round.(preds, digits=3))")

# ═══════════════════════════════════════════════════════════════════════
# PHASE 4: Time Series Forecasting (Vol 9 — TimeSeriesHealth)
# ═══════════════════════════════════════════════════════════════════════
println("\n▶ PHASE 4: Time Series Forecasting (Vol 9)")
println("-" ^ 50)

# Fit ARIMA to the case series for forecasting
case_series = Float64.(cases[1:120])  # Use first 120 days
arima_model = auto_arima(case_series; max_p=3, max_q=3)
println("  Best ARIMA: ($(arima_model.p), $(arima_model.d), $(arima_model.q))")
println("  AIC: $(round(arima_model.aic, digits=1))")

# Kalman filter for level estimation
dlm_model = dlm_fit(case_series)
println("  DLM σ²_ε = $(round(dlm_model.σ²_ε, digits=2)), σ²_η = $(round(dlm_model.σ²_η, digits=2))")

# ═══════════════════════════════════════════════════════════════════════
# PHASE 5: Causal Policy Evaluation (Vol 11 — PolicyEval)
# ═══════════════════════════════════════════════════════════════════════
println("\n▶ PHASE 5: Causal Policy Evaluation (Vol 11)")
println("-" ^ 50)

# Simulate a lockdown intervention: 25 counties treated, 25 control
n_units = 50
treat = vcat(ones(25), zeros(25))
post = vcat(ones(50))  # All in post period
# Treatment effect: reduces cases by ~20% + noise
y_pre = rand(rng, 40.0:80.0, n_units)
treatment_effect = -15.0
y_post = y_pre .+ treat .* treatment_effect .+ randn(rng, n_units) .* 5.0
y_all = vcat(y_pre, y_post)
treat_all = vcat(treat, treat)
post_all = vcat(zeros(n_units), ones(n_units))

did_result = did_2x2(y_all, treat_all, post_all; n_boot=200, rng=rng)
println("  DiD estimate (lockdown effect): $(round(did_result.att, digits=2))")
println("  95% CI: [$(round(did_result.ci_lower, digits=2)), $(round(did_result.ci_upper, digits=2))]")
println("  True effect: $(treatment_effect)")

# ═══════════════════════════════════════════════════════════════════════
# PHASE 6: Facility Optimization (Vol 12 — FacilityLocation)
# ═══════════════════════════════════════════════════════════════════════
println("\n▶ PHASE 6: Testing Facility Optimization (Vol 12)")
println("-" ^ 50)

# Place 5 testing sites to minimize population-weighted distance
demand_pts = county_coords
population = Float64.(rand(rng, 5000:50000, n_counties))
candidate_sites = hcat(rand(rng, 20) * 200, rand(rng, 20) * 150)

pmedian_result = p_median(demand_pts, candidate_sites, 5; weights=population, rng=rng)
println("  Optimal 5 facility locations selected")
println("  Objective (weighted distance): $(round(p_median_obj(pmedian_result), digits=1))")
println("  Facilities opened at indices: $(pmedian_result.open_facilities)")

# Coverage analysis
cover_result = set_cover(demand_pts, candidate_sites; coverage_radius=50.0, weights=population)
println("  Minimum facilities for full coverage (r=50km): $(cover_result.n_facilities)")

# ═══════════════════════════════════════════════════════════════════════
# PHASE 7: Risk Stratification (Vol 13 — HealthIntelligence)
# ═══════════════════════════════════════════════════════════════════════
println("\n▶ PHASE 7: Risk Stratification (Vol 13)")
println("-" ^ 50)

# Combine signals into composite risk score
risk_features = hcat(
    eb_result.smoothed,           # Disease burden
    population ./ maximum(population),  # Population density proxy
    [county_coords[i,1] > 120 ? 1.0 : 0.0 for i in 1:n_counties],  # Geographic risk
)
risk_result = composite_risk_score(risk_features; weights=[0.5, 0.3, 0.2], n_bands=4)
println("  Risk bands: $(count(==(1), risk_result.bands)) low, $(count(==(2), risk_result.bands)) medium, $(count(==(3), risk_result.bands)) high, $(count(==(4), risk_result.bands)) very high")

# Health Needs Index
hni = health_needs_index(
    rand(rng, n_counties),  # Access scores
    rand(rng, n_counties),  # Deprivation
    eb_result.smoothed ./ maximum(eb_result.smoothed);  # Disease burden (normalized)
)
println("  Health Needs Index range: $(round(minimum(hni.index), digits=3)) — $(round(maximum(hni.index), digits=3))")

# ═══════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════
println("\n" * "=" ^ 70)
println("  PIPELINE COMPLETE — 7 phases across 5 volumes")
println("=" ^ 70)
println("""
  Volumes Used:
    Vol 13: InfectiousDisease (SIR/SEIR), SurveillanceSystems (CUSUM/EWMA),
            HealthIntelligence (risk scoring)
    Vol 10: GeostatHealth (kriging), DiseaseMapping (SMR, EB smoothing)
    Vol 9:  TimeSeriesHealth (ARIMA, Kalman filter)
    Vol 11: PolicyEval (difference-in-differences)
    Vol 12: FacilityLocation (p-median, set cover)

  Key Results:
    • R₀ = $(round(R0, digits=2)), herd immunity at $(round(hit*100, digits=0))%
    • Outbreak detected $(something(first_cusum, 999) - 60) days after start
    • $(high_risk) high-risk counties identified (SMR > 1.5)
    • Lockdown reduced cases by $(round(abs(did_result.att), digits=1)) (DiD)
    • 5 optimal testing facilities placed (p-median)
    • $(count(==(4), risk_result.bands)) counties in highest risk band
""")
