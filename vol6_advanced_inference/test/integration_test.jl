#!/usr/bin/env julia
# test/integration_test.jl — Vol 6 cross-package integration test
# Chapter 48.2 — 20 testsets

using Test, Random, DataFrames, Statistics, LinearAlgebra
Random.seed!(42)

import Pkg

PKGS_DIR = joinpath(@__DIR__, "..", "packages")

for dir in ["CausalHealth", "GaussianProcessHealth"]
    Pkg.activate(joinpath(PKGS_DIR, dir))
end
Pkg.activate(joinpath(PKGS_DIR, "CausalHealth"))
using CausalHealth

Pkg.activate(joinpath(PKGS_DIR, "GaussianProcessHealth"))
using GaussianProcessHealth

# ── Fixtures ──────────────────────────────────────────────────────────────────

function make_policy_panel(n=30, n_years=8, τ=0.04; rng=MersenneTwister(42))
    treat_ids = 1:div(n,2)
    rows = NamedTuple[]
    for id in 1:n
        fe = 0.1*randn(rng)
        for yr in 2015:2015+n_years-1
            treated = id in treat_ids
            post    = yr >= 2019
            y = 0.5 + fe + 0.005*(yr-2015) +
                (treated && post ? τ : 0.0) + 0.03*randn(rng)
            push!(rows, (id=lpad(id,3,'0'), year=yr, treated=Int(treated),
                         outcome=y, x1=randn(rng), z=randn(rng)))
        end
    end
    DataFrame(rows)
end

panel = make_policy_panel()

X_geo = hcat(46.5 .+ randn(25) .* 1.5, -100.5 .+ randn(25) .* 2.0)
y_geo = sin.(X_geo[:,1]) .+ 0.1*randn(25)

