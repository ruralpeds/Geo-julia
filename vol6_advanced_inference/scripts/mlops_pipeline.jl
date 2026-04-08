#!/usr/bin/env julia
# scripts/mlops_pipeline.jl
# MLOps: model registry, drift detection, A/B testing, auto-retraining
# Chapter 46 — Julia Healthcare GIS Textbook, Vol 6
#
# Components:
#   ModelRegistry    — versioned model storage with metadata
#   DriftDetector    — Kolmogorov-Smirnov and Population Stability Index
#   ABTest           — frequentist A/B test for model comparison
#   RetrainingTrigger — automatic retraining on drift detection

using Statistics, Dates, Random, LinearAlgebra

# ── Model Registry ────────────────────────────────────────────────────────────

"""
    ModelRecord

A single versioned model entry in the registry.
"""
struct ModelRecord
    id          ::String
    name        ::String
    version     ::VersionNumber
    created_at  ::DateTime
    metrics     ::Dict{String,Float64}
    params      ::Dict{String,Any}
    tags        ::Vector{String}
    is_champion ::Bool
end

"""
    ModelRegistry

In-memory model registry for tracking trained models.
"""
mutable struct ModelRegistry
    records    ::Vector{ModelRecord}
    champion_id::Union{String,Nothing}
end

ModelRegistry() = ModelRegistry(ModelRecord[], nothing)

"""
    register!(registry, name, version, metrics, params; tags) -> String

Register a model and return its unique ID.
"""
function register!(reg     ::ModelRegistry,
                   name    ::String,
                   version ::VersionNumber,
                   metrics ::Dict{String,Float64},
                   params  ::Dict{String,Any} = Dict();
                   tags    ::Vector{String}    = String[])::String
    id = string(hash((name, version, now())); base=16)[1:8]
    rec = ModelRecord(id, name, version, now(), metrics, params, tags, false)
    push!(reg.records, rec)
    @info "Registered model: $name v$version (id=$id)  RMSE=$(get(metrics, \"rmse\", NaN))"
    id
end

"""
    promote_champion!(registry, model_id)

Promote a model to champion status (replaces current champion).
"""
function promote_champion!(reg::ModelRegistry, model_id::String)
    for (i, r) in enumerate(reg.records)
        reg.records[i] = ModelRecord(r.id, r.name, r.version, r.created_at,
                                      r.metrics, r.params, r.tags,
                                      r.id == model_id)
    end
    reg.champion_id = model_id
    @info "Promoted model $model_id to champion"
end

"""
    get_champion(registry) -> Union{ModelRecord, Nothing}
"""
get_champion(reg::ModelRegistry) = isnothing(reg.champion_id) ? nothing :
    findfirst(r -> r.id == reg.champion_id, reg.records) |>
    i -> isnothing(i) ? nothing : reg.records[i]

"""
    model_leaderboard(registry; metric="rmse", lower_better=true) -> Vector{ModelRecord}

Return models sorted by metric.
"""
function model_leaderboard(reg::ModelRegistry;
                            metric::String = "rmse",
                            lower_better::Bool = true)
    sort(reg.records,
         by = r -> get(r.metrics, metric, lower_better ? Inf : -Inf),
         rev = !lower_better)
end

# ── Data Drift Detection ──────────────────────────────────────────────────────

"""
    DriftResult

Result of a drift detection test.
"""
struct DriftResult
    feature     ::String
    test        ::Symbol     # :ks or :psi
    statistic   ::Float64
    p_value     ::Float64
    psi         ::Float64    # Population Stability Index
    drifted     ::Bool       # true if drift detected
    severity    ::Symbol     # :none, :warning, :critical
end

"""
    ks_test(x_ref, x_new) -> (D, p_value)

Two-sample Kolmogorov-Smirnov test.
D = max|F_ref(x) - F_new(x)|
p-value via asymptotic distribution.
"""
function ks_test(x_ref::AbstractVector{<:Real},
                 x_new::AbstractVector{<:Real})
    n1, n2 = length(x_ref), length(x_new)
    combined = sort(vcat(Float64.(x_ref), Float64.(x_new)))
    # ECDF of each sample
    ecdf_ref = [count(<=(v), x_ref) / n1 for v in combined]
    ecdf_new = [count(<=(v), x_new) / n2 for v in combined]
    D = maximum(abs.(ecdf_ref .- ecdf_new))
    # Asymptotic p-value: Kolmogorov distribution
    c = D * sqrt(n1 * n2 / (n1 + n2))
    # Approximation: p ≈ 2·exp(-2c²)
    p = min(2 * exp(-2 * c^2), 1.0)
    (D=D, p_value=p)
