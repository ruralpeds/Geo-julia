using Test, Statistics, Random, LinearAlgebra

include(joinpath(@__DIR__, "..", "src", "GeostatHealth.jl"))
using .GeostatHealth

function make_spatial_data(n=40; seed=1, nugget=0.1, sill=1.0, range_val=5.0)
    rng    = MersenneTwister(seed)
    coords = hcat(rand(rng, n) .* 20, rand(rng, n) .* 20)
    # Simple spatial structure: smooth surface + nugget noise
    z = [sin(coords[i,1]/5) + cos(coords[i,2]/5) + sqrt(nugget)*randn(rng)
         for i in 1:n]
    Float64.(z), coords
end

@testset "Empirical variogram — basic properties" begin
    z, c = make_spatial_data(50)
    ev = empirical_variogram(c, z; n_lags=10)
    @test length(ev.lags)  >= 1
    @test length(ev.gamma) == length(ev.lags)
    valid = .!isnan.(ev.gamma)
    @test any(valid)
    @test all(ev.gamma[valid] .>= 0.0)
    @test sum(ev.n_pairs) > 0
end

@testset "Empirical variogram — robust estimator" begin
    z, c = make_spatial_data(40)
    ev_r = empirical_variogram(c, z; n_lags=8, estimator=:robust)
    valid = .!isnan.(ev_r.gamma)
    @test all(ev_r.gamma[valid] .>= 0.0)
end

@testset "Variogram models — value at 0" begin
    for m in [:spherical, :exponential, :gaussian, :matern]
        vm = VariogramModel(m, 0.1, 1.0, 5.0, 1.5)
        @test variogram_value(vm, 0.0) == 0.0
        @test variogram_value(vm, 0.0) == 0.0
    end
end

@testset "Variogram models — sill at large lag" begin
    vm_s = VariogramModel(:spherical,    0.0, 1.0, 3.0, 1.5)
    vm_e = VariogramModel(:exponential,  0.0, 1.0, 3.0, 1.5)
    vm_g = VariogramModel(:gaussian,     0.0, 1.0, 3.0, 1.5)
    @test variogram_value(vm_s, 10.0) ≈ 1.0 atol=1e-10
    @test variogram_value(vm_e, 100.0) ≈ 1.0 atol=1e-4
    @test variogram_value(vm_g, 100.0) ≈ 1.0 atol=1e-4
end

@testset "Variogram models — non-decreasing" begin
    vm = VariogramModel(:spherical, 0.05, 1.0, 5.0, 1.5)
    lags = 0.0:0.5:10.0
    vals = [variogram_value(vm, h) for h in lags]
    diffs = diff(vals)
    @test all(diffs .>= -1e-10)
end

@testset "Covariance: C(0) = sill, C(∞) ≈ nugget" begin
    vm = VariogramModel(:spherical, 0.1, 1.0, 4.0, 1.5)
    @test covariance_value(vm, 0.0) ≈ vm.sill atol=1e-10
    @test covariance_value(vm, 1000.0) ≈ vm.nugget atol=1e-8
end

@testset "Variogram fitting — spherical" begin
    z, c = make_spatial_data(60; sill=1.0, range_val=5.0, nugget=0.05)
    ev = empirical_variogram(c, z; n_lags=12)
    vm = fit_variogram(ev; model=:spherical, range_init=5.0, sill_init=1.0)
    @test vm.model == :spherical
    @test vm.sill  > vm.nugget
    @test vm.range > 0.0
    @test vm.nugget >= 0.0
end

@testset "Variogram fitting — exponential and Gaussian" begin
    z, c = make_spatial_data(40)
    ev = empirical_variogram(c, z; n_lags=8)
    vm_e = fit_variogram(ev; model=:exponential)
    vm_g = fit_variogram(ev; model=:gaussian)
    @test isfinite(vm_e.sill) && vm_e.sill > 0
    @test isfinite(vm_g.range) && vm_g.range > 0
end

@testset "Ordinary kriging — interpolation" begin
    z, c   = make_spatial_data(30)
    ev     = empirical_variogram(c, z; n_lags=8)
    vm     = fit_variogram(ev; model=:spherical)
    ok     = ordinary_kriging(z, c, vm)
    # Predict at training locations (should be close to z)
    ẑ, σ²  = ok_predict(ok, c[1:5,:])
    @test all(isfinite.(ẑ))
    @test all(σ² .>= 0.0)
end

@testset "Simple kriging" begin
    z, c  = make_spatial_data(25)
    ev    = empirical_variogram(c, z; n_lags=6)
    vm    = fit_variogram(ev)
    sk    = simple_kriging(z, c, vm)
    ẑ, σ² = sk_predict(sk, c[1:4,:])
    @test length(ẑ) == 4
    @test all(σ² .>= 0.0)
end

@testset "Universal kriging — trend removal" begin
    rng  = MersenneTwister(5)
    n    = 30
    c    = hcat(rand(rng, n)*10, rand(rng, n)*10)
    z    = c[:,1] .* 0.3 .+ c[:,2] .* (-0.1) .+ 0.2*randn(rng, n)
    ev   = empirical_variogram(c, z; n_lags=6)
    vm   = fit_variogram(ev; model=:exponential)
    uk   = universal_kriging(z, c, vm; degree=1)
    ẑ, σ² = uk_predict(uk, c[1:5,:])
    @test all(isfinite.(ẑ))
    @test all(σ² .>= 0.0)
end

@testset "Kriging LOO CV" begin
    z, c = make_spatial_data(25)
    ev   = empirical_variogram(c, z; n_lags=6)
    vm   = fit_variogram(ev)
    loo  = kriging_loo_cv(z, c, vm; method=:ordinary)
    @test loo.rmse >= 0.0
    @test loo.mae  >= 0.0
    @test 0.0 <= loo.picp_95 <= 1.0
    @test loo.n == 25
end

@testset "SGS simulation" begin
    rng  = MersenneTwister(7)
    z, c = make_spatial_data(20)
    ev   = empirical_variogram(c, z; n_lags=6)
    vm   = fit_variogram(ev)
    pred_c = hcat(rand(rng,8)*20, rand(rng,8)*20)
    sims = sgs_simulate(z, c, pred_c, vm; n_real=5, rng=rng)
    @test size(sims) == (8, 5)
    @test all(isfinite.(sims))

    unc = sgs_uncertainty(sims)
    @test length(unc.mean) == 8
    @test all(unc.variance .>= 0.0)
    @test all(unc.lower_90 .<= unc.upper_90)
end

@testset "GeostatReport" begin
    z, c = make_spatial_data(30)
    r    = geostat_report(z, c; series_name="TestSurface")
    @test isa(r, GeostatReport)
    @test r.n_data == 30
    @test isfinite(r.loo_rmse)
    @test 0.0 <= r.nugget_ratio <= 1.0
end
