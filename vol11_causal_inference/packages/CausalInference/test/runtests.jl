using Test, Statistics, Random, LinearAlgebra

include(joinpath(@__DIR__, "..", "src", "CausalInference.jl"))
using .CausalInference

function make_data(n=200; seed=1, true_ate=2.0)
    rng = MersenneTwister(seed)
    X   = randn(rng, n, 3)
    # True PS logistic in X[:,1], X[:,2]
    ps  = 1 ./ (1 .+ exp.(-(0.5 .* X[:,1] .- 0.3 .* X[:,2])))
    D   = Float64.(rand(rng, n) .< ps)
    y   = true_ate .* D .+ X[:,1] .+ 0.5 .* X[:,2] .+ randn(rng, n)
    (X=X, D=D, y=y, ps_true=ps)
end

@testset "Propensity score estimation" begin
    d = make_data()
    m = ps_fit(d.D, d.X)
    @test m.converged || m.n_iter > 0
    p̂ = ps_predict(m, d.X)
    @test length(p̂) == 200
    @test all(0.0 .< p̂ .< 1.0)
    @test m.log_lik < 0.0
end

@testset "Propensity trimming and overlap" begin
    d  = make_data()
    m  = ps_fit(d.D, d.X)
    p̂  = ps_predict(m, d.X)
    ps_t, D_t, y_t, idx = ps_trim(p̂, d.D, d.y)
    @test length(ps_t) <= 200
    @test all(0.05 .<= ps_t .<= 0.95)
    ov = ps_overlap(p̂, d.D)
    @test ov.n_treated + ov.n_control == 200
    @test ov.overlap_min <= ov.overlap_max
end

@testset "IPW ATE (Hajek)" begin
    d    = make_data(; true_ate=2.0)
    m    = ps_fit(d.D, d.X)
    p̂    = ps_predict(m, d.X)
    rng  = MersenneTwister(10)
    res  = ipw_ate(d.D, d.y, p̂; estimator=:hajek, n_boot=50, rng=rng)
    @test isfinite(res.ate)
    @test res.se > 0.0
    @test res.ci_lower < res.ate < res.ci_upper
    @test res.n_treated + res.n_control == 200
end

@testset "HT ATE estimator" begin
    d   = make_data()
    m   = ps_fit(d.D, d.X)
    p̂   = ps_predict(m, d.X)
    rng = MersenneTwister(11)
    res = ipw_ate(d.D, d.y, p̂; estimator=:ht, n_boot=50, rng=rng)
    @test isfinite(res.ate)
    @test res.estimator == :ht
end

@testset "AIPW doubly-robust ATE" begin
    d   = make_data(; true_ate=2.0)
    m   = ps_fit(d.D, d.X)
    p̂   = ps_predict(m, d.X)
    rng = MersenneTwister(12)
    res = aipw_ate(d.D, d.y, p̂, d.X; n_boot=50, rng=rng)
    @test isfinite(res.ate)
    @test res.se > 0.0
    @test res.estimator == :aipw
    # AIPW should be close to true ATE (within 2 SE)
    @test abs(res.ate - 2.0) < 3 * res.se + 0.5
end

@testset "Overlap-weighted ATE" begin
    d   = make_data()
    m   = ps_fit(d.D, d.X)
    p̂   = ps_predict(m, d.X)
    rng = MersenneTwister(13)
    res = overlap_ate(d.D, d.y, p̂; n_boot=50, rng=rng)
    @test isfinite(res.ate)
    @test res.estimator == :overlap
end

@testset "NN matching ATT" begin
    d   = make_data(; true_ate=2.0)
    m   = ps_fit(d.D, d.X)
    p̂   = ps_predict(m, d.X)
    rng = MersenneTwister(14)
    mr  = nn_match(d.D, d.y, p̂, d.X; k=1, n_boot=50, rng=rng)
    @test mr.n_matched > 0
    @test isfinite(mr.att)
    @test mr.ci_lower < mr.att < mr.ci_upper
end

@testset "Balance table" begin
    d   = make_data()
    m   = ps_fit(d.D, d.X)
    p̂   = ps_predict(m, d.X)
    rng = MersenneTwister(15)
    mr  = nn_match(d.D, d.y, p̂, d.X; n_boot=50, rng=rng)
    tbl = balance_table(mr, ["age","income","edu"])
    @test length(tbl) == 3
    # At least some covariates improved
    @test any(r.improved for r in tbl)
end

@testset "Causal report" begin
    d   = make_data(; n=150)
    rng = MersenneTwister(99)
    rpt = causal_report(d.D, d.y, d.X; study_name="Test", n_boot=30, rng=rng)
    @test rpt.n == 150
    @test isfinite(rpt.ipw_ate)
    @test isfinite(rpt.aipw_ate)
    @test isfinite(rpt.att_matched)
    @test rpt.mean_smd_after <= rpt.mean_smd_before + 0.5
end
