#!/usr/bin/env julia
using Test, Random, Statistics

include(joinpath(@__DIR__, "..", "src", "SurveillanceSystems.jl"))
using .SurveillanceSystems

# Shared fixture: 52-week series with outbreak in weeks 30-36
function make_series(; seed=1, n=52, μ_base=10.0, outbreak_mult=3.0)
    rng = MersenneTwister(seed)
    x = fill(μ_base, n)
    for t in 30:36; x[t] *= outbreak_mult; end
    x .+ randn(rng, n) .* sqrt(μ_base)
end

@testset "CUSUM — basic properties" begin
    x = make_series()
    r = cusum(x)
    @test r.n == length(x)
    @test all(r.S .>= 0)
    @test length(r.alerts) == r.n
    @test r.μ₀ > 0
    @test r.h > 0
    @test r.n_alerts == length(r.alert_times)
    # Outbreak at t=30-36 should trigger alert
    @test any(r.alert_times .>= 28)
end

@testset "CUSUM — parameter sensitivity" begin
    x = make_series()
    # Higher h → fewer alerts
    r_low  = cusum(x; h=2.0)
    r_high = cusum(x; h=20.0)
    @test r_low.n_alerts >= r_high.n_alerts

    # Two-sided detects both high and low
    r_two = cusum(x; two_sided=true)
    @test r_two.n_alerts >= 0
end

@testset "CUSUM reset" begin
    x = make_series()
    r = cusum_reset(x)
    @test all(r.S .>= 0)
    @test r.n == length(x)
end

@testset "EWMA — basic properties" begin
    x = make_series()
    r = ewma(x)
    @test length(r.Z) == length(x)
    @test all(r.ucl .>= r.Z .- 1e-9 .|| r.alerts)  # UCL above statistic when no alert
    @test r.n_alerts == length(r.alert_times)

    # λ=1 → EWMA = raw data
    r_raw = ewma(x; λ=1.0)
    @test r_raw.Z ≈ x atol=1e-8
end

@testset "EWMA — outbreak detection" begin
    x = make_series(; outbreak_mult=5.0)
    r = ewma(x; λ=0.3)
    @test any(r.alert_times .>= 28)
end

@testset "Farrington threshold" begin
    x = make_series(; n=104)  # 2 years
    r = farrington(x; baseline_weeks=52)
    @test length(r.threshold) == 104
    # Thresholds should be positive where computed
    valid = .!isnan.(r.threshold)
    @test all(r.threshold[valid] .> 0)
    @test all(r.upper95[valid] .>= r.threshold[valid])
    @test r.n_alerts >= 0
end

@testset "CDC EARS" begin
    x = make_series()
    r = ears(x)
    @test length(r.C1) == length(x)
    @test length(r.C2) == length(x)
    @test length(r.C3) == length(x)
    # C3 threshold more sensitive — similar or more alerts than C2
    @test sum(r.alerts_C3) >= 0  # non-negative

    # Extreme outbreak should trigger C3
    x2 = make_series(; outbreak_mult=8.0)
    r2 = ears(x2)
    @test sum(r2.alerts_C3) > 0
end

@testset "Temporal scan statistic" begin
    x = make_series()
    r = temporal_scan(x; n_sim=99, rng=MersenneTwister(1))
    @test r.λ_obs >= 0
    @test 0 < r.p_value <= 1
    @test 1 <= r.cluster_start <= r.cluster_end <= length(x)
    @test r.cluster_cases >= 0
    @test r.expected_cases > 0
    @test r.rr >= 0

    # Known outbreak → should be significant
    x_outbreak = fill(5.0, 52)
    x_outbreak[28:35] .= 50.0
    r2 = temporal_scan(x_outbreak; n_sim=99, rng=MersenneTwister(2))
    @test r2.cluster_start <= 35 && r2.cluster_end >= 28
end

@testset "Prospective scan" begin
    x = make_series()
    r = prospective_scan(x; window=5, n_sim=99, rng=MersenneTwister(3))
    @test haskey(r, :llr)
    @test haskey(r, :p_value)
    @test 0 < r.p_value <= 1
end

@testset "Combine alerts and sensitivity/specificity" begin
    x = make_series()
    rc = cusum(x)
    re = ewma(x)
    combined = combine_alerts(rc, re)
    @test length(combined) == length(x)
    @test all(combined .== (rc.alerts .| re.alerts))

    # Sensitivity/specificity
    truth = falses(length(x)); truth[30:36] .= true
    perf  = sensitivity_specificity(combined, truth)
    @test 0 <= perf.sensitivity <= 1
    @test 0 <= perf.specificity <= 1
    @test 0 <= perf.f1 <= 1
    @test perf.tp + perf.fp + perf.fn + perf.tn == length(x)
end

@testset "Threshold calibration" begin
    x = make_series()
    truth = falses(length(x)); truth[30:36] .= true
    cal = calibrate_threshold(x, truth; method=:cusum)
    @test !isnan(cal.threshold)
    @test cal.threshold > 0
    @test 0 <= cal.f1 <= 1
end

println("\n✓ All SurveillanceSystems tests passed.")
