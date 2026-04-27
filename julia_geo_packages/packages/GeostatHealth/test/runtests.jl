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
    @test length(ev.lags)  == 10
    @test length(ev.gamma) == 10
    valid = .!isnan.(ev.gamma)
    @test any(valid)
    @test all(ev.gamma[valid] .>= 0.0)
    # The default lag_max covers half the domain — pairs within that range only
    total_possible = 50 * 49 ÷ 2
    @test 0 < sum(ev.n_pairs) <= total_possible
end

@testset "Empirical variogram — robust estimator" begin
    z, c = make_spatial_data(40)
    ev_r = empirical_variogram(c, z; n_lags=8, estimator=:robust)
    valid = .!isnan.(ev_r.gamma)
    @test all(ev_r.gamma[valid] .>= 0.0)
end

@testset "Cloud variogram" begin
    z, c = make_spatial_data(30)
    cv = cloud_variogram(c, z)
    expected_pairs = 30 * 29 ÷ 2
    @test cv.n_pairs == expected_pairs
    @test length(cv.distances) == expected_pairs
    @test length(cv.gamma)     == expected_pairs
    @test all(cv.distances .>= 0.0)
    @test all(cv.gamma     .>= 0.0)
    # cloud gamma should equal (z_i - z_j)^2 / 2
    @test cv.gamma[1] ≈ (z[1] - z[2])^2 / 2.0 atol=1e-12
end

@testset "Variogram plot text" begin
    z, c = make_spatial_data(40)
    ev   = empirical_variogram(c, z; n_lags=8)
    txt  = variogram_plot_text(ev; title="Test variogram")
    @test occursin("Test variogram", txt)
    @test occursin("γ(h)", txt)
    # has at least some non-whitespace content
    @test length(strip(txt)) > 10
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

@testset "Covariance: C(0) = sill, C(∞) ≈ 0" begin
    vm = VariogramModel(:spherical, 0.1, 1.0, 4.0, 1.5)
    @test covariance_value(vm, 0.0) ≈ vm.sill atol=1e-10
    # Spherical is bounded: γ(h ≥ range) = sill → C(h) = sill − sill = 0
    @test covariance_value(vm, 1000.0) ≈ 0.0 atol=1e-8
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

@testset "OK local neighbourhood prediction" begin
    z, c  = make_spatial_data(40)
    ev    = empirical_variogram(c, z; n_lags=8)
    vm    = fit_variogram(ev)
    ok    = ordinary_kriging(z, c, vm)
    pred_c = hcat([5.0, 10.0, 15.0], [5.0, 10.0, 15.0])
    ẑ, σ² = ok_predict_local(ok, pred_c; max_neighbors=16)
    @test length(ẑ) == 3
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

@testset "Kriging LOO CV — metrics and standardised residuals" begin
    z, c = make_spatial_data(25)
    ev   = empirical_variogram(c, z; n_lags=6)
    vm   = fit_variogram(ev)
    loo  = kriging_loo_cv(z, c, vm; method=:ordinary)
    @test loo.rmse >= 0.0
    @test loo.mae  >= 0.0
    @test 0.0 <= loo.picp_95 <= 1.0
    @test loo.n == 25
    @test length(loo.std_residuals) == 25
    @test all(isfinite.(loo.std_residuals))
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

@testset "Raster — create_grid" begin
    g = create_grid(0.0:2.0:10.0, 0.0:2.0:8.0)
    @test g.nx == 6
    @test g.ny == 5
    @test size(g.coords) == (30, 2)
    @test g.coords[1,:] == [0.0, 0.0]
end

@testset "Raster — zonal_statistics" begin
    z, c = make_spatial_data(50)
    bbox = BoundingBox(0.0, 10.0, 0.0, 10.0)
    stats = zonal_statistics(z, c, bbox)
    @test !isnothing(stats)
    @test stats.n > 0
    @test isfinite(stats.mean)
    @test stats.min <= stats.mean <= stats.max

    # Empty bbox
    bbox2 = BoundingBox(100.0, 200.0, 100.0, 200.0)
    @test isnothing(zonal_statistics(z, c, bbox2))
end

@testset "Raster — kriging_grid" begin
    z, c = make_spatial_data(30)
    ev   = empirical_variogram(c, z; n_lags=6)
    vm   = fit_variogram(ev)
    ok   = ordinary_kriging(z, c, vm)
    res  = kriging_grid(ok, 2.0:4.0:18.0, 2.0:4.0:18.0; max_neighbors=10)
    @test size(res.z_hat) == (length(res.y), length(res.x))
    @test size(res.sigma2) == size(res.z_hat)
    @test all(isfinite.(res.z_hat))
    @test all(res.sigma2 .>= 0.0)
end

@testset "Raster — uncertainty_surface" begin
    z, c = make_spatial_data(25)
    ev   = empirical_variogram(c, z; n_lags=6)
    vm   = fit_variogram(ev)
    ok   = ordinary_kriging(z, c, vm)
    g    = create_grid(1.0:4.0:17.0, 1.0:4.0:17.0)
    surf = uncertainty_surface(ok, g; max_neighbors=12)
    @test surf.grid.nx == g.nx && surf.grid.ny == g.ny
    @test size(surf.z_hat)    == (g.ny, g.nx)
    @test size(surf.sigma2)   == (g.ny, g.nx)
    @test size(surf.lower_95) == (g.ny, g.nx)
    @test size(surf.upper_95) == (g.ny, g.nx)
    @test all(surf.lower_95 .<= surf.upper_95)
end

@testset "Raster — synthetic WorldPop / GHSL grids" begin
    bbox = BoundingBox(0.0, 5.0, 0.0, 5.0)
    wp = synthetic_worldpop_grid(bbox; resolution=1.0)
    @test isa(wp.grid, RasterGrid)
    @test length(wp.density) == wp.grid.nx * wp.grid.ny
    @test all(wp.density .> 0.0)   # log-normal, always positive

    gh = synthetic_ghsl_grid(bbox; resolution=1.0)
    @test length(gh.built_up) == gh.grid.nx * gh.grid.ny
    @test all(0.0 .<= gh.built_up .<= 1.0)
end
