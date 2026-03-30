using Test, Random, SparseArrays, LinearAlgebra
using SpatialStats

Random.seed!(42)

# ── helpers ──────────────────────────────────────────────────────────────────

function make_chain_weights(n::Int)
    # Simple chain: i~i+1 for i in 1:n-1 (row-standardised)
    Is = Int[]; Js = Int[]; Vs = Float64[]
    for i in 1:n-1
        push!(Is, i, i+1); push!(Js, i+1, i); push!(Vs, 1.0, 1.0)
    end
    W = sparse(Is, Js, Vs, n, n)
    # row-standardise manually
    row_sums = vec(sum(W; dims=2))
    rows, cols, vals = findnz(W)
    for k in eachindex(rows)
        vals[k] /= row_sums[rows[k]]
    end
    W = sparse(rows, cols, vals, n, n)
    SpatialStats.SpatialWeights(W, n,
        SpatialStats.RowStandardizedStyle(),
        SpatialStats.DistanceTransform(),
        0, 1.5, 1, 2)
end

# ── haversine_km ──────────────────────────────────────────────────────────────
@testset "haversine_km" begin
    # NYC (40.71, -74.01) to LA (34.05, -118.24) ≈ 3944 km
    d = SpatialStats.haversine_km(40.71, -74.01, 34.05, -118.24)
    @test 3900.0 < d < 4000.0

    # Same point → 0
    @test SpatialStats.haversine_km(45.0, -90.0, 45.0, -90.0) ≈ 0.0
end

# ── lag_spatial ───────────────────────────────────────────────────────────────
@testset "lag_spatial" begin
    n = 5
    w = make_chain_weights(n)
    y = Float64.(1:n)
    lag = lag_spatial(w, y)
    @test length(lag) == n
    # Node 1 has only one neighbour (node 2); lag[1] = 2.0
    @test lag[1] ≈ 2.0
end

# ── moran ─────────────────────────────────────────────────────────────────────
@testset "moran permutation" begin
    n  = 30
    w  = make_chain_weights(n)
    # Clustered pattern: high on left, low on right → positive autocorrelation
    y_clust = vcat(fill(10.0, 15), fill(1.0, 15))
    r = moran(y_clust, w; permutations=499)
    @test r.I > 0.0
    @test -1.0 ≤ r.I ≤ 1.0
    @test 0.0 ≤ r.p_value ≤ 1.0

    # Random pattern → near-zero I
    y_rand = randn(n)
    r2 = moran(y_rand, w; permutations=199)
    @test -1.0 ≤ r2.I ≤ 1.0
end

@testset "moran analytical" begin
    n = 20
    w = make_chain_weights(n)
    y = randn(n)
    r = moran(y, w; method=:analytical)
    @test r.method == :analytical
    @test -1.0 ≤ r.I ≤ 1.0
end

# ── geary ─────────────────────────────────────────────────────────────────────
@testset "geary" begin
    n = 20
    w = make_chain_weights(n)
    y = vcat(fill(10.0, 10), fill(1.0, 10))
    r = geary(y, w; permutations=199)
    @test r.I < 1.0   # positive spatial autocorrelation → C < 1
    @test 0.0 ≤ r.p_value ≤ 1.0
end

# ── lisa ──────────────────────────────────────────────────────────────────────
@testset "lisa clusters" begin
    n = 20
    w = make_chain_weights(n)
    # Strong spatial pattern
    y = vcat(fill(10.0, 10), fill(1.0, 10))
    r = lisa(y, w; permutations=199, alpha=0.05)
    @test length(r.cluster_type) == n
    @test all(t ∈ (:HH, :LL, :HL, :LH, :NS) for t in r.cluster_type)
    @test r.n == n
end

# ── getis_ord ─────────────────────────────────────────────────────────────────
@testset "getis_ord" begin
    n = 20
    w = make_chain_weights(n)
    y = abs.(randn(n)) .+ 1.0
    r = getis_ord(y, w; star=true, permutations=99)
    @test length(r.z_scores) == n
    @test all(0.0 .≤ r.p_values .≤ 1.0)
end

# ── OLS + LM tests ────────────────────────────────────────────────────────────
@testset "lm_spatial OLS" begin
    n = 30
    w = make_chain_weights(n)
    X = hcat(ones(n), randn(n))
    β_true = [2.0, 3.0]
    y = X * β_true + 0.5 * randn(n)
    r = lm_spatial(y, X, w; coef_names=["intercept","x1"])
    @test r.model_type == :OLS
    @test length(r.coefficients) == 2
    @test r.r_squared > 0.5
    @test 0.0 ≤ r.lm_lag_p ≤ 1.0
    @test 0.0 ≤ r.lm_error_p ≤ 1.0
end

# ── SLM ───────────────────────────────────────────────────────────────────────
@testset "slm" begin
    n = 30
    w = make_chain_weights(n)
    X = hcat(ones(n), randn(n))
    y = X * [1.0, 2.0] + 0.5 * randn(n)
    r = slm(y, X, w)
    @test r.model_type == :SLM
    @test -1.0 ≤ r.rho_or_lambda ≤ 1.0
    @test r.AIC < Inf
    @test length(r.residuals) == n
end

# ── SEM ───────────────────────────────────────────────────────────────────────
@testset "sem" begin
    n = 30
    w = make_chain_weights(n)
    X = hcat(ones(n), randn(n))
    y = X * [1.0, 2.0] + 0.3 * randn(n)
    r = sem(y, X, w)
    @test r.model_type == :SEM
    @test r.AIC < Inf
end

# ── SDM ───────────────────────────────────────────────────────────────────────
@testset "sdm" begin
    n = 30
    w = make_chain_weights(n)
    X = hcat(ones(n), randn(n))
    y = X * [1.0, 2.0] + 0.3 * randn(n)
    r = sdm(y, X, w)
    @test r.model_type == :SDM
    @test length(r.coefficients) > 2   # has lagged X terms
end

# ── Type stability ────────────────────────────────────────────────────────────
@testset "type stability" begin
    n = 10
    w = make_chain_weights(n)
    y = randn(n)
    @test isa(lag_spatial(w, y), Vector{Float64})
    r = moran(y, w; permutations=99)
    @test isa(r.I, Float64)
    @test isa(r.p_value, Float64)
end
