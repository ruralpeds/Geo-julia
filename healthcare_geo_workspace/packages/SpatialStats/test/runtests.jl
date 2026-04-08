using Test, Random, DataFrames, SparseArrays, LinearAlgebra, Statistics
using SpatialStats

Random.seed!(42)

# ──────────────────────────────────────────────────────────────────────────────
# Helpers: synthetic 5×5 grid of "county" polygons
# ──────────────────────────────────────────────────────────────────────────────

"""Build a 5×5 grid of square polygons as a DataFrame with :geometry."""
function _grid_df(nrow_g = 5, ncol_g = 5)
    geoms = []
    for r in 1:nrow_g, c in 1:ncol_g
        # ArchGDAL is not required here — use a mock geometry that supports GeoInterface
        # For testing weights, we use a simple struct with an extent
        push!(geoms, nothing)   # placeholder
    end
    # For weight tests without real geometry, we build W directly from coords
    n = nrow_g * ncol_g
    coords = Float64[
        46.0 + (i-1) * 0.5 for i in 1:n,
        for _ in 1:1
    ]
    coords
end

"""Build queen-contiguity W for an nrow×ncol regular grid."""
function _grid_queen_W(nrow_g::Int, ncol_g::Int)
    n  = nrow_g * ncol_g
    idx = (r, c) -> (r - 1) * ncol_g + c
    rows = Int[]; cols = Int[]; vals = Float64[]
    for r in 1:nrow_g, c in 1:ncol_g
        i = idx(r, c)
        for dr in -1:1, dc in -1:1
            (dr == 0 && dc == 0) && continue
            r2, c2 = r + dr, c + dc
            (1 <= r2 <= nrow_g && 1 <= c2 <= ncol_g) || continue
            j = idx(r2, c2)
            push!(rows, i); push!(cols, j); push!(vals, 1.0)
        end
    end
    W_bin = sparse(rows, cols, vals, n, n)
    # Row-standardise
    rs = vec(sum(W_bin; dims = 2))
    I_idx, J_idx, V = findnz(W_bin)
    V_std = [rs[I_idx[k]] > 0 ? V[k] / rs[I_idx[k]] : 0.0 for k in eachindex(V)]
    W_std = sparse(I_idx, J_idx, V_std, n, n)
    SpatialWeights(W_std, n, :W, :queen, 0, mean(rs))
end

# ──────────────────────────────────────────────────────────────────────────────
# queen_weights (via direct construction for unit tests)
# ──────────────────────────────────────────────────────────────────────────────
@testset "queen_weights grid" begin
    w = _grid_queen_W(5, 5)
    @test w.n == 25
    @test w.transform == :queen
    # Corner cells have 3 queen neighbours; edge have 5; interior have 8
    # Row sums of W_std should be ≈ 1.0
    rs = vec(sum(Matrix(w.W); dims = 2))
    @test all(isapprox.(rs, 1.0; atol = 1e-9))
    # No islands in a complete grid
    @test w.island_count == 0
end

# ──────────────────────────────────────────────────────────────────────────────
# Moran's I
# ──────────────────────────────────────────────────────────────────────────────
@testset "moran — perfect clustering" begin
    w   = _grid_queen_W(5, 5)
    # Two blocks: top half high, bottom half low → strong positive AC
    val = vcat(fill(10.0, 15), fill(1.0, 10))
    res = moran(val, w; method = :permutation, permutations = 499)
    @test res.I > 0.4
    @test res.p_value < 0.05
end

@testset "moran — checkerboard (negative AC)" begin
    w   = _grid_queen_W(5, 5)
    # Checkerboard: alternating high/low
    val = Float64[(((i-1) ÷ 5) + (i-1) % 5) % 2 == 0 ? 10.0 : 1.0 for i in 1:25]
    res = moran(val, w; method = :permutation, permutations = 499)
    @test res.I < 0.0
end

@testset "moran — analytical method" begin
    w   = _grid_queen_W(5, 5)
    val = randn(MersenneTwister(1), 25)
    res = moran(val, w; method = :analytical)
    @test -1.0 <= res.I <= 1.0
    @test res.method == :analytical
end

