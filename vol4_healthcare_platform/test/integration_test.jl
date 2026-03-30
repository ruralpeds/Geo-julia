#!/usr/bin/env julia
# test/integration_test.jl — Vol 4 cross-package integration test
# Tests the full ND pipeline end-to-end using synthetic data.
# Run: julia --project=. test/integration_test.jl
# Vol 4 — Chapter 34.2

using Test, Random
Random.seed!(42)

# ── Package availability checks ───────────────────────────────────────────────

PACKAGES_DIR = joinpath(@__DIR__, "..", "packages")

# Load PointPatterns from local dev path
using Pkg
Pkg.activate(joinpath(PACKAGES_DIR, "PointPatterns"))
using PointPatterns
Pkg.activate(joinpath(@__DIR__, ".."))

# Load SpatialStats from Vol 3 workspace
const SS_PATH = joinpath(@__DIR__, "..", "..", "julia_geo_packages", "packages", "SpatialStats")
if isdir(SS_PATH)
    Pkg.activate(SS_PATH)
    using SpatialStats
    Pkg.activate(joinpath(@__DIR__, ".."))
    const SPATIAL_STATS_AVAILABLE = true
else
    @warn "SpatialStats.jl not found. Skipping autocorrelation tests."
    const SPATIAL_STATS_AVAILABLE = false
end

using DataFrames, CSV, Statistics, SparseArrays

# ── Synthetic North Dakota dataset ────────────────────────────────────────────

function make_synthetic_nd(n=53)
    Random.seed!(42)
    DataFrame(
        GEOID         = ["38" * lpad(i, 3, '0') for i in 1:n],
        NAME          = ["County $(i)" for i in 1:n],
        centroid_lat  = 46.5 .+ range(-2.0,  2.0;  length=n),
        centroid_lon  = -100.5 .+ range(-3.0, 3.0;  length=n),
        access_score  = abs.(randn(n)) .* 0.01 .+ 0.005,
        poverty_pct   = 5.0  .+ 15.0 .* rand(n),
        uninsured_pct = 8.0  .+ 12.0 .* rand(n),
        total_pop     = 1000 .+ round.(Int, 50_000 .* rand(n).^2),
    )
end

nd_df = make_synthetic_nd()

# ── Synthetic provider locations ──────────────────────────────────────────────

prov_df = DataFrame(
    lat = 46.8 .+ randn(30) .* 0.5,
    lon = -100.5 .+ randn(30) .* 1.0,
)

# ── Spatial weights helpers ───────────────────────────────────────────────────

function build_chain_weights(n::Int)
    Is = Int[]; Js = Int[]; Vs = Float64[]
    for i in 1:n-1
        push!(Is, i, i+1); push!(Js, i+1, i); push!(Vs, 1.0, 1.0)
    end
    for i in 1:n-8
        push!(Is, i, i+8); push!(Js, i+8, i); push!(Vs, 1.0, 1.0)
    end
    W = sparse(Is, Js, Vs, n, n)
    row_sums = vec(sum(W; dims=2))
    rows, cols, vals = findnz(W)
    for k in eachindex(rows); vals[k] /= row_sums[rows[k]]; end
    sparse(rows, cols, vals, n, n)
end

# ── Test suites ───────────────────────────────────────────────────────────────