end

"""
    population_stability_index(x_ref, x_new; n_bins=10) -> Float64

PSI = Σᵢ (Expected% - Actual%) · ln(Expected% / Actual%)
PSI < 0.1  → no drift
0.1–0.2    → moderate drift (warning)
PSI > 0.2  → significant drift (critical)
"""
function population_stability_index(x_ref::AbstractVector{<:Real},
                                     x_new::AbstractVector{<:Real};
                                     n_bins::Int = 10)::Float64
    # Use reference distribution to define bins
    edges = quantile(Float64.(x_ref), range(0, 1; length=n_bins+1))
    edges[1]   -= 1e-9
    edges[end] += 1e-9
    psi = 0.0
    for i in 1:n_bins
        exp_frac = count(v -> edges[i] <= v < edges[i+1], x_ref) / length(x_ref)
        act_frac = count(v -> edges[i] <= v < edges[i+1], x_new) / length(x_new)
        exp_frac = max(exp_frac, 1e-6)
        act_frac = max(act_frac, 1e-6)
        psi += (exp_frac - act_frac) * log(exp_frac / act_frac)
    end
    psi
end

"""
    detect_drift(X_ref, X_new; feature_names, alpha) -> Vector{DriftResult}

Run KS + PSI drift detection for each feature.
"""
function detect_drift(X_ref::AbstractMatrix{<:Real},
                      X_new::AbstractMatrix{<:Real};
                      feature_names::Vector{String} = String[],
                      alpha::Float64 = 0.05)::Vector{DriftResult}
    n_feat = size(X_ref, 2)
    fn     = isempty(feature_names) ? ["feature_$i" for i in 1:n_feat] : feature_names
    results = DriftResult[]
    for j in 1:n_feat
        ks = ks_test(X_ref[:, j], X_new[:, j])
        psi = population_stability_index(X_ref[:, j], X_new[:, j])
        drifted = ks.p_value < alpha || psi > 0.1
        severity = psi > 0.2 || ks.p_value < 0.001 ? :critical :
                   psi > 0.1 || ks.p_value < alpha  ? :warning  : :none
        push!(results, DriftResult(fn[j], :ks, ks.D, ks.p_value, psi, drifted, severity))
    end
    results
end

# ── A/B Testing ───────────────────────────────────────────────────────────────

"""
    ABTestResult

Frequentist A/B test comparing two model variants.
"""
struct ABTestResult
    model_a      ::String
    model_b      ::String
    metric       ::String
    mean_a       ::Float64
    mean_b       ::Float64
    delta        ::Float64   # mean_b - mean_a
    relative_lift::Float64   # (mean_b - mean_a) / |mean_a|
    t_stat       ::Float64
    p_value      ::Float64
    ci_lo        ::Float64
    ci_hi        ::Float64
    winner       ::Union{String, Nothing}
    power        ::Float64
end

"""
    ab_test(errors_a, errors_b; name_a, name_b, metric, alpha) -> ABTestResult

Welch's t-test for difference in prediction errors (lower-is-better metrics).
"""
function ab_test(errors_a::AbstractVector{<:Real},
                 errors_b::AbstractVector{<:Real};
                 name_a  ::String = "model_A",
                 name_b  ::String = "model_B",
                 metric  ::String = "rmse",
                 alpha   ::Float64 = 0.05)

    na, nb = length(errors_a), length(errors_b)
    μa, μb = mean(errors_a), mean(errors_b)
    sa, sb = std(errors_a), std(errors_b)
    δ      = μb - μa

    # Welch's t
    se    = sqrt(sa^2/na + sb^2/nb)
    t     = δ / max(se, 1e-12)
    ν     = (sa^2/na + sb^2/nb)^2 /
            ((sa^2/na)^2/(na-1) + (sb^2/nb)^2/(nb-1))
    p     = 2 * ccdf(TDist(max(ν, 1.0)), abs(t))
    ci_lo = δ - 1.96se; ci_hi = δ + 1.96se

    # Power (Cohen's d)
    d = abs(δ) / max((sa + sb)/2, 1e-12)
    power = cdf(Normal(), d * sqrt(min(na, nb)/2) - 1.96)

    winner = p < alpha ? (δ < 0 ? name_b : name_a) : nothing
    rel_lift = abs(μa) > 1e-12 ? δ / abs(μa) : NaN

    ABTestResult(name_a, name_b, metric, μa, μb, δ, rel_lift,
                 t, p, ci_lo, ci_hi, winner, power)
