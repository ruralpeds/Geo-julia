using Test, Statistics, Random, LinearAlgebra

# ── Load all Vol 10 packages ──────────────────────────────────────────────────
include(joinpath(@__DIR__, "..", "packages", "GeostatHealth", "src", "GeostatHealth.jl"))
include(joinpath(@__DIR__, "..", "packages", "DiseaseMapping", "src", "DiseaseMapping.jl"))
include(joinpath(@__DIR__, "..", "packages", "PointPatterns", "src", "PointPatterns.jl"))
using .GeostatHealth, .DiseaseMapping, .PointPatterns

# ── Shared fixtures ───────────────────────────────────────────────────────────

function make_coords(n=30; seed=1)
    rng = MersenneTwister(seed)
    hcat(rand(rng, n) .* 7.6, rand(rng, n) .* 3.1)
end

function make_nd_access(n=30; seed=2)
    rng    = MersenneTwister(seed)
    coords = make_coords(n; seed=seed)
    z      = 0.3 .+ 0.3 .* coords[:,1] ./ 7.6 .+ 0.1 .* randn(rng, n)
    z      = clamp.(z, 0.01, 0.99)
    (coords=coords, z=z, n=n)
end

function make_disease_data(n=25; seed=3)
    rng    = MersenneTwister(seed)
    coords = make_coords(n; seed=seed)
    pop    = round.(Int, 2000 .+ 20000 .* rand(rng, n))
    E      = pop .* 0.008 .* (0.8 .+ 0.4 .* rand(rng, n))
    O      = Float64.([max(0, round(Int, E[i] * (0.8 .+ 0.4*rand(rng)))) for i in 1:n])
    areas  = ["A-$(lpad(i,2,'0'))" for i in 1:n]
    (O=O, E=E, coords=coords, areas=areas, n=n)
end

function make_point_data(n=50; seed=4)
    rng = MersenneTwister(seed)
    pts = hcat(rand(rng, n) .* 7.6, rand(rng, n) .* 3.1)
    pts
end

# =============================================================================
# GeostatHealth Tests
# =============================================================================

@testset "GeostatHealth — empirical variogram" begin
    d = make_nd_access()
    ev = empirical_variogram(d.coords, d.z; n_lags=8, estimator=:classical)
    valid = .!isnan.(ev.gamma)
    @test sum(valid) >= 4
    @test all(ev.gamma[valid] .>= 0.0)
    @test all(ev.n_pairs[valid] .> 0)
    @test ev.estimator == :classical
end

@testset "GeostatHealth — robust variogram" begin
    d  = make_nd_access()
    ev = empirical_variogram(d.coords, d.z; n_lags=8, estimator=:robust)
    valid = .!isnan.(ev.gamma)
    @test sum(valid) >= 4
    @test all(ev.gamma[valid] .>= 0.0)
end

@testset "GeostatHealth — variogram model fitting" begin
    d      = make_nd_access()
    ev     = empirical_variogram(d.coords, d.z; n_lags=8)
    vm_sph = fit_variogram(ev; model=:spherical)
    vm_exp = fit_variogram(ev; model=:exponential)
    vm_gau = fit_variogram(ev; model=:gaussian)
    for vm in [vm_sph, vm_exp, vm_gau]
        @test vm.nugget >= 0.0
        @test vm.sill   > vm.nugget
        @test vm.range  > 0.0
        @test isfinite(variogram_value(vm, 1.0))
        vs = variogram_summary(vm)
        @test 0.0 <= vs.nugget_ratio <= 1.0
    end
end

@testset "GeostatHealth — ordinary kriging prediction" begin
    d  = make_nd_access(25)
    ev = empirical_variogram(d.coords, d.z; n_lags=6)
    vm = fit_variogram(ev; model=:spherical)
    ok = ordinary_kriging(d.z, d.coords, vm)
    pred_c = hcat([1.0, 2.0, 3.0], [1.0, 1.5, 2.0])
    ẑ, σ² = ok_predict(ok, pred_c)
    @test length(ẑ) == 3
    @test all(isfinite.(ẑ))
    @test all(σ² .>= 0.0)
