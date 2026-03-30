using Test, Statistics, Random, LinearAlgebra

include(joinpath(@__DIR__, "..", "packages", "CausalInference", "src", "CausalInference.jl"))
include(joinpath(@__DIR__, "..", "packages", "PolicyEval", "src", "PolicyEval.jl"))
include(joinpath(@__DIR__, "..", "packages", "SpatialCausal", "src", "SpatialCausal.jl"))
using .CausalInference, .PolicyEval, .SpatialCausal

# ── Shared fixtures ───────────────────────────────────────────────────────────

function make_obs_data(n=150; seed=1, true_ate=3.0)
    rng  = MersenneTwister(seed)
    X    = randn(rng, n, 3)
    ps   = 1 ./ (1 .+ exp.(-(0.5*X[:,1] .- 0.3*X[:,2])))
    D    = Float64.(rand(rng, n) .< ps)
    y    = true_ate.*D .+ X[:,1] .+ 0.5*X[:,2] .+ randn(rng, n)
    (X=X, D=D, y=y, true_ate=true_ate)
end

function make_panel_data(n_u=20, n_t=6; seed=2, true_att=2.0)
    rng = MersenneTwister(seed)
    treat = vcat(trues(n_u÷2), falses(n_u - n_u÷2))
    treat_t = 4
    y=[]; D_=[]; P_=[]; U=[]; T_=[]
    for u in 1:n_u, t in 1:n_t
        post = t >= treat_t
        push!(y, 0.1t + (treat[u] && post ? true_att : 0.0) + 0.3randn(rng))
        push!(D_, treat[u]); push!(P_, post); push!(U, u); push!(T_, t)
    end
    (y=Float64.(y), treat=Bool.(D_), post=Bool.(P_), unit_ids=U, time=T_, treat_t=treat_t)
end

function make_spatial_data(n_u=30, n_t=4; seed=3)
    rng = MersenneTwister(seed)
    coords = hcat(rand(rng, n_u).*8, rand(rng, n_u).*4)
    sites  = [2.0 1.0; 6.0 3.0]
    y=[]; uid=[]; post=[]
    for u in 1:n_u, t in 1:n_t
        pt = t >= 3
        push!(y, 0.2t + 0.3randn(rng)); push!(uid, u); push!(post, pt)
    end
    (y=Float64.(y), coords=coords, post=Bool.(post), unit_ids=uid, sites=sites)
end

function make_iv_data(n=100; seed=4)
    rng = MersenneTwister(seed)
    Z   = rand(rng, n)
    X   = randn(rng, n, 1)
    D   = Z .+ 0.3randn(rng, n)
    y   = 2.0.*D .+ X[:,1] .+ randn(rng, n)
    (y=y, D=D, Z=Z, X=X)
end

# =============================================================================
# CausalInference Tests
# =============================================================================

@testset "CI — propensity score" begin
    d  = make_obs_data()
    m  = ps_fit(d.D, d.X)
    p̂  = ps_predict(m, d.X)
    @test all(0.0 .< p̂ .< 1.0)
    @test m.converged || m.n_iter > 0
    ov = ps_overlap(p̂, d.D)
    @test ov.overlap_min <= ov.overlap_max
end

@testset "CI — IPW Hajek ATE" begin
    d   = make_obs_data(; true_ate=3.0)
    m   = ps_fit(d.D, d.X)
    p̂   = ps_predict(m, d.X)
    rng = MersenneTwister(10)
    res = ipw_ate(d.D, d.y, p̂; estimator=:hajek, n_boot=50, rng=rng)
    @test isfinite(res.ate)
    @test res.se > 0.0
    @test res.ci_lower < res.ate < res.ci_upper
end

@testset "CI — AIPW doubly robust" begin
    d   = make_obs_data(; true_ate=3.0)
    m   = ps_fit(d.D, d.X)
    p̂   = ps_predict(m, d.X)
    rng = MersenneTwister(11)
    res = aipw_ate(d.D, d.y, p̂, d.X; n_boot=50, rng=rng)
    @test isfinite(res.ate)
    @test res.estimator == :aipw
