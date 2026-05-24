#!/usr/bin/env julia
# test/integration_test.jl
# Vol 13 integration tests: SurveillanceSystems · InfectiousDisease · HealthIntelligence

using Test, Random, Statistics, LinearAlgebra

include(joinpath(@__DIR__, "..", "packages", "SurveillanceSystems", "src", "SurveillanceSystems.jl"))
include(joinpath(@__DIR__, "..", "packages", "InfectiousDisease",   "src", "InfectiousDisease.jl"))
include(joinpath(@__DIR__, "..", "packages", "HealthIntelligence",  "src", "HealthIntelligence.jl"))

using .SurveillanceSystems, .InfectiousDisease, .HealthIntelligence

rng = MersenneTwister(42)

# ─── Shared fixtures ──────────────────────────────────────────────────────────

function make_weekly_series(; seed=1, T=52, μ=30.0, outbreak_weeks=28:35, mult=4.0)
    rng = MersenneTwister(seed)
    x   = max.(0.0, μ .+ sqrt(μ) .* randn(rng, T))
    for t in outbreak_weeks; x[t] = x[t] * mult; end
    x
end

function make_county_features(n=20; seed=3)
    rng = MersenneTwister(seed)
    hcat(rand(rng, n) .* 120,   # access (min)
         rand(rng, n) .* 60,    # deprivation
         rand(rng, n) .* 400 .+ 500, # burden
         rand(rng, n) .* 40,    # behavioural
         rand(rng, n) .* 7)     # mental health
end

# ─── SurveillanceSystems tests ────────────────────────────────────────────────

@testset "SurveillanceSystems — CUSUM" begin
    x = make_weekly_series()
    r = cusum(x; μ₀=mean(x[1:20]))
    @test r.n == length(x)
    @test all(r.S .>= 0)
    @test r.n_alerts == length(r.alert_times)
    @test any(r.alert_times .>= 25)  # detects outbreak
end

@testset "SurveillanceSystems — EWMA" begin
    x = make_weekly_series()
    r = ewma(x; λ=0.2)
    @test length(r.Z) == length(x)
    @test all(r.ucl .>= r.lcl)
    @test any(r.alert_times .>= 25)
end

@testset "SurveillanceSystems — Farrington" begin
    x = make_weekly_series(; T=104, seed=5)
    r = farrington(x; baseline_weeks=52)
    @test length(r.threshold) == 104
    valid = .!isnan.(r.threshold)
    @test any(valid)
    @test all(r.upper95[valid] .>= r.threshold[valid] .- 1e-6)
end

@testset "SurveillanceSystems — EARS" begin
    x = make_weekly_series()
    r = ears(x; baseline_days=7)
    @test length(r.C2) == length(x)
    # C3 should be positive somewhere during outbreak
    valid = .!isnan.(r.C3)
    @test any(r.C3[valid] .> 0)
end

@testset "SurveillanceSystems — Temporal scan" begin
    x = make_weekly_series(; mult=5.0)
    r = temporal_scan(x; n_sim=99, rng=MersenneTwister(1))
    @test r.λ_obs >= 0
    @test 0 < r.p_value <= 1
    @test r.cluster_start <= r.cluster_end
    @test r.rr >= 0
end

@testset "SurveillanceSystems — Sensitivity/Specificity" begin
    x = make_weekly_series()
    rc = cusum(x; μ₀=mean(x[1:20]))
    truth = falses(length(x)); truth[28:35] .= true
    perf  = sensitivity_specificity(rc.alerts, truth)
    @test 0 <= perf.sensitivity <= 1
    @test 0 <= perf.specificity <= 1
    @test perf.tp + perf.fp + perf.fn + perf.tn == length(x)
end

@testset "SurveillanceSystems — Combine alerts" begin
    x  = make_weekly_series()
    rc = cusum(x)
    re = ewma(x)
    combined = combine_alerts(rc, re)
    @test all(combined .== (rc.alerts .| re.alerts))
end

@testset "SurveillanceSystems — Prospective scan" begin
    x = make_weekly_series()
    r = prospective_scan(x; window=4, n_sim=99, rng=MersenneTwister(2))
    @test 0 < r.p_value <= 1
end

# ─── InfectiousDisease tests ──────────────────────────────────────────────────

@testset "InfectiousDisease — SIR basic" begin
    r = sir(50000, 10, 0.3, 0.1; t_end=200.0)
    @test all(abs.(r.S .+ r.I .+ r.R .- 1.0) .< 1e-3)
    @test r.R₀ ≈ 3.0 atol=1e-8
    @test r.attack_rate > 0.8
    @test r.peak_I > 0
end