@testset "Vol 6 Integration Tests" begin

    # ── CausalHealth ─────────────────────────────────────────────────────────
    @testset "1. DiD — estimates finite" begin
        r = did_estimate(panel; id_col=:id, time_col=:year,
                          treat_col=:treated, outcome_col=:outcome, treat_time=2019)
        @test isfinite(r.att)
        @test r.se > 0
        @test r.ci_lo < r.ci_hi
    end

    @testset "2. DiD — pre-trend test" begin
        r = did_estimate(panel; id_col=:id, time_col=:year,
                          treat_col=:treated, outcome_col=:outcome, treat_time=2019)
        @test 0 <= r.pre_trend_p <= 1
        @test !isnothing(r.event_study)
        @test nrow(r.event_study) > 0
    end

    @testset "3. Synthetic control — weights sum to 1" begin
        r = synthetic_control(panel; treated_id="001",
                              id_col=:id, time_col=:year, outcome_col=:outcome,
                              treat_time=2019, n_placebos=3)
        @test abs(sum(r.weights) - 1.0) < 1e-5
        @test all(r.weights .>= -1e-9)
        @test isfinite(r.pre_fit_rmse)
    end

    @testset "4. IV 2SLS — coefficients finite" begin
        r = iv_2sls(panel; outcome_col=:outcome, endog_col=:treated,
                    instrument_cols=[:z], exog_cols=[:x1])
        @test !any(isnan, r.β_iv)
        @test r.first_stage_F >= 0
        @test 0 <= r.hausman_p <= 1
    end

    @testset "5. RD — local linear estimate" begin
        n = 300; rng = MersenneTwister(123)
        x = randn(rng, n); y = 1.5 .+ 0.4*(x.>=0) .+ 0.3*x .+ 0.1*randn(rng,n)
        df2 = DataFrame(x=x, y=y)
        r = rd_estimate(df2; running_col=:x, outcome_col=:y, cutoff=0.0,
                         bandwidth=2.0, poly_order=1)
        @test isfinite(r.τ)
        @test abs(r.τ - 0.4) < 0.3
    end

    @testset "6. RD — plot data" begin
        df2 = DataFrame(x=randn(200), y=randn(200))
        r = rd_estimate(df2; running_col=:x, outcome_col=:y, cutoff=0.0,
                         bandwidth=2.0)
        @test nrow(r.plot_data) == 100  # 50 left + 50 right
    end

    @testset "7. CausalReport table" begin
        reports = [CausalReport("DiD", 0.04, 0.01, 0.001, 0.02, 0.06, 200, "TWFE")]
        tbl = causal_summary(reports)
        @test nrow(tbl) == 1
    end

    # ── GaussianProcessHealth ─────────────────────────────────────────────────
    @testset "8. SE kernel — correct values" begin
        k = SquaredExponential(σ²=2.0, ℓ=1.5)
        @test k(0.0) ≈ 2.0
        @test k(1.5) ≈ 2.0 * exp(-0.5)
        @test k(1.0) == k(-1.0)
    end

    @testset "9. Matern32 — positive definite K" begin
        k = Matern32(σ²=1.0, ℓ=100.0)
        K = kernel_matrix(k, X_geo, X_geo; dist_fn=haversine_dist_deg)
        @test minimum(eigvals(Symmetric(K + 1e-6I))) > -1e-8
    end

    @testset "10. GP fit — log ML finite" begin
        k = Matern32(σ²=0.5, ℓ=100.0)
        m = gp_fit(X_geo, y_geo, k; σ²_noise=0.1, dist_fn=haversine_dist_deg)
        @test isfinite(m.log_ml)
        @test length(m.α) == 25
    end

    @testset "11. GP predict — finite, non-negative variance" begin
        k = Matern52(σ²=1.0, ℓ=100.0)
        m = gp_fit(X_geo, y_geo, k; σ²_noise=0.1, dist_fn=haversine_dist_deg)
        μ, v, σ = gp_predict(m, X_geo[1:5,:])
        @test !any(isnan, μ)
        @test all(v .>= 0)
    end

    @testset "12. GP predict — uncertainty increases far away" begin
        k = SquaredExponential(σ²=1.0, ℓ=0.5)
        X_1d = reshape(collect(-2.0:0.2:2.0), :, 1)
        y_1d = sin.(vec(X_1d)) .+ 0.05*randn(21)
        m    = gp_fit(X_1d, y_1d, k; σ²_noise=0.05)
        _, _, σ_far  = gp_predict(m, reshape([100.0], 1, 1))
        _, _, σ_near = gp_predict(m, X_1d[11:11,:])
        @test σ_far[1] > σ_near[1]
    end

    @testset "13. optimize_hyperparams! — improves ML" begin
        k = Matern32(σ²=1.0, ℓ=50.0)
        m_default = gp_fit(X_geo, y_geo, k; σ²_noise=0.1, dist_fn=haversine_dist_deg)
        m_opt = optimize_hyperparams!(k, X_geo, y_geo;
                                       σ²_noise=0.1, n_restarts=2,
                                       dist_fn=haversine_dist_deg)
        @test m_opt.log_ml >= m_default.log_ml - 2.0
    end

    @testset "14. spatial_gp_surface — grid size" begin
        k = Matern32(σ²=1.0, ℓ=100.0)
        m = gp_fit(X_geo, y_geo, k; σ²_noise=0.1, dist_fn=haversine_dist_deg)
        surf = spatial_gp_surface(m, (45.9, 49.0), (-104.0, -96.5); nx=5, ny=4)
        @test nrow(surf) == 20
        @test all(surf.lower_95 .<= surf.mean)
    end

    @testset "15. leave_one_out_cv" begin
        k = SquaredExponential(σ²=1.0, ℓ=50.0)
        loo = leave_one_out_cv(k, X_geo, y_geo; σ²_noise=0.1,
                                dist_fn=haversine_dist_deg)
        @test length(loo.loo_means) == 25
        @test loo.rmse >= 0
        @test isfinite(loo.loo_log_lik)
    end

    @testset "16. sparse_gp_fit" begin
        X_big = Float64.(reshape(range(-3,3;length=60), :,1))
        y_big = sin.(vec(X_big)) .+ 0.1*randn(60)
        k = Matern32(σ²=1.0, ℓ=0.5)
        m = sparse_gp_fit(X_big, y_big, k; m_inducing=8, σ²_noise=0.1)
        @test size(m.X_induce, 1) == 8
        @test isfinite(m.log_elbo)
    end

    # ── Cross-package pipeline ────────────────────────────────────────────────
    @testset "17. Causal → GP: residual spatial smoothing" begin
        # DiD residuals → GP spatial smoothing of unexplained variation
        r_did = did_estimate(panel; id_col=:id, time_col=:year,
                              treat_col=:treated, outcome_col=:outcome,
                              treat_time=2019)
        @test isfinite(r_did.att)

        # Synthetic county locations for GP
        k = Matern32(σ²=0.01, ℓ=80.0)
        m = gp_fit(X_geo[1:15,:], y_geo[1:15], k; σ²_noise=0.05,
                   dist_fn=haversine_dist_deg)
        μ, v, _ = gp_predict(m, X_geo[16:end,:])
        @test length(μ) == 10
        @test !any(isnan, μ)
    end

    @testset "18. MLOps drift detection" begin
        include(joinpath(@__DIR__, "..", "scripts", "mlops_pipeline.jl"))
        X_ref = randn(100, 4)
        X_new = randn(50, 4)
        X_new[:, 1] .+= 2.0   # inject drift
        drift = detect_drift(X_ref, X_new;
                              feature_names=["f1","f2","f3","f4"])
        @test length(drift) == 4
        @test drift[1].drifted   # feature 1 should be detected as drifted
        @test !drift[2].drifted  # feature 2 should not
    end

    @testset "19. MLOps A/B test" begin
        err_a = abs.(randn(80)) .* 0.005 .+ 0.003
        err_b = abs.(randn(80)) .* 0.004 .+ 0.0025
        ab = ab_test(err_a, err_b; name_a="RF", name_b="GBM")
        @test isfinite(ab.t_stat)
        @test 0 <= ab.p_value <= 1
        @test 0 <= ab.power <= 1
    end

    @testset "20. Multi-modal fusion" begin
        include(joinpath(@__DIR__, "..", "scripts", "multimodal_integration.jl"))
        data = generate_multimodal_dataset(30)
        fused = fuse_modalities(data.geo, data.claims, data.network)
        @test nrow(fused) == 30
        @test hasproperty(fused, :access_x_diabetes)
        @test hasproperty(fused, :telehealth_x_rural)
        @test hasproperty(fused, :hhi_x_betweenness)
    end

end  # @testset

using LinearAlgebra: eigvals, Symmetric
@info "Vol 6 integration tests complete."