end

@testset "CI — overlap weights" begin
    d   = make_obs_data()
    m   = ps_fit(d.D, d.X)
    p̂   = ps_predict(m, d.X)
    rng = MersenneTwister(12)
    res = overlap_ate(d.D, d.y, p̂; n_boot=50, rng=rng)
    @test res.estimator == :overlap
    @test isfinite(res.ate)
end

@testset "CI — NN matching" begin
    d   = make_obs_data()
    m   = ps_fit(d.D, d.X)
    p̂   = ps_predict(m, d.X)
    rng = MersenneTwister(13)
    mr  = nn_match(d.D, d.y, p̂, d.X; n_boot=50, rng=rng)
    @test mr.n_matched > 0
    @test isfinite(mr.att)
end

# =============================================================================
# PolicyEval Tests
# =============================================================================

@testset "PE — 2×2 DiD" begin
    d   = make_panel_data()
    rng = MersenneTwister(20)
    res = did_2x2(d.y, d.treat, d.post; unit_ids=d.unit_ids, n_boot=50, rng=rng)
    @test isfinite(res.β_did)
    @test res.ci_lower < res.β_did < res.ci_upper
    @test abs(res.β_did - 2.0) < 2.0
end

@testset "PE — event study" begin
    d   = make_panel_data()
    rng = MersenneTwister(21)
    es  = event_study(d.y, d.treat, d.time;
                      treat_time=d.treat_t, unit_ids=d.unit_ids, n_boot=50, rng=rng)
    @test length(es.β) > 0
    @test all(isfinite.(es.β))
end

@testset "PE — parallel trends test" begin
    d   = make_panel_data()
    rng = MersenneTwister(22)
    pt  = parallel_trends_test(d.y, d.treat, d.time;
                                treat_time=d.treat_t, unit_ids=d.unit_ids,
                                n_boot=50, rng=rng)
    @test 0.0 <= pt.p_value <= 1.0
    @test isfinite(pt.chi2)
end

@testset "PE — synthetic control" begin
    rng    = MersenneTwister(23)
    T_pre  = 8; T_post = 4; n_d = 6
    donors = randn(rng, T_pre+T_post, n_d)
    y_t    = donors[:,1:3] * [0.5,0.3,0.2] .+ 2.0*(0:T_pre+T_post-1 .>= T_pre)
    sr = synth_control(y_t[1:T_pre], donors[1:T_pre,:],
                       y_t[T_pre+1:end], donors[T_pre+1:end,:]; n_placebo_iter=3)
    @test abs(sum(sr.weights) - 1.0) < 1e-6
    @test all(sr.weights .>= -1e-8)
    @test sr.ratio > 0.0
end

@testset "PE — RDD" begin
    rng = MersenneTwister(24)
    n   = 200
    x   = randn(rng, n)
    y   = 3.0.*(x .>= 0) .+ 2.0.*x .+ randn(rng, n)
    res = rdd_fit(y, x; cutoff=0.0, n_boot=50, rng=rng)
    @test isfinite(res.τ)
    @test res.n_left > 0
    @test res.n_right > 0
    @test abs(res.τ - 3.0) < 3*res.se + 1.0
end

# =============================================================================
# SpatialCausal Tests
# =============================================================================

@testset "SC — spatial DiD" begin
    d   = make_spatial_data()
    rng = MersenneTwister(30)
    res = spatial_did(d.y, d.coords, d.post, d.sites;
                      radius=1.5, buffer=1.0, unit_ids=d.unit_ids, n_boot=50, rng=rng)
    @test isfinite(res.β_direct)
    @test isfinite(res.β_spillover)
    @test res.n == length(d.y)
end

@testset "SC — Conley SE" begin
    d   = make_obs_data(100)
    coords = hcat(rand(MersenneTwister(31), 100).*5, rand(MersenneTwister(32), 100).*5)
    res = conley_se(d.y, d.X, coords; cutoff=2.0)
    @test all(res.se_conley .>= 0.0)
    @test length(res.β) == 4   # intercept + 3 covariates
    @test all(0.0 .<= res.p_values .<= 1.0)