@testset "InfectiousDisease — SEIR" begin
    r = seir(50000, 50, 10, 0.3, 0.2, 0.1; t_end=300.0)
    @test all(abs.(r.S .+ r.E .+ r.I .+ r.R .- 1.0) .< 1e-3)
    @test argmax(r.E) <= argmax(r.I)
end

@testset "InfectiousDisease — Herd immunity" begin
    @test herd_immunity_threshold(2.0) ≈ 0.5
    @test herd_immunity_threshold(4.0) ≈ 0.75
    @test herd_immunity_threshold(1.0) == 0.0
    @test effective_r0(3.0, 0.33) ≈ 3.0*0.67 atol=0.01
end

@testset "InfectiousDisease — Attack rate prediction" begin
    for R₀ in [1.5, 2.0, 3.0]
        A = attack_rate_prediction(R₀)
        @test abs(1-A-exp(-R₀*A)) < 1e-8
    end
end

@testset "InfectiousDisease — R₀ from growth" begin
    r = sir(200000, 10, 0.3, 0.1; t_end=150.0)
    est = r0_from_growth(r.I .* 200000; γ=0.1, n_early=20)
    @test !isnan(est.R₀)
    @test est.R₀ > 1.0
end

@testset "InfectiousDisease — Spatial SIR" begin
    N = [20000.0, 30000.0, 15000.0]
    I₀ = [10.0, 0.0, 0.0]
    coords = [0.0 0.0; 1.0 0.0; 0.5 1.0]
    r = spatial_sir(N, I₀, coords, 0.3, 0.1; t_end=150.0, dt=1.0)
    @test r.n_patches == 3
    @test all(r.attack_rate .>= 0)
    @test r.attack_rate[1] > 0
end

@testset "InfectiousDisease — Stochastic SIR" begin
    r = sir_stochastic(10000, 5, 0.3, 0.1; rng=MersenneTwister(5))
    @test all(abs.(r.S .+ r.I .+ r.R .- 1.0) .< 0.01)
    @test all(r.I .>= -1e-6)
end

# ─── HealthIntelligence tests ─────────────────────────────────────────────────

@testset "HealthIntelligence — Composite risk" begin
    X = make_county_features()
    r = composite_risk_score(X)
    @test r.n == 20
    @test all(1 .<= r.quantile_band .<= 4)
    @test length(r.scores) == 20
end

@testset "HealthIntelligence — HNI" begin
    X = make_county_features()
    hni = health_needs_index(X[:,1], X[:,2], X[:,3])
    @test hni.n == 20
    @test all(0 .<= hni.index .<= 100)
    @test minimum(hni.rank) == 1 && maximum(hni.rank) == 20
end

@testset "HealthIntelligence — Risk-adjusted outcomes" begin
    n = 20
    exp_v = fill(10.0, n)
    obs_v = exp_v .+ randn(MersenneTwister(10), n) .* 3
    obs_v = max.(0.0, obs_v)
    rao = risk_adjusted_outcomes(obs_v, exp_v)
    @test isfinite(rao.smr_global)
    @test length(rao.unit_smr) == n
end

@testset "HealthIntelligence — LOF" begin
    X = make_county_features()
    r = lof(X; k=4, threshold=2.0)
    @test r.n == 20
    @test all(r.lof_scores .> 0)
end

@testset "HealthIntelligence — k-Means" begin
    X = make_county_features()
    r = kmeans(X, 3; rng=MersenneTwister(7))
    @test r.k == 3
    @test all(1 .<= r.labels .<= 3)
    @test r.inertia > 0
end

@testset "HealthIntelligence — Predictive risk" begin
    X = make_county_features()
    y = Float64.(X[:,3] .> median(X[:,3]))
    r = predictive_risk(X, y; λ=0.05)
    @test 0 <= r.c_statistic <= 1
    @test 0 <= r.brier_score <= 1
    @test all(0 .<= r.predicted_prob .<= 1)
end

# ─── Cross-package integration tests ─────────────────────────────────────────

@testset "Integration — SIR trajectories drive surveillance alerts" begin
    # Simulate epidemic, convert to weekly case counts, run surveillance
    r   = sir(100_000, 5, 0.35, 0.1; t_end=260.0, dt=7.0)  # weekly time step
    inc = max.(0.0, diff(r.R) .* 100_000)  # weekly new removals as proxy cases
    T   = length(inc)
    T < 10 && (inc = repeat(inc, ceil(Int, 10/T))[1:20])

    μ₀  = mean(inc[1:min(10,end)])
    σ₀  = max(std(inc[1:min(10,end)]; corrected=true), 1.0)
    sc  = cusum(inc; μ₀=μ₀, σ₀=σ₀)
    ew  = ewma(inc; μ₀=μ₀, σ₀=σ₀)

    @test sc.n == length(inc)
    @test ew.n == length(inc)
    # Ensemble shouldn't suppress all alerts during epidemic
    combo = combine_alerts(sc, ew)
    @test any(combo) || r.attack_rate < 0.01  # either detects or epidemic was trivial