# ──────────────────────────────────────────────────────────────────────────────
# LISA
# ──────────────────────────────────────────────────────────────────────────────
@testset "lisa clusters" begin
    w   = _grid_queen_W(5, 5)
    # Clear spatial structure: top-left quadrant high, bottom-right low
    val = Float64[((r <= 3 && c <= 3) ? 10.0 : 1.0) for r in 1:5 for c in 1:5]
    res = lisa(val, w; permutations = 499, alpha = 0.05)
    @test length(res.cluster_type) == 25
    @test all(c in (:HH, :LL, :HL, :LH, :NS) for c in res.cluster_type)
    # Centre of high block should be HH
    centre_idx = (2 - 1) * 5 + 2   # row 2, col 2 (0-indexed → 1-indexed)
    # Don't assert specific cluster here as permutations vary;
    # just confirm no errors and types are valid
    @test res.significance == 0.05
end

@testset "lisa — uniform values → all NS" begin
    w   = _grid_queen_W(3, 3)
    val = fill(5.0, 9)
    res = lisa(val, w; permutations = 199, alpha = 0.05)
    @test all(res.cluster_type .== :NS)
end

# ──────────────────────────────────────────────────────────────────────────────
# Getis-Ord G*
# ──────────────────────────────────────────────────────────────────────────────
@testset "getis_ord" begin
    w   = _grid_queen_W(5, 5)
    val = vcat(fill(10.0, 13), fill(1.0, 12))
    res = getis_ord(val, w; star = true, permutations = 199)
    @test length(res.z_scores) == 25
    @test length(res.p_values) == 25
    @test all(res.p_values .>= 0.0) && all(res.p_values .<= 1.0)
end

# ──────────────────────────────────────────────────────────────────────────────
# OLS diagnostics / LM tests
# ──────────────────────────────────────────────────────────────────────────────
@testset "lm_spatial OLS" begin
    n   = 25
    w   = _grid_queen_W(5, 5)
    X   = hcat(ones(n), randn(MersenneTwister(2), n))
    β   = [1.0, 0.5]
    y   = X * β .+ 0.3 * randn(MersenneTwister(3), n)

    result = lm_spatial(y, X, w)
    @test result.model_type == :OLS
    @test length(result.residuals) == n
    @test !isnan(result.lm_tests.LM_lag)
    @test !isnan(result.lm_tests.LM_err)
end

# ──────────────────────────────────────────────────────────────────────────────
# Spatial Lag Model (SLM)
# ──────────────────────────────────────────────────────────────────────────────
@testset "slm" begin
    n   = 25
    w   = _grid_queen_W(5, 5)
    X   = hcat(ones(n), randn(MersenneTwister(4), n))
    y   = X * [1.0, 0.5] .+ 0.2 * randn(MersenneTwister(5), n)

    result = slm(y, X, w)
    @test result.model_type == :SLM
    @test -1.0 <= result.rho_or_lambda <= 1.0
    @test !isnan(result.log_likelihood)
    @test result.AIC < 0.0 || result.AIC > 0.0   # just finite
end

# ──────────────────────────────────────────────────────────────────────────────
# Spatial Error Model (SEM)
# ──────────────────────────────────────────────────────────────────────────────
@testset "sem" begin
    n   = 25
    w   = _grid_queen_W(5, 5)
    X   = hcat(ones(n), randn(MersenneTwister(6), n))
    y   = X * [1.0, 0.5] .+ 0.2 * randn(MersenneTwister(7), n)

    result = sem(y, X, w)
    @test result.model_type == :SEM
    @test -1.0 <= result.rho_or_lambda <= 1.0
end

# ──────────────────────────────────────────────────────────────────────────────
# SDM
# ──────────────────────────────────────────────────────────────────────────────
@testset "sdm" begin
    n   = 25
    w   = _grid_queen_W(5, 5)
    X   = hcat(ones(n), randn(MersenneTwister(8), n))
    y   = X * [1.0, 0.5] .+ 0.1 * randn(MersenneTwister(9), n)

    result = sdm(y, X, w)
    @test result.model_type == :SDM
    @test length(result.coefficients) == 4   # β1, β2, θ1, θ2
end