@testset "Vol 4 Integration Tests" begin

    # ──────────────────────────────────────────────────────────────────────────
    @testset "1. Synthetic data integrity" begin
        @test nrow(nd_df) == 53
        @test all(nd_df.access_score .> 0)
        @test all(nd_df.total_pop .> 0)
        @test all(5.0 .<= nd_df.poverty_pct .<= 20.0)
        @test length(unique(nd_df.GEOID)) == 53
    end

    # ──────────────────────────────────────────────────────────────────────────
    @testset "2. PointPatterns — CSR simulation" begin
        win = RectWindow(-104.0, -96.5, 45.9, 49.0)
        pp  = simulate_csr(2.0, win)
        @test pp isa PointPattern
        @test pp.n > 0
        @test all(pp.x .>= win.xmin) && all(pp.x .<= win.xmax)
        @test all(pp.y .>= win.ymin) && all(pp.y .<= win.ymax)
    end

    @testset "3. PointPatterns — Kfunction" begin
        win = RectWindow(-104.0, -96.5, 45.9, 49.0)
        pp  = PointPattern(nd_df.centroid_lon, nd_df.centroid_lat,
                           nothing, win, nrow(nd_df))
        kdf = Kfunction(pp)
        @test kdf isa DataFrame
        @test hasproperty(kdf, :r) && hasproperty(kdf, :K)
        @test all(kdf.K .>= 0)
        @test all(kdf.r .>= 0)
        # K should be close to πr² for random points
        @test kdf.K[end] ≈ kdf.K_csr[end] rtol=0.5
    end

    @testset "4. PointPatterns — Gfunction" begin
        win = RectWindow(-104.0, -96.5, 45.9, 49.0)
        pp  = PointPattern(nd_df.centroid_lon, nd_df.centroid_lat,
                           nothing, win, nrow(nd_df))
        gdf = Gfunction(pp)
        @test gdf isa DataFrame
        @test hasproperty(gdf, :G)
        @test all(0 .<= gdf.G .<= 1)
        @test issorted(gdf.G)
    end

    @testset "5. PointPatterns — Clark-Evans test" begin
        win  = RectWindow(-104.0, -96.5, 45.9, 49.0)
        pp   = PointPattern(nd_df.centroid_lon, nd_df.centroid_lat,
                            nothing, win, nrow(nd_df))
        result = clarkevans_test(pp)
        @test haskey(result, :R)
        @test haskey(result, :p_value)
        @test result.R isa Float64
        @test 0 <= result.p_value <= 1
    end

    @testset "6. PointPatterns — Quadrat test" begin
        win = RectWindow(-104.0, -96.5, 45.9, 49.0)
        pp  = PointPattern(nd_df.centroid_lon, nd_df.centroid_lat,
                           nothing, win, nrow(nd_df))
        result = quadrat_test(pp; nx=4, ny=4)
        @test haskey(result, :chi2)
        @test haskey(result, :p_value)
        @test result.chi2 >= 0
    end

    @testset "7. PointPatterns — Kernel intensity" begin
        win = RectWindow(-104.0, -96.5, 45.9, 49.0)
        pp  = PointPattern(nd_df.centroid_lon, nd_df.centroid_lat,
                           nothing, win, nrow(nd_df))
        ki = kernel_intensity(pp; nx=10, ny=8)
        @test ki isa Matrix{Float64}
        @test size(ki) == (10, 8)
        @test all(ki .>= 0)
        @test sum(ki) > 0
    end

    @testset "8. PointPatterns — Scan statistic" begin
        n   = 30
        coords = hcat(randn(n), randn(n))
        pop    = rand(500:2000, n)
        cases  = rand(0:20, n)
        # Inject elevated rate in first 5 areas
        cases[1:5] .= round.(Int, pop[1:5] ./ 100 .* 3)
        result = scan_statistic(cases, pop, coords; max_pop_fraction=0.3,
                                 n_centers=20, nsim=99)
        @test haskey(result, :p_value)
        @test haskey(result, :llr)
        @test 0 <= result.p_value <= 1
    end

    @testset "9. PointPatterns — Envelope (CSR)" begin
        win = RectWindow(-104.0, -96.5, 45.9, 49.0)
        pp  = PointPattern(nd_df.centroid_lon[1:20], nd_df.centroid_lat[1:20],
                           nothing, win, 20)
        env = envelope(pp, Kfunction; nsim=19)
        @test hasproperty(env, :K_lo) && hasproperty(env, :K_hi)
        @test all(env.K_lo .<= env.K_hi)
    end

    # ──────────────────────────────────────────────────────────────────────────
    @testset "10. E2SFCA access computation" begin
        n  = nrow(nd_df)
        σ_km = 50.0 / 3.0
        access = zeros(Float64, n)
        for j in 1:nrow(prov_df)
            pl = Float64(prov_df.lat[j])
            lo = Float64(prov_df.lon[j])
            for i in 1:n
                dlat = pl - nd_df.centroid_lat[i]
                dlon = lo - nd_df.centroid_lon[i]
                d = sqrt(dlat^2 + dlon^2) * 111.0
                d <= 50.0 && (access[i] += exp(-d^2 / (2σ_km^2)))
            end
        end
        @test all(access .>= 0)
        @test maximum(access) > 0
        @test count(access .> 0) >= 1
    end

    # ──────────────────────────────────────────────────────────────────────────
    if SPATIAL_STATS_AVAILABLE
        n = nrow(nd_df)
        W_sp = build_chain_weights(n)

        @testset "11. SpatialStats — Moran's I" begin
            access_vals = Float64.(nd_df.access_score)
            w = SpatialStats.SpatialWeights(W_sp, n,
                    SpatialStats.RowStandardizedStyle(),
                    SpatialStats.QueenTransform(),
                    0, mean(vec(sum(W_sp .!= 0; dims=2))), 1, 8)
            r = moran(access_vals, w; permutations=99)
            @test r isa SpatialStats.MoranResult
            @test -1.0 <= r.I <= 1.0
            @test 0 <= r.p_value <= 1
            @test r.n_permutations == 99
        end

        @testset "12. SpatialStats — LISA clusters" begin
            access_vals = Float64.(nd_df.access_score)
            w = SpatialStats.SpatialWeights(W_sp, n,
                    SpatialStats.RowStandardizedStyle(),
                    SpatialStats.QueenTransform(),
                    0, mean(vec(sum(W_sp .!= 0; dims=2))), 1, 8)
            r = lisa(access_vals, w; permutations=99, alpha=0.05)
            @test length(r.cluster_type) == n
            @test all(c -> c in [:HH, :LL, :HL, :LH, :NS], r.cluster_type)
            @test length(r.p_values) == n
            @test all(0 .<= r.p_values .<= 1)
        end

        @testset "13. SpatialStats — Spatial regression" begin
            poverty_vals   = Float64.(nd_df.poverty_pct)
            uninsured_vals = Float64.(nd_df.uninsured_pct)
            access_vals    = Float64.(nd_df.access_score)
            w = SpatialStats.SpatialWeights(W_sp, n,
                    SpatialStats.RowStandardizedStyle(),
                    SpatialStats.QueenTransform(),
                    0, mean(vec(sum(W_sp .!= 0; dims=2))), 1, 8)
            X = hcat(ones(n), poverty_vals, uninsured_vals)
            y = (access_vals .- mean(access_vals)) ./ max(std(access_vals), 1e-9)

            ols = lm_spatial(y, X, w; coef_names=["intercept","poverty","uninsurance"])
            @test hasfield(typeof(ols), :AIC)
            @test hasfield(typeof(ols), :coefficients)
            @test length(ols.coefficients) == 3

            slm_result = slm(y, X, w; coef_names=["intercept","poverty","uninsurance"])
            @test hasfield(typeof(slm_result), :rho_or_lambda)
            @test -1.0 <= slm_result.rho_or_lambda <= 1.0
        end
    end

    # ──────────────────────────────────────────────────────────────────────────
    @testset "14. GPU fallback (CPU path)" begin
        include(joinpath(@__DIR__, "..", "scripts", "gpu_acceleration.jl"))
        lats = 46.5 .+ randn(20)
        lons = -100.5 .+ randn(20)
        D = haversine_matrix_cpu(lats, lons)
        @test size(D) == (20, 20)
        @test all(D .>= 0)
        @test all(D[diagind(D)] .== 0)
        # haversine_matrix_gpu falls back to CPU when no GPU
        D2 = haversine_matrix_gpu(lats, lons)
        @test D ≈ D2 atol=1e-3
    end

    @testset "15. GPU — Moran permutation CPU fallback" begin
        n_t = 20
        W_d = zeros(n_t, n_t)
        for i in 1:n_t-1; W_d[i,i+1] = W_d[i+1,i] = 0.5; end
        x   = randn(n_t)
        res = moran_permutation_gpu(x, sparse(W_d); permutations=199)
        @test haskey(res, :I_observed)
        @test haskey(res, :p_value)
        @test 0 <= res.p_value <= 1
        @test res.n_permutations == 199
    end

    # ──────────────────────────────────────────────────────────────────────────
    @testset "16. CSV pipeline round-trip" begin
        tmpdir = mktempdir()
        path   = joinpath(tmpdir, "nd_results.csv")
        out_df = select(nd_df, [:GEOID, :NAME, :access_score, :poverty_pct])
        CSV.write(path, out_df)
        @test isfile(path)
        back = CSV.read(path, DataFrame)
        @test nrow(back) == 53
        @test hasproperty(back, :access_score)
        @test back.access_score ≈ out_df.access_score atol=1e-6
    end

end  # @testset "Vol 4 Integration Tests"

@info "Vol 4 integration tests complete."