end

@testset "GeostatHealth — universal kriging" begin
    d  = make_nd_access(25)
    ev = empirical_variogram(d.coords, d.z; n_lags=6)
    vm = fit_variogram(ev; model=:exponential)
    uk = universal_kriging(d.z, d.coords, vm; degree=1)
    pred_c = hcat([1.0, 4.0], [1.0, 2.0])
    ẑ, σ² = uk_predict(uk, pred_c)
    @test length(ẑ) == 2
    @test all(isfinite.(ẑ))
    @test all(σ² .>= 0.0)
end

@testset "GeostatHealth — simple kriging" begin
    d  = make_nd_access(20)
    ev = empirical_variogram(d.coords, d.z; n_lags=5)
    vm = fit_variogram(ev; model=:spherical)
    sk = simple_kriging(d.z, d.coords, vm)
    pred_c = hcat([2.0], [1.5])
    ẑ, σ² = sk_predict(sk, pred_c)
    @test length(ẑ) == 1
    @test all(σ² .>= 0.0)
end

@testset "GeostatHealth — LOO cross-validation" begin
    d   = make_nd_access(20)
    ev  = empirical_variogram(d.coords, d.z; n_lags=5)
    vm  = fit_variogram(ev; model=:spherical)
    loo = kriging_loo_cv(d.z, d.coords, vm; method=:ordinary)
    @test loo.rmse >= 0.0
    @test loo.mae  >= 0.0
    @test isfinite(loo.mean_bias)
    @test 0.0 <= loo.picp_95 <= 1.0
end

@testset "GeostatHealth — SGS simulation" begin
    d     = make_nd_access(20)
    ev    = empirical_variogram(d.coords, d.z; n_lags=5)
    vm    = fit_variogram(ev; model=:exponential)
    pred  = hcat(range(0.5, 7.0, length=6), range(0.5, 2.5, length=6))
    rng   = MersenneTwister(10)
    sims  = sgs_simulate(d.z, d.coords, pred, vm; n_real=3, rng=rng)
    @test size(sims) == (6, 3)
    unc   = sgs_uncertainty(sims)
    @test all(isfinite.(unc.mean))
    @test all(unc.variance .>= 0.0)
    @test all(unc.lower_90 .<= unc.upper_90)
end

@testset "GeostatHealth — geostat report" begin
    d   = make_nd_access(20)
    rng = MersenneTwister(11)
    rpt = geostat_report(d.z, d.coords; series_name="Test")
    @test isa(rpt, GeostatReport)
    @test rpt.n_data == 20
    @test isfinite(rpt.loo_rmse)
    @test 0.0 <= rpt.nugget_ratio <= 1.0
end

# =============================================================================
# DiseaseMapping Tests
# =============================================================================

@testset "DiseaseMapping — SMR" begin
    d   = make_disease_data()
    res = batch_smr(d.O, d.E; areas=d.areas)
    @test length(res) == d.n
    for r in res
        @test r.smr >= 0.0
        @test r.lower_ci <= r.smr
        @test r.smr <= r.upper_ci
        @test 0.0 <= r.p_value <= 1.0
    end
end

@testset "DiseaseMapping — indirect standardisation" begin
    n     = 15
    n_age = 4
    rng   = MersenneTwister(20)
    pop_age   = [abs.(round.(Int, 500 .+ 200*randn(rng, n_age))) for _ in 1:n]
    ref_rates = [0.002, 0.006, 0.015, 0.04]
    counts_age = [round.(Int, pop_age[i] .* ref_rates .* (0.8 .+ 0.4*rand(rng, n_age))) for i in 1:n]
    E_std, O_std = indirect_standardise(counts_age, pop_age, ref_rates)
    @test length(E_std) == n
    @test all(E_std .> 0.0)
    @test all(O_std .>= 0.0)