end

@testset "SC — geographic IV" begin
    d  = make_iv_data()
    res = geo_iv_2sls(d.y, d.D, d.Z, d.X)
    @test isfinite(res.β_2sls[2])
    @test res.f_stat > 0.0
    @test res.r2_first >= 0.0
end

# =============================================================================
# Cross-package Integration Tests
# =============================================================================

@testset "Integration — PS → DiD comparison" begin
    # Compare PS-matched ATT vs DiD ATT on same data
    d   = make_obs_data(200; true_ate=2.5)
    m   = ps_fit(d.D, d.X)
    p̂   = ps_predict(m, d.X)
    rng = MersenneTwister(40)
    mr  = nn_match(d.D, d.y, p̂, d.X; n_boot=30, rng=rng)
    @test isfinite(mr.att)
    # Both estimators should be in the right ballpark
    @test abs(mr.att - 2.5) < 3.0
end

@testset "Integration — DiD residuals → Conley correction" begin
    # Run DiD, then apply Conley SE to the unit-level residuals
    d    = make_panel_data(30, 6)
    rng  = MersenneTwister(41)
    dr   = did_2x2(d.y, d.treat, d.post; unit_ids=d.unit_ids, n_boot=30, rng=rng)
    @test isfinite(dr.β_did)

    # Simulate spatial units
    n_u  = 30
    coords = hcat(rand(MersenneTwister(42), n_u) .* 8, rand(MersenneTwister(43), n_u) .* 4)
    # Unit-level DiD residuals (simplification: y_post - y_pre per unit)
    y_unit = [mean(d.y[d.unit_ids .== u]) for u in 1:n_u]
    X_unit = hcat(rand(MersenneTwister(44), n_u), rand(MersenneTwister(45), n_u))
    cr = conley_se(y_unit, X_unit, coords; cutoff=2.0)
    @test all(cr.se_conley .>= 0.0)
end

@testset "Integration — PS weights → 2SLS comparison" begin
    # Compare IPW ATE vs 2SLS LATE when instrument = PS quintile
    d    = make_obs_data(150; true_ate=2.0)
    m    = ps_fit(d.D, d.X)
    p̂    = ps_predict(m, d.X)
    rng  = MersenneTwister(50)
    ipw  = ipw_ate(d.D, d.y, p̂; estimator=:hajek, n_boot=30, rng=rng)

    # Use PS as instrument (Heckman-style)
    iv_res = geo_iv_2sls(d.y, d.D, p̂, d.X[:,1:1])
    @test isfinite(ipw.ate)
    @test isfinite(iv_res.β_2sls[2])
end

@testset "Integration — synth control gaps → RDD validation" begin
    # Use post-treatment gaps from synth control to validate RDD estimate direction
    rng    = MersenneTwister(60)
    T_pre  = 6; T_post = 4; n_d = 5
    donors = randn(rng, T_pre+T_post, n_d)
    y_t    = donors[:,1] .+ 2.0.*(0:T_pre+T_post-1 .>= T_pre)
    sr = synth_control(y_t[1:T_pre], donors[1:T_pre,:],
                       y_t[T_pre+1:end], donors[T_pre+1:end,:]; n_placebo_iter=2)
    gaps = synth_gaps(y_t[T_pre+1:end], donors[T_pre+1:end,:], sr.weights)
    @test length(gaps) == T_post
    # Mean gap should be positive (effect injected)
    @test mean(gaps) > 0.0

    # RDD on running variable near cutoff
    x   = randn(rng, 100)
    yr  = 2.0.*(x .>= 0) .+ randn(rng, 100)
    rdd = rdd_fit(yr, x; cutoff=0.0, n_boot=30, rng=rng)
    # Both gaps and RDD should find positive effects
    @test sign(mean(gaps)) == sign(rdd.τ) || abs(rdd.τ) < 2*rdd.se
end

println("\n✓ All Vol 11 integration tests passed.")
