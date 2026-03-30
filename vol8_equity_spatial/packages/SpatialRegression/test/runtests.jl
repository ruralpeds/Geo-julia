#!/usr/bin/env julia
# test/runtests.jl — SpatialRegression.jl unit tests

using Test, Random, LinearAlgebra, Statistics
using SpatialRegression

Random.seed!(42)

# ── Fixtures ──────────────────────────────────────────────────────────────────
rng = MersenneTwister(42)
n = 40; p = 3

# Random locations in a 10×10 grid (simulate ND counties)
coords = hcat(rand(rng, n) .* 10, rand(rng, n) .* 10)
X = randn(rng, n, p)

# Binary spatial weights (k-nearest neighbours, k=4)
D = distance_matrix(coords)
function make_knn_W(D, k)
    n = size(D, 1)
    W = zeros(n, n)
    for i in 1:n
        order = sortperm(D[i,:])
        for j in order[2:k+1]
            W[i,j] = 1.0
        end
    end
    # Row-normalise
    for i in 1:n
        rs = sum(W[i,:]); rs > 0 && (W[i,:] ./= rs)
    end
    W
end
W = make_knn_W(D, 4)

# Spatial lag DGP: y = 0.4Wy + Xβ + ε
β_true = [0.5, -0.3, 0.2]
ε = 0.1 * randn(rng, n)
A_inv = (I(n) .- 0.4W)
y = A_inv \ (X * β_true .+ ε)

@testset "SpatialRegression.jl" begin

    @testset "distance_matrix — symmetric, zero diagonal" begin
        D2 = distance_matrix(coords)
        @test size(D2) == (n, n)
        @test all(diag(D2) .== 0)
        @test D2 ≈ D2'
    end

    @testset "gaussian_kernel — decreasing, K(0)=1" begin
        @test gaussian_kernel(0.0, 1.0) ≈ 1.0
        @test gaussian_kernel(1.0, 1.0) < gaussian_kernel(0.5, 1.0)
        @test gaussian_kernel(10.0, 1.0) < 1e-10
    end

    @testset "bisquare_kernel — compact support" begin
        @test bisquare_kernel(0.0, 1.0) ≈ 1.0
        @test bisquare_kernel(1.0, 1.0) == 0.0
        @test bisquare_kernel(0.5, 1.0) > 0
    end

    @testset "bandwidth_aic — returns positive" begin
        b = bandwidth_aic(y, X, coords; n_candidates=6)
        @test b > 0
        @test isfinite(b)
    end

    @testset "GWR — fit and predict" begin
        b = bandwidth_aic(y, X, coords; n_candidates=6)
        m = gwr_fit(y, X, coords; bandwidth=b)
        @test m isa GWRModel
        @test m.n == n
        @test size(m.local_β) == (n, p+1)
        @test !any(isnan, m.local_β)
        @test !any(isnan, m.residuals)
    end

    @testset "GWR — local R² in [0,1]" begin
        m = gwr_fit(y, X, coords; bandwidth=3.0)
        @test all(-0.5 .<= m.local_r2 .<= 1.0)
    end

    @testset "gwr_summary — correct columns" begin
        m = gwr_fit(y, X, coords; bandwidth=3.0)
        df = gwr_summary(m)
        @test nrow(df) == n
        @test hasproperty(df, :local_r2)
        @test hasproperty(df, :residual)
    end

    @testset "GWR predict — output shape" begin
        m = gwr_fit(y, X, coords; bandwidth=3.0)
        X_new = randn(rng, 5, p)
        coords_new = rand(rng, 5, 2) .* 10
        ŷ = gwr_predict(m, X_new, coords_new)
        @test length(ŷ) == 5
        @test !any(isnan, ŷ)
    end

    @testset "Spatial lag — ρ and β finite" begin
        m = spatial_lag_fit(y, X, W; feature_names=["f1","f2","f3"])
        @test m isa SpatialLagModel
        @test abs(m.ρ) < 1.0
        @test length(m.β) == p+1
        @test all(isfinite, m.β)
        @test isfinite(m.log_lik)
    end

    @testset "Spatial lag — AIC finite" begin
        m = spatial_lag_fit(y, X, W)
        @test isfinite(m.aic)
        @test isfinite(m.bic)
        @test m.aic > 0
    end

    @testset "Spatial error — λ and β finite" begin
        m = spatial_error_fit(y, X, W)
        @test m isa SpatialErrorModel
        @test abs(m.λ) < 1.0
        @test all(isfinite, m.β)
        @test isfinite(m.log_lik)
    end

    @testset "Spatial error — fitted ≈ mean(y) when λ=0" begin
        m = spatial_error_fit(y, X, W)
        @test !any(isnan, m.fitted)
        @test !any(isnan, m.residuals)
    end

    @testset "Moran's I — finite test statistic" begin
        e_ols = y .- X * ((X'X + 1e-8I) \ X'y)
        mi = moran_residuals(e_ols, W; permutations=99)
        @test isfinite(mi.I)
        @test 0 <= mi.p <= 1
    end

    @testset "LM lag test — stat >= 0, p in [0,1]" begin
        e_ols = y .- hcat(ones(n), X) * ((hcat(ones(n),X)'*hcat(ones(n),X)+1e-8I) \ hcat(ones(n),X)'*y)
        r = lm_lag_test(e_ols, X, W)
        @test r.stat >= 0
        @test 0 <= r.p <= 1
    end

    @testset "LM error test — stat >= 0, p in [0,1]" begin
        e_ols = y .- hcat(ones(n), X) * ((hcat(ones(n),X)'*hcat(ones(n),X)+1e-8I) \ hcat(ones(n),X)'*y)
        r = lm_error_test(e_ols, X, W)
        @test r.stat >= 0
        @test 0 <= r.p <= 1
    end

    @testset "run_diagnostics — returns SpatialDiagnostics" begin
        e_ols = y .- hcat(ones(n), X) * ((hcat(ones(n),X)'*hcat(ones(n),X)+1e-8I) \ hcat(ones(n),X)'*y)
        diag = run_diagnostics(e_ols, X, W; permutations=99)
        @test diag isa SpatialDiagnostics
        @test isa(diag.recommend_lag, Bool)
        @test isa(diag.recommend_error, Bool)
    end

    @testset "GW-RF — fits and predicts" begin
        m_rf = gwrf_fit(y, X, coords; bandwidth=3.0, n_trees=10, max_depth=3, rng=rng)
        @test m_rf isa GWRFModel
        @test m_rf.global_rmse >= 0
        μ, σ = gwrf_predict(m_rf, X[1:5,:], coords[1:5,:]; rng=rng, n_trees=10)
        @test length(μ) == 5
        @test all(!isnan, μ)
        @test all(σ .>= 0)
    end

end  # @testset
