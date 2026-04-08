#!/usr/bin/env julia
# scripts/surveillance.jl
# Real-time disease surveillance for North Dakota weekly respiratory illness data

using Random, Statistics, Printf

include(joinpath(@__DIR__, "..", "packages", "SurveillanceSystems", "src", "SurveillanceSystems.jl"))
using .SurveillanceSystems

rng = MersenneTwister(2024)

println("="^68)
println("  North Dakota Respiratory Illness Surveillance  —  52 Weeks")
println("="^68)

# ── Generate synthetic ND weekly ILI count data ───────────────────────────────
# Seasonal baseline + two outbreak periods (influenza season)
T      = 104   # 2 years of weekly data
μ_base = 45.0  # baseline weekly ILI cases (ND scale)
# Seasonal component: higher in winter (weeks 1-10, 44-52)
season_factor = [1.0 + 0.6*exp(-((w%52-0 < 10 ? w%52 : 52-(w%52))^2)/50) for w in 1:T]
x = [μ_base * season_factor[t] + sqrt(μ_base * season_factor[t]) * randn(rng)
     for t in 1:T]
x = max.(0.0, x)

# Inject outbreak at weeks 8-14 (year 1) and weeks 60-68 (year 2)
for t in 8:14;  x[t] *= 3.2; end
for t in 60:68; x[t] *= 4.5; end
x = round.(Int, max.(0.0, x)) |> Float64

println("\n  Weekly case counts: min=$(Int(minimum(x))), max=$(Int(maximum(x))), mean=$(round(mean(x),digits=1))")

# ── CUSUM ─────────────────────────────────────────────────────────────────────
μ₀ = mean(x[15:52])   # in-control mean (outbreak-free window)
σ₀ = max(std(x[15:52]; corrected=true), 1.0)
cusum_r = cusum(x; μ₀=μ₀, σ₀=σ₀, k=σ₀/2, h=5.0*σ₀)
println("\n  CUSUM: $(cusum_r.n_alerts) alerts  (h=5σ, k=σ/2)")
for t in cusum_r.alert_times[1:min(5,end)]
    @printf "    Week %3d: S=%.1f  x=%d\n" t cusum_r.S[t] round(Int,x[t])
end

# ── EWMA ──────────────────────────────────────────────────────────────────────
ewma_r = ewma(x; λ=0.2, L=3.0, μ₀=μ₀, σ₀=σ₀)
println("\n  EWMA (λ=0.2, L=3σ): $(ewma_r.n_alerts) alerts")

# ── CDC EARS ──────────────────────────────────────────────────────────────────
ears_r = ears(x; baseline_days=7, threshold=3.0)
n_c1 = sum(ears_r.alerts_C1); n_c2 = sum(ears_r.alerts_C2); n_c3 = sum(ears_r.alerts_C3)
println("\n  CDC EARS:  C1=$(n_c1)  C2=$(n_c2)  C3=$(n_c3) alerts")

# ── Farrington ────────────────────────────────────────────────────────────────
farr = farrington(x; baseline_weeks=52, alpha=0.05)
println("\n  Farrington regression: $(farr.n_alerts) alerts")

# ── Temporal scan ─────────────────────────────────────────────────────────────
scan_r = temporal_scan(x; max_window=16, n_sim=499, rng=rng)
println("\n  Temporal Kulldorff scan:")
@printf "    LLR=%.2f  RR=%.2f  p=%.3f  %s\n" \
    scan_r.λ_obs scan_r.rr scan_r.p_value (scan_r.significant ? "SIGNIFICANT" : "n.s.")
@printf "    Most likely cluster: weeks %d–%d  (obs=%d, exp=%.1f)\n" \
    scan_r.cluster_start scan_r.cluster_end scan_r.cluster_cases scan_r.expected_cases

# ── Sensitivity / specificity ─────────────────────────────────────────────────
truth = falses(T); truth[8:14] .= true; truth[60:68] .= true
for (name, alerts) in [("CUSUM", cusum_r.alerts), ("EWMA", ewma_r.alerts),
                        ("EARS-C3", ears_r.alerts_C3)]
    perf = sensitivity_specificity(alerts, truth)
    @printf "\n  %-8s  sens=%.2f  spec=%.2f  F1=%.2f\n" name perf.sensitivity perf.specificity perf.f1
end

# ── Prospective scan (simulated real-time) ────────────────────────────────────
println("\n  Prospective scan (last 4 weeks, rolling):")
for t_end in [50, 70, 80]
    pr = prospective_scan(x[1:t_end]; window=4, n_sim=199, rng=rng)
    @printf "    Through week %3d: LLR=%.2f  p=%.3f  start=week %d  %s\n" \
        t_end pr.llr pr.p_value pr.cluster_start (pr.significant ? "ALERT" : "—")
end

# ── Threshold calibration ─────────────────────────────────────────────────────
cal = calibrate_threshold(x, truth; method=:cusum)
@printf "\n  Optimal CUSUM h (max F1): h=%.2f  F1=%.3f\n" cal.threshold cal.f1

println("\n" * "="^68)
println("  Surveillance analysis complete.")
println("="^68)