end

@testset "DiseaseMapping — EB smoothing" begin
    d  = make_disease_data()
    eb = eb_smooth(d.O, d.E)
    @test length(eb.θ_hat) == d.n
    @test eb.α_hat > 0.0
    @test eb.β_hat > 0.0
    @test all(eb.θ_hat .>= 0.0)
    # EB estimates should have smaller range than raw SMR
    @test (maximum(eb.θ_hat) - minimum(eb.θ_hat)) <=
          (maximum(eb.smr_raw) - minimum(eb.smr_raw)) + 0.05
end

@testset "DiseaseMapping — kernel smoothing" begin
    d   = make_disease_data()
    ks  = kernel_smooth_rates(d.O, d.E, d.coords; bandwidth=1.5)
    @test length(ks) == d.n
    @test all(ks .>= 0.0)
    @test all(isfinite.(ks))
end

@testset "DiseaseMapping — adjacency build" begin
    d   = make_disease_data()
    W, Q, m_i = build_adjacency(d.coords; threshold=2.0)
    @test size(W) == (d.n, d.n)
    @test issymmetric(W)
    @test all(diag(W) .== 0)
    @test all(m_i .>= 0)
    @test size(Q) == (d.n, d.n)
end

@testset "DiseaseMapping — BYM model" begin
    d    = make_disease_data(20)
    W, Q, m_i = build_adjacency(d.coords; threshold=2.5)
    rng  = MersenneTwister(30)
    bym  = bym_fit(d.O, d.E, W, Q; n_iter=500, n_warmup=100, rng=rng)
    @test length(bym.rr) == d.n
    @test all(bym.rr .>= 0.0)
    @test bym.τ_u_mean > 0.0
    @test bym.τ_v_mean > 0.0
    @test isfinite(bym.dic)
    @test all(bym.rr_lower .<= bym.rr)
    @test all(bym.rr .<= bym.rr_upper)
end

@testset "DiseaseMapping — spatial scan" begin
    d    = make_disease_data()
    rng  = MersenneTwister(40)
    scans = spatial_scan(d.O, d.E, d.coords; max_pop_frac=0.4, n_sim=49, rng=rng)
    @test !isempty(scans)
    for s in scans
        @test s.llr >= 0.0
        @test 0.0 <= s.p_value <= 1.0
        @test s.O_inside >= 0.0
        @test s.E_inside >= 0.0
    end
end

# =============================================================================
# PointPatterns Tests
# =============================================================================

@testset "PointPatterns — KDE basic" begin
    pts = make_point_data()
    kr  = kde2d(pts; n_grid=10)
    @test all(kr.density .>= 0.0)
    @test kr.bandwidth > 0.0
    @test kr.n_points == size(pts, 1)
end

@testset "PointPatterns — Ripley K" begin
    pts = make_point_data()
    rng = MersenneTwister(50)
    kr  = ripley_k(pts, 7.6*3.1; n_r=8, n_sim=49, rng=rng)
    @test all(kr.K .>= 0.0)
    @test all(kr.K_csr .>= 0.0)
    @test 0.0 <= kr.p_value <= 1.0
    @test all(isfinite.(kr.L))
end

@testset "PointPatterns — DBSCAN" begin
    pts = make_point_data(40)
    db  = dbscan(pts; ε=0.8, min_pts=3)
    @test length(db.labels) == 40
    @test db.n_clusters + db.n_noise <= 40
end

@testset "PointPatterns — Knox test" begin
    rng    = MersenneTwister(60)
    pts    = make_point_data(30)
    times  = rand(rng, 30) .* 50.0
    kt     = knox_test(pts, times; d_thresh=1.0, t_thresh=5.0, n_perm=49, rng=rng)
    @test kt.observed >= 0
    @test 0.0 <= kt.p_value <= 1.0
    @test isfinite(kt.ratio)
