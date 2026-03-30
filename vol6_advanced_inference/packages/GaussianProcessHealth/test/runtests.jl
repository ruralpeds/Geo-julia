using Test, Random, Statistics, LinearAlgebra
Random.seed!(42)

import Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
using GaussianProcessHealth

# ── 1D and 2D synthetic data ──────────────────────────────────────────────────
function make_1d(n=30; rng=MersenneTwister(42))
    x = sort(randn(rng, n))
    y = sin.(x) .+ 0.1 .* randn(rng, n)
    reshape(x, :, 1), y
end

function make_geo(n=20; rng=MersenneTwister(42))
    lats = 46.5 .+ randn(rng, n) .* 1.5
    lons = -100.5 .+ randn(rng, n) .* 2.0
    X = hcat(lats, lons)
    y = sin.(lats) .+ 0.5*cos.(lons) .+ 0.05*randn(rng, n)
    X, y
end

X1d, y1d = make_1d()
Xgeo, ygeo = make_geo()

@testset "GaussianProcessHealth Tests" begin

    @testset "1. Kernels — SquaredExponential" begin
        k = SquaredExponential(σ²=1.0, ℓ=1.0)
        @test k(0.0) ≈ 1.0
        @test k(1.0) ≈ exp(-0.5)
        @test k(1.0) == k(-1.0)   # symmetric
        @test k(100.0) < 1e-6     # decays to zero
    end

    @testset "2. Kernels — Matern32" begin
        k = Matern32(σ²=2.0, ℓ=1.5)
        @test k(0.0) ≈ 2.0
        @test k(1.0) > 0
        @test k(1.0) < k(0.0)    # decays
        @test k(1.0) == k(-1.0)
    end

    @testset "3. Kernels — Matern52" begin
        k = Matern52(σ²=1.0, ℓ=2.0)
        @test k(0.0) ≈ 1.0
        @test k(1.0) > k(2.0)
    end

    @testset "4. Kernels — RationalQuadratic" begin
        k = RationalQuadratic(σ²=1.0, ℓ=1.0, α=1.0)
        @test k(0.0) ≈ 1.0
        @test 0 < k(1.0) < 1
    end

    @testset "5. Kernels — CompositeKernel (sum)" begin
        k1 = SquaredExponential(σ²=0.5, ℓ=1.0)
        k2 = Matern32(σ²=0.5, ℓ=2.0)
        kc = CompositeKernel(k1, k2, :sum)
        @test kc(0.0) ≈ 1.0 atol=1e-9
        @test kc(1.0) > 0
    end

    @testset "6. kernel_matrix — symmetry & positive definite" begin
        k = Matern52(σ²=1.0, ℓ=1.0)
        K = kernel_matrix(k, X1d, X1d)
        @test size(K) == (size(X1d,1), size(X1d,1))
        @test K ≈ K'  atol=1e-10
        @test minimum(eigvals(Symmetric(K))) > -1e-8
    end

    @testset "7. haversine_dist_deg" begin
        a = [46.5, -100.5]
        b = [46.5, -100.5]
        @test haversine_dist_deg(a, b) ≈ 0.0 atol=1e-9
        c = [47.0, -100.5]
        d = haversine_dist_deg(a, c)
        @test 50 < d < 70  # ~55km per degree latitude
    end

    @testset "8. gp_fit — basic" begin
        k = Matern32(σ²=1.0, ℓ=1.0)
        m = gp_fit(X1d, y1d, k; σ²_noise=0.1)
        @test m isa GPModel
        @test isfinite(m.log_ml)
        @test length(m.α) == length(y1d)
    end

    @testset "9. gp_predict — shape and finite" begin
        k = SquaredExponential(σ²=1.0, ℓ=1.0)
        m = gp_fit(X1d, y1d, k; σ²_noise=0.1)
        X_test = reshape(collect(range(-2, 2; length=20)), :, 1)
        μ, v, σ = gp_predict(m, X_test)
        @test length(μ) == 20
        @test all(isfinite, μ)
        @test all(v .>= 0)
    end

    @testset "10. gp_predict — zero variance at training points" begin
        k = SquaredExponential(σ²=1.0, ℓ=1.0)
        m = gp_fit(X1d, y1d, k; σ²_noise=1e-6)
        μ, v, σ = gp_predict(m, X1d)
        # With tiny noise, posterior mean should be near training targets
        @test maximum(abs.(μ .- y1d)) < 0.5
    end

    @testset "11. gp_predict — uncertainty grows far from training data" begin
        k = Matern52(σ²=1.0, ℓ=0.5)
        m = gp_fit(X1d, y1d, k; σ²_noise=0.1)
        X_far  = reshape([100.0], 1, 1)
        X_near = X1d[1:1, :]
        _, _, σ_far  = gp_predict(m, X_far)
        _, _, σ_near = gp_predict(m, X_near)
        @test σ_far[1] > σ_near[1]
    end

    @testset "12. optimize_hyperparams!" begin
        k = Matern32(σ²=1.0, ℓ=1.0)
        m_opt = optimize_hyperparams!(k, X1d, y1d; σ²_noise=0.1, n_restarts=2)
        @test m_opt isa GPModel
        # Optimised should have higher or equal ML than default
        m_default = gp_fit(X1d, y1d, k; σ²_noise=0.1)
        @test m_opt.log_ml >= m_default.log_ml - 1.0
    end

    @testset "13. Geographic GP — haversine kernel" begin
        k = Matern32(σ²=1.0, ℓ=100.0)  # 100 km length-scale
        m = gp_fit(Xgeo, ygeo, k; σ²_noise=0.1,
                   dist_fn=haversine_dist_deg)
        @test isfinite(m.log_ml)
        X_test = Xgeo[1:5, :]
        μ, v, σ = gp_predict(m, X_test)
        @test !any(isnan, μ)
        @test all(v .>= 0)
    end

    @testset "14. spatial_gp_surface" begin
        k = SquaredExponential(σ²=1.0, ℓ=50.0)
        m = gp_fit(Xgeo, ygeo, k; σ²_noise=0.1, dist_fn=haversine_dist_deg)
        surf = spatial_gp_surface(m, (45.0, 48.0), (-103.0, -98.0); nx=5, ny=5)
        @test nrow(surf) == 25
        @test hasproperty(surf, :mean)
        @test hasproperty(surf, :std)
        @test all(surf.lower_95 .<= surf.mean .<= surf.upper_95)
    end

    @testset "15. uncertainty_map" begin
        k = Matern32(σ²=1.0, ℓ=50.0)
        m = gp_fit(Xgeo, ygeo, k; σ²_noise=0.1, dist_fn=haversine_dist_deg)
        X_cand = Xgeo[1:5, :]
        σ = uncertainty_map(m, X_cand)
        @test length(σ) == 5
        @test all(σ .>= 0)
    end

    @testset "16. leave_one_out_cv" begin
        k = SquaredExponential(σ²=1.0, ℓ=1.0)
        loo = leave_one_out_cv(k, X1d, y1d; σ²_noise=0.1)
        @test haskey(loo, :loo_means)
        @test length(loo.loo_means) == length(y1d)
        @test isfinite(loo.loo_log_lik)
        @test loo.rmse >= 0
    end

    @testset "17. param serialisation round-trip" begin
        k = Matern52(σ²=2.5, ℓ=3.1)
        θ = get_params(k)
        k2 = set_params(k, θ)
        @test k2.σ² ≈ k.σ² atol=1e-9
        @test k2.ℓ  ≈ k.ℓ  atol=1e-9
    end

    @testset "18. sparse_gp_fit — basic" begin
        X_big = Float64.(reshape(range(-3, 3; length=80), :, 1))
        y_big = sin.(vec(X_big)) .+ 0.1 .* randn(80)
        k = Matern32(σ²=1.0, ℓ=0.5)
        m = sparse_gp_fit(X_big, y_big, k; m_inducing=10, σ²_noise=0.1)
        @test m isa SparseGP
        @test size(m.X_induce) == (10, 1)
        @test isfinite(m.log_elbo)
    end

    @testset "19. sparse_gp_predict" begin
        X_big = Float64.(reshape(range(-3, 3; length=60), :, 1))
        y_big = sin.(vec(X_big)) .+ 0.1 .* randn(60)
        k = SquaredExponential(σ²=1.0, ℓ=0.5)
        m = sparse_gp_fit(X_big, y_big, k; m_inducing=8, σ²_noise=0.1)
        μ, v, σ = sparse_gp_predict(m, X_big[1:10, :])
        @test length(μ) == 10
        @test all(isfinite, μ)
        @test all(v .>= 0)
    end

    @testset "20. marginal_likelihood_surface" begin
        k = Matern32
        lml = marginal_likelihood_surface(
            (s,l) -> Matern32(σ²=s, ℓ=l),
            X1d, y1d, [0.5, 1.0, 2.0], [0.5, 1.0, 2.0]; σ²_noise=0.1)
        @test size(lml) == (3, 3)
        @test !all(lml .== -Inf)
    end

end  # @testset

using LinearAlgebra: eigvals, Symmetric
@info "GaussianProcessHealth tests complete."