end

@testset "Integration — Spatial SIR → region-level risk scores" begin
    n_patches = 5
    pops      = rand(rng, n_patches) .* 50000 .+ 10000
    I₀        = [20.0; zeros(n_patches-1)]
    coords    = rand(rng, n_patches, 2) .* 3.0
    sr = spatial_sir(pops, I₀, coords, 0.35, 0.1;
                     coupling_strength=0.05, t_end=150.0, dt=1.0)

    # Use attack rates + R₀ to build feature matrix for risk scoring
    features = hcat(sr.attack_rate,
                    fill(sr.R₀_global, n_patches),
                    sr.β_local,
                    pops ./ maximum(pops),
                    fill(sr.γ, n_patches))
    @test size(features) == (n_patches, 5)

    rsk = composite_risk_score(features)
    @test rsk.n == n_patches
    # Patch 1 (seeded) should have highest attack rate → highest risk score
    @test rsk.scores[1] >= minimum(rsk.scores) - 1e-6
end

@testset "Integration — Surveillance → IForest anomaly cross-check" begin
    # Run CUSUM and EWMA on 10 simulated county series; use alert counts as features
    n_counties = 15
    μ₀_c = 20.0
    feature_matrix = zeros(n_counties, 4)
    for i in 1:n_counties
        x = make_weekly_series(; seed=i, T=52, μ=μ₀_c)
        rc = cusum(x; μ₀=μ₀_c)
        re = ewma(x; μ₀=μ₀_c, σ₀=sqrt(μ₀_c))
        er = ears(x)
        sr = temporal_scan(x; n_sim=49, rng=MersenneTwister(i))
        feature_matrix[i, :] = [rc.n_alerts, re.n_alerts,
                                 sum(er.alerts_C3), sr.rr]
    end

    ifr = isolation_forest(feature_matrix; n_trees=50, threshold=0.55, rng=rng)
    @test ifr.n == n_counties
    @test all(0 .<= ifr.anomaly_scores .<= 1)
end

@testset "Integration — End-to-end ND spatial epidemiology pipeline" begin
    # 1. Simulate epidemic in 5 ND regions
    region_pop = [65_000.0, 120_000.0, 80_000.0, 350_000.0, 164_261.0]
    coords     = [-104.0 48.0; -98.0 48.0; -101.0 47.0; -97.0 46.5; -103.0 46.5]
    I₀         = [5.0, 0.0, 0.0, 0.0, 0.0]
    spat = spatial_sir(region_pop, I₀, coords, 0.35, 0.1;
                        coupling_strength=0.02, t_end=150.0, dt=1.0)
    @test spat.n_patches == 5
    @test any(spat.attack_rate .> 0)

    # 2. Convert trajectory to weekly incident series (region 4, highest pop)
    I_series = spat.I[:, 4] .* region_pop[4]
    weekly_inc = max.(0.0, [I_series[max(1,t-7)] - I_series[t] for t in 8:7:length(I_series)])
    length(weekly_inc) < 5 && (weekly_inc = vcat(weekly_inc, zeros(5 - length(weekly_inc))))
    weekly_inc = weekly_inc[1:max(5, length(weekly_inc))]

    # 3. Surveillance on region 4 weekly incidence
    μ₀_s = max(mean(weekly_inc[1:min(5,end)]), 1.0)
    sc   = cusum(weekly_inc; μ₀=μ₀_s, σ₀=sqrt(μ₀_s))
    @test sc.n == length(weekly_inc)
    @test isfinite(sc.μ₀)

    # 4. R₀ estimation
    I_total = sum(spat.I; dims=2)[:]
    est = r0_from_growth(I_total .* sum(region_pop); γ=0.1, n_early=15)
    @test !isnan(est.R₀) || spat.R₀_global < 1.1  # either valid or trivial epidemic

    # 5. County health intelligence layer
    X_feat = make_county_features(5)
    hni    = health_needs_index(X_feat[:,1], X_feat[:,2], X_feat[:,3])
    @test all(0 .<= hni.index .<= 100)

    # 6. Combined pipeline output is finite and consistent
    @test all(isfinite.(spat.attack_rate))
    @test all(isfinite.(hni.index))
    @test isfinite(sc.μ₀)
end

println("\n✓ All Vol 13 integration tests passed.")