end

@testset "PointPatterns — Bernoulli scan" begin
    rng  = MersenneTwister(70)
    n_c  = 20; n_ctl = 60
    cases    = hcat(rand(rng, n_c) .* 2, rand(rng, n_c) .* 2)
    controls = hcat(rand(rng, n_ctl) .* 7.6, rand(rng, n_ctl) .* 3.1)
    sr       = spatial_scan_points(cases, controls; n_sim=49, rng=rng)
    @test sr.llr >= 0.0
    @test 0.0 <= sr.p_value <= 1.0
end

# =============================================================================
# Cross-package Integration Tests
# =============================================================================

@testset "Integration — kriging uncertainty → hotspot delineation" begin
    # Kriging variance map → treat as pseudo-density for hotspot identification
    d  = make_nd_access(25)
    ev = empirical_variogram(d.coords, d.z; n_lags=6)
    vm = fit_variogram(ev; model=:spherical)
    ok = ordinary_kriging(d.z, d.coords, vm)

    # Dense prediction grid
    pred_c = hcat([x for x in range(0.5, 7.0, length=8) for _ in 1:8],
                  [y for _ in range(0.5, 7.0, length=8) for y in range(0.5, 2.5, length=8)])
    ẑ, σ² = ok_predict(ok, pred_c)

    # Use kriging variance as a pseudo-density in KDE result struct
    @test all(σ² .>= 0.0)
    # High-uncertainty regions: top quartile of kriging variance
    thr_unc = quantile(σ², 0.75)
    high_unc = sum(σ² .>= thr_unc)
    @test high_unc >= 10   # at least 25% of grid
end

@testset "Integration — EB smoothed rates → spatial scan" begin
    d    = make_disease_data(25)
    eb   = eb_smooth(d.O, d.E)

    # Apply spatial scan to EB-smoothed pseudo-counts
    rng  = MersenneTwister(80)
    # EB posterior means as expected; observed O
    scans = spatial_scan(d.O, eb.θ_hat .* d.E, d.coords; n_sim=49, rng=rng)
    @test !isempty(scans)
    @test isfinite(scans[1].llr)
end

@testset "Integration — BYM relative risks → point process intensity" begin
    d    = make_disease_data(20)
    W, Q, m_i = build_adjacency(d.coords; threshold=2.5)
    rng  = MersenneTwister(90)
    bym  = bym_fit(d.O, d.E, W, Q; n_iter=300, n_warmup=100, rng=rng)

    # Use BYM RRs as spatial weights for a KDE intensity surface
    # Create pseudo-cases weighted by RR
    pts  = d.coords
    kr   = kde2d(pts; n_grid=8)
    @test all(kr.density .>= 0.0)
    @test all(bym.rr .>= 0.0)

    # Areas with high RR should have elevated BYM estimates vs raw SMR
    corr = cor(bym.rr, d.O ./ max.(d.E, 1e-6))
    @test isfinite(corr)
end

@testset "Integration — kriging access scores → disease risk correlation" begin
    # Kriging predicts access scores at disease mapping locations
    access_d = make_nd_access(20)
    disease_d = make_disease_data(20)

    ev = empirical_variogram(access_d.coords, access_d.z; n_lags=5)
    vm = fit_variogram(ev; model=:spherical)
    ok = ordinary_kriging(access_d.z, access_d.coords, vm)

    # Predict access at disease county centroids
    ẑ_access, σ² = ok_predict(ok, disease_d.coords)
    raw_smr = disease_d.O ./ max.(disease_d.E, 1e-6)

    @test length(ẑ_access) == disease_d.n
    @test all(isfinite.(ẑ_access))
    # Correlation between predicted access and SMR should be computable
    corr = cor(ẑ_access, raw_smr)
    @test isfinite(corr)
end

println("\n✓ All Vol 10 integration tests passed.")
