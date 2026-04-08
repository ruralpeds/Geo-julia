using Test, Statistics, Random, LinearAlgebra

include(joinpath(@__DIR__, "..", "src", "SpatialCausal.jl"))
using .SpatialCausal

function make_panel_spatial(n_units=40, n_periods=6; seed=5, true_direct=3.0, true_spill=1.0)
    rng     = MersenneTwister(seed)
    coords  = hcat(rand(rng, n_units) .* 10, rand(rng, n_units) .* 10)
    # 2 treatment sites
    treat_sites = [2.0 2.0; 8.0 8.0]
    treat_t   = 4

    y_all = Float64[]; uid_all = Int[]; post_all = Bool[]
    for u in 1:n_units
        d_min = minimum(sqrt(sum((coords[u,:] .- treat_sites[k,:]).^2)) for k in 1:2)
        is_t  = d_min <= 1.5
        is_s  = !is_t && d_min <= 2.5
        for t in 1:n_periods
            post = t >= treat_t
            eff  = post && is_t ? true_direct : 0.0
            spe  = post && is_s ? true_spill  : 0.0
            push!(y_all, 0.1t + eff + spe + 0.3randn(rng))
            push!(uid_all, u); push!(post_all, post)
        end
    end
    (y=y_all, coords=coords, post=post_all, unit_ids=uid_all,
     treatment_sites=treat_sites, n_units=n_units)
end

function make_ols_data(n=100; seed=6, spatial_corr=0.5)
    rng    = MersenneTwister(seed)
    coords = hcat(rand(rng, n) .* 5, rand(rng, n) .* 5)
    X      = randn(rng, n, 2)
    β_true = [1.0, -0.5]
    # Spatially correlated errors
    ε = spatial_corr .* (coords[:,1] .- 2.5) ./ 2.5 .+ randn(rng, n)
    y = X * β_true .+ ε
    (y=y, X=X, coords=coords)
end

function make_iv_data(n=200; seed=7, true_tau=4.0)
    rng  = MersenneTwister(seed)
    # Facility location
    fac  = [5.0 5.0]
    coords = hcat(rand(rng, n) .* 10, rand(rng, n) .* 10)
    # IV: inverse distance to facility
    Z    = 1.0 ./ (1.0 .+ [sqrt(sum((coords[i,:] .- fac[1,:]).^2)) for i in 1:n])
    # Confounder
    U    = randn(rng, n)
    X    = randn(rng, n, 1)
    # Endogenous treatment: D depends on Z and U
    D    = clamp.(Z .+ 0.5*randn(rng, n), 0, 1)
    y    = true_tau .* D .+ X[:,1] .+ 0.5*U .+ randn(rng, n)
    (y=y, D=D, Z=Z, X=X, coords=coords, true_tau=true_tau)
end

@testset "Spatial DiD direct effect" begin
    d   = make_panel_spatial()
    rng = MersenneTwister(40)
    res = spatial_did(d.y, d.coords, d.post, d.treatment_sites;
                      radius=1.5, buffer=1.0, unit_ids=d.unit_ids, n_boot=50, rng=rng)
    @test isfinite(res.β_direct)
    @test isfinite(res.β_spillover)
    @test res.se_direct > 0.0
    @test res.se_spillover > 0.0
    @test res.n == length(d.y)
    @test res.n_treated + res.n_spillover + res.n_control == d.n_units
end

@testset "Spatial DiD confidence intervals" begin
    d   = make_panel_spatial()
    rng = MersenneTwister(41)
    res = spatial_did(d.y, d.coords, d.post, d.treatment_sites;
                      radius=1.5, buffer=1.0, unit_ids=d.unit_ids, n_boot=50, rng=rng)
    @test res.ci_direct[1] < res.β_direct < res.ci_direct[2]
    @test res.ci_spillover[1] < res.β_spillover < res.ci_spillover[2]
end

@testset "Spillover decomposition" begin
    d   = make_panel_spatial()
    rng = MersenneTwister(42)
    res = spatial_did(d.y, d.coords, d.post, d.treatment_sites;
                      radius=1.5, buffer=1.0, unit_ids=d.unit_ids, n_boot=30, rng=rng)
    sd  = spillover_decomposition(res)
    @test isfinite(sd.ratio)
    @test sd.n_treated >= 0
    @test sd.n_spillover >= 0
    @test sd.n_control >= 0
end

@testset "Conley spatial HAC SE" begin
    d   = make_ols_data()
    res = conley_se(d.y, d.X, d.coords; cutoff=2.0)
    @test length(res.β) == 3  # intercept + 2 covariates
    @test all(res.se_conley .>= 0.0)
    @test all(res.se_ols .>= 0.0)
    # Conley SE should differ from OLS SE (spatial corr present)
    @test !all(isapprox.(res.se_conley, res.se_ols; rtol=0.01))
end

@testset "Conley with default bandwidth" begin
    d   = make_ols_data()
    res = conley_se(d.y, d.X, d.coords)
    @test res.cutoff > 0.0
    @test length(res.p_values) == 3
    @test all(0.0 .<= res.p_values .<= 1.0)
end

@testset "Geographic IV first stage" begin
    d   = make_iv_data()
    res = geo_iv_2sls(d.y, d.D, d.Z, d.X)
    @test length(res.β_first) == 3  # intercept + Z + X
    @test res.r2_first >= 0.0
    @test isfinite(res.f_stat)
    # Z should be relevant (strong instrument)
    @test res.f_stat > 1.0
end

@testset "Geographic IV second stage" begin
    d   = make_iv_data(; true_tau=4.0)
    res = geo_iv_2sls(d.y, d.D, d.Z, d.X)
    @test length(res.β_2sls) == 3  # intercept + treatment + X
    @test isfinite(res.β_2sls[2])  # treatment effect
    @test all(res.se_2sls .>= 0.0)
end

@testset "Weak instrument test" begin
    d   = make_iv_data()
    res = geo_iv_2sls(d.y, d.D, d.Z, d.X)
    wt  = weak_instrument_test(res)
    @test isfinite(wt.f_stat)
    @test isa(wt.weak, Bool)
    @test isa(wt.very_weak, Bool)
end

@testset "Spatial causal report" begin
    d1  = make_panel_spatial(20)
    rng = MersenneTwister(99)
    dr  = spatial_did(d1.y, d1.coords, d1.post, d1.treatment_sites;
                      radius=1.5, buffer=1.0, unit_ids=d1.unit_ids, n_boot=30, rng=rng)
    d2  = make_ols_data(60)
    cr  = conley_se(d2.y, d2.X, d2.coords)
    d3  = make_iv_data(80)
    ir  = geo_iv_2sls(d3.y, d3.D, d3.Z, d3.X)
    rpt = spatial_causal_report(study_name="Test";
                                 spatial_did_result=dr, conley_result=cr, geo_iv_result=ir)
    @test rpt.n_obs == length(d1.y)
    @test isfinite(rpt.direct_effect)
    @test isfinite(rpt.iv_tau)
    @test isfinite(rpt.se_inflation)
end
