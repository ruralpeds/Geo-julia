#!/usr/bin/env julia
# scripts/health_intelligence.jl
# Population health analytics and risk stratification for North Dakota counties

using Random, Statistics, Printf, LinearAlgebra

include(joinpath(@__DIR__, "..", "packages", "HealthIntelligence", "src", "HealthIntelligence.jl"))
using .HealthIntelligence

rng = MersenneTwister(2024)

println("="^66)
println("  North Dakota Population Health Intelligence  —  53 Counties")
println("="^66)

n_counties = 53

# ── Generate synthetic ND county-level health indicators ─────────────────────
# Domain 1: Access — drive time to nearest hospital (min)
access = 15.0 .+ rand(rng, n_counties) .* 120.0

# Domain 2: Deprivation — composite social vulnerability index (0-100)
deprivation = 20.0 .+ rand(rng, n_counties) .* 60.0

# Domain 3: Disease burden — age-standardised mortality rate (per 100k)
burden = 600.0 .+ rand(rng, n_counties) .* 400.0

# Domain 4: Behavioural — obesity + smoking composite (0-100)
behavioural = 25.0 .+ rand(rng, n_counties) .* 40.0

# Domain 5: Mental health — poor mental health days/month
mental = 3.0 .+ rand(rng, n_counties) .* 7.0

X_domains = hcat(access, deprivation, burden, behavioural, mental)

# ── Composite risk score ──────────────────────────────────────────────────────
println("\n── 1. Composite Health Risk Score ───────────────────────────────────")
risk_r = composite_risk_score(X_domains;
                               weights=[0.25, 0.25, 0.30, 0.10, 0.10])
for band in 1:4
    names = ["Low","Moderate","High","Very High"][band]
    n_b = sum(risk_r.quantile_band .== band)
    @printf "  Band %d (%9s): %2d counties\n" band names n_b
end
top5_risk = sortperm(risk_r.scores; rev=true)[1:5]
println("  Top 5 highest-risk counties:")
for (i,c) in enumerate(top5_risk)
    @printf "    %d. County %2d  score=%.3f\n" i c risk_r.scores[c]
end

# ── Health Needs Index ────────────────────────────────────────────────────────
println("\n── 2. Health Needs Index ─────────────────────────────────────────────")
hni_r = health_needs_index(access, deprivation, burden;
                            w_access=0.3, w_deprivation=0.4, w_burden=0.3)
top5_hni = sortperm(hni_r.index; rev=true)[1:5]
println("  Top 5 highest-need counties:")
for (i,c) in enumerate(top5_hni)
    @printf "    %d. County %2d  HNI=%.1f  rank=%d\n" i c hni_r.index[c] hni_r.rank[c]
end
n_urgent = sum(hni_r.quantile_band .== 4)
@printf "  Urgent need (top quartile): %d counties\n" n_urgent

# ── Risk-adjusted outcomes ────────────────────────────────────────────────────
println("\n── 3. Risk-Adjusted Outcomes (Preventable Hospitalisations) ─────────")
# Simulate expected based on risk model; observed with random variation
expected = 50.0 .+ risk_r.scores .* 5.0
observed = max.(0.0, round.(Int, expected .+ randn(rng, n_counties) .* 8.0)) |> Float64
rao = risk_adjusted_outcomes(observed, expected; label="Preventable Hospitalisations")
@printf "  Global SMR: %.3f\n" rao.smr_global
@printf "  High outliers (SMR CI > 1): %d counties\n" rao.n_high
@printf "  Low outliers (SMR CI < 1):  %d counties\n" rao.n_low

# ── LOF Anomaly Detection ─────────────────────────────────────────────────────
println("\n── 4. Local Outlier Factor — Anomalous Health Profiles ──────────────")
lof_r = lof(X_domains; k=7, threshold=2.5)
@printf "  Outlier counties: %d / %d (LOF threshold = 2.5)\n" lof_r.n_outliers lof_r.n
if !isempty(lof_r.outlier_idx)
    println("  Top LOF scores:")
    top_lof = sort(1:n_counties; by=i->-lof_r.lof_scores[i])[1:min(5,end)]
    for c in top_lof
        @printf "    County %2d: LOF=%.2f  %s\n" c lof_r.lof_scores[c] \
            (lof_r.outliers[c] ? "OUTLIER" : "")
    end
end

# ── Isolation Forest ──────────────────────────────────────────────────────────
println("\n── 5. Isolation Forest — Health Anomaly Scoring ─────────────────────")
if_r = isolation_forest(X_domains; n_trees=100, threshold=0.58, rng=rng)
@printf "  Anomalous counties: %d / %d\n" sum(if_r.outliers) n_counties
@printf "  Score range: %.3f – %.3f\n" minimum(if_r.anomaly_scores) maximum(if_r.anomaly_scores)

# ── Population Segmentation ───────────────────────────────────────────────────
println("\n── 6. k-Means Population Segmentation (k=4) ─────────────────────────")
km = kmeans(X_domains, 4; n_restarts=10, rng=rng)
@printf "  Silhouette coefficient: %.3f\n" km.silhouette
@printf "  Within-cluster inertia: %.1f\n" km.inertia
for c in 1:4
    members = findall(km.labels .== c)
    mean_hni = isempty(members) ? NaN : mean(hni_r.index[members])
    @printf "  Cluster %d: %2d counties  mean HNI=%.1f\n" c length(members) mean_hni
end

# ── Predictive Risk Model ─────────────────────────────────────────────────────
println("\n── 7. Predictive Risk Model (Hospitalisation) ───────────────────────")
y_binary = Float64.(observed .> quantile(observed, 0.75))  # top quartile = high
pr_r = predictive_risk(X_domains, y_binary; λ=0.1)
@printf "  C-statistic  : %.3f  (0.5=random, 1.0=perfect)\n" pr_r.c_statistic
@printf "  Brier score  : %.4f  (lower=better)\n" pr_r.brier_score
@printf "  Calibration  : slope=%.3f  intercept=%.4f\n" \
    pr_r.calibration_slope pr_r.calibration_intercept
@printf "  High-risk counties: %d predicted\n" sum(pr_r.predicted_prob .> 0.5)

# ── Health event anomaly stream ───────────────────────────────────────────────
println("\n── 8. Health Event Anomaly Stream ───────────────────────────────────")
baseline_calls = fill(120.0, 52) .+ randn(rng, 52) .* 10
event_stream   = [120.0, 118.0, 122.0, 195.0, 230.0, 210.0, 125.0, 119.0]
anm = health_event_anomaly(event_stream, baseline_calls; threshold_sd=2.5)
@printf "  Event stream: %d time points\n" length(event_stream)
@printf "  Anomalous time points: %d  (first at t=%s)\n" \
    anm.n_anomalous (isnothing(anm.first_anomaly) ? "—" : string(anm.first_anomaly))
println("  Z-scores: " * join([@sprintf("%.1f",z) for z in anm.z_scores], "  "))

println("\n" * "="^66)
println("  Health intelligence analysis complete.")
println("="^66)