end

# ── Auto-retraining trigger ────────────────────────────────────────────────────

"""
    RetrainingTrigger

Configuration for automatic model retraining.
"""
struct RetrainingTrigger
    drift_threshold     ::Float64   # PSI threshold
    performance_drop    ::Float64   # relative RMSE increase to trigger
    min_new_samples     ::Int       # minimum new data before retraining
    check_interval_days ::Int
end

RetrainingTrigger(; drift_threshold=0.15, performance_drop=0.10,
                   min_new_samples=30, check_interval_days=7) =
    RetrainingTrigger(drift_threshold, performance_drop, min_new_samples, check_interval_days)

"""
    should_retrain(trigger, drift_results, current_rmse, baseline_rmse, n_new) -> NamedTuple

Decide whether to trigger retraining based on drift + performance signals.
"""
function should_retrain(trigger       ::RetrainingTrigger,
                        drift_results ::Vector{DriftResult},
                        current_rmse  ::Float64,
                        baseline_rmse ::Float64,
                        n_new         ::Int)
    drift_triggered  = any(r -> r.psi > trigger.drift_threshold, drift_results)
    perf_triggered   = (current_rmse - baseline_rmse) / max(baseline_rmse, 1e-12) >
                       trigger.performance_drop
    enough_data      = n_new >= trigger.min_new_samples
    n_drifted        = count(r -> r.drifted, drift_results)

    retrain = (drift_triggered || perf_triggered) && enough_data
    reason  = drift_triggered && perf_triggered ? "drift+performance_drop" :
              drift_triggered ? "feature_drift" :
              perf_triggered  ? "performance_drop" : "none"

    (retrain=retrain, reason=reason, drift_triggered=drift_triggered,
     perf_triggered=perf_triggered, n_features_drifted=n_drifted,
     enough_data=enough_data)
end

# ── Demo ──────────────────────────────────────────────────────────────────────

if abspath(PROGRAM_FILE) == @__FILE__
    @info "MLOps Pipeline Demo — Chapter 46"
    rng = MersenneTwister(42)

    # 1. Model registry
    reg = ModelRegistry()
    id1 = register!(reg, "RandomForestAccess", v"1.0.0",
                    Dict("rmse"=>0.0045, "r2"=>0.72, "n_trees"=>100.0),
                    Dict("n_trees"=>100, "max_depth"=>6))
    id2 = register!(reg, "GradientBoostAccess", v"1.0.0",
                    Dict("rmse"=>0.0038, "r2"=>0.78, "n_trees"=>200.0),
                    Dict("n_trees"=>200, "learning_rate"=>0.05))
    promote_champion!(reg, id2)
    @info "Champion: $(get_champion(reg).name)"

    lb = model_leaderboard(reg; metric="rmse")
    @info "Leaderboard: $([(r.name, r.metrics["rmse"]) for r in lb])"

    # 2. Drift detection
    X_ref = randn(rng, 200, 4)
    X_new = randn(rng, 80,  4)
    X_new[:, 1] .+= 1.5   # induce drift in feature 1
    drift = detect_drift(X_ref, X_new;
                         feature_names=["poverty","uninsured","pop_k","rurality"])
    @info "Drift results:"
    for d in drift
        @info "  $(d.feature): PSI=$(round(d.psi;digits=3)) $(d.drifted ? "⚠ DRIFT" : "ok") ($(d.severity))"
    end

    # 3. A/B test
    err_a = abs.(randn(rng, 100)) .* 0.005 .+ 0.003
    err_b = abs.(randn(rng, 100)) .* 0.004 .+ 0.0025
    ab = ab_test(err_a, err_b; name_a="RF", name_b="GBM")
    @info "A/B test: RF=$(round(ab.mean_a;digits=4)) vs GBM=$(round(ab.mean_b;digits=4))  p=$(round(ab.p_value;digits=3))  winner=$(ab.winner)"

    # 4. Retraining trigger
    trigger = RetrainingTrigger(drift_threshold=0.1, performance_drop=0.05,
                                 min_new_samples=50)
    dec = should_retrain(trigger, drift, 0.0050, 0.0038, 80)
    @info "Retrain decision: $(dec.retrain)  reason: $(dec.reason)"
end

using Distributions: TDist, Normal, ccdf, cdf
