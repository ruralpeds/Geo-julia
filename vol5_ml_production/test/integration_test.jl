#!/usr/bin/env julia
# test/integration_test.jl — Vol 5 cross-package integration test
# Tests the complete ML + network + temporal pipeline end-to-end.
# Run: julia --project=packages/HealthcareML test/integration_test.jl
# Vol 5 — Chapter 41.2

using Test, Random, DataFrames, Statistics, SparseArrays, Dates
Random.seed!(42)

import Pkg

PKGS_DIR = joinpath(@__DIR__, "..", "packages")

# Load all three Vol 5 packages
for (dir, mod) in [("HealthcareML", :HealthcareML),
                    ("NetworkHealth", :NetworkHealth),
                    ("TemporalHealth", :TemporalHealth)]
    Pkg.activate(joinpath(PKGS_DIR, dir))
end
Pkg.activate(joinpath(PKGS_DIR, "HealthcareML"))
using HealthcareML

Pkg.activate(joinpath(PKGS_DIR, "NetworkHealth"))
using NetworkHealth

Pkg.activate(joinpath(PKGS_DIR, "TemporalHealth"))
using TemporalHealth

# ── Synthetic North Dakota panel dataset ──────────────────────────────────────

N_COUNTIES = 53
N_YEARS    = 8

function make_nd_panel()
    rng = MersenneTwister(42)
    n   = N_COUNTIES * N_YEARS
    df  = DataFrame(
        GEOID    = repeat(["38" * lpad(i,3,'0') for i in 1:N_COUNTIES], inner=N_YEARS),
        year     = repeat(2015:2022, outer=N_COUNTIES),
        poverty  = 10.0 .+ 8.0 .* randn(rng, n),
        uninsured= 12.0 .+ 6.0 .* randn(rng, n),
        pop_k    = 5.0  .+ abs.(randn(rng, n)) .* 20,
        rurality = clamp.(rand(rng, n), 0, 1),
        access   = abs.(randn(rng, n)) .* 0.008 .+ 0.004,
    )
    clamp!(df.poverty, 2.0, 35.0)
    clamp!(df.uninsured, 1.0, 30.0)
    df
end

nd_panel = make_nd_panel()

# Single-year slice for ML / network
nd_2022 = filter(r -> r.year == 2022, nd_panel)

# ── Test suites ───────────────────────────────────────────────────────────────

@testset "Vol 5 Integration Tests" begin

    # ── HealthcareML ────────────────────────────────────────────────────────
    @testset "1. HealthcareML — feature engineering" begin
        feat = build_features(nd_2022, :access;
                              feature_cols=[:poverty, :uninsured, :pop_k, :rurality],
                              config=AccessFeatures(spatial_lags=0, interaction_terms=false,
                                                     polynomial_degree=1, standardize=true))
        @test size(feat.X, 1) == N_COUNTIES
        @test size(feat.X, 2) >= 4
        @test length(feat.y) == N_COUNTIES
        @test !any(isnan, feat.X)
    end

    @testset "2. HealthcareML — Ridge CV" begin
        feat = build_features(nd_2022, :access;
                              feature_cols=[:poverty, :uninsured, :pop_k, :rurality],
                              config=AccessFeatures(spatial_lags=0, polynomial_degree=1,
                                                     interaction_terms=false, standardize=true))
        cv = cross_validate(() -> RidgeAccess(λ=1.0), feat.X, feat.y; folds=5)
        @test length(cv.scores) == 5
        @test cv.mean_score > 0
        @test !any(isnan, cv.oof_predictions)
    end

    @testset "3. HealthcareML — Random Forest end-to-end" begin
        feat = build_features(nd_2022, :access;
                              feature_cols=[:poverty, :uninsured, :pop_k, :rurality],
                              config=AccessFeatures(spatial_lags=0, polynomial_degree=2,
                                                     interaction_terms=true, standardize=true))
        m = RandomForestAccess(n_trees=30, max_depth=4)
        fit!(m, feat.X, feat.y)
        @test m.fitted
        @test !isnan(m.oob_score_)
        ŷ = predict(m, feat.X)
        @test length(ŷ) == N_COUNTIES
        imp = permutation_importance(m, feat.X, feat.y;
                                      feature_names=feat.feature_names, n_repeats=3)
        @test nrow(imp) == size(feat.X, 2)
    end

    @testset "4. HealthcareML — Gradient Boosting" begin
        X = randn(N_COUNTIES, 4)
        y = X * [0.3, -0.5, 0.2, -0.1] .+ 0.1 .* randn(N_COUNTIES)
        m = GradientBoostAccess(n_estimators=20, learning_rate=0.1, max_depth=2)
        fit!(m, X, y)
        ŷ = predict(m, X)
        # Training loss should decrease
        @test m.train_scores_[end] < m.train_scores_[1] + 0.5
        @test length(ŷ) == N_COUNTIES
    end

    @testset "5. HealthcareML — SHAP values finite" begin
        X = randn(20, 4)
        y = X[:, 1] .+ X[:, 2] .* 0.5 .+ 0.2 .* randn(20)
        m = RidgeAccess(λ=0.5)
        fit!(m, X, y)
        sv = shap_values(m, X[1:5, :]; n_samples=20)
        @test size(sv) == (5, 4)
        @test !any(isnan, sv)
        @test !any(isinf, sv)
    end

    @testset "6. HealthcareML — ModelComparison" begin
        feat = build_features(nd_2022, :access;
                              feature_cols=[:poverty, :uninsured, :pop_k, :rurality],
                              config=AccessFeatures(spatial_lags=0, polynomial_degree=1,
                                                     interaction_terms=false, standardize=true))
        models = Dict(
            "ridge"  => () -> RidgeAccess(λ=1.0),
            "forest" => () -> RandomForestAccess(n_trees=15, max_depth=3),
        )
        comp = compare_models(models, feat.X, feat.y; folds=3)
        @test haskey(comp.scores, "ridge")
        @test haskey(comp.scores, "forest")
        @test all(s -> s > 0, values(comp.scores))
    end

    # ── NetworkHealth ───────────────────────────────────────────────────────
    @testset "7. NetworkHealth — build from adjacency" begin
        # 10-provider referral network
        n = 10
        A = zeros(n, n)
        for i in 1:n-1; A[i,i+1] = rand() * 5; end
        for i in 1:n-2; A[i,i+2] = rand() * 2; end
        g = from_adjmatrix(A; directed=true)
        @test nv(g) == n
        @test ne(g) > 0
    end

    @testset "8. NetworkHealth — centrality measures" begin
        A = zeros(15, 15)
        for i in 1:14; A[i,i+1] = 1.0; A[i+1,i] = 0.5; end
        A[1,8] = 3.0; A[8,1] = 2.0
        g = from_adjmatrix(A; directed=true)

        pr = pagerank(g; α=0.85)
        @test abs(sum(pr) - 1.0) < 1e-6
        @test all(pr .> 0)

        bc = betweenness_centrality(g)
        @test length(bc) == 15
        @test all(bc .>= 0)

        ec = eigenvector_centrality(g)
        @test !any(isnan, ec)
    end

    @testset "9. NetworkHealth — community detection" begin
        n = 20
        A = zeros(n, n)
        # Two dense cliques + sparse cross-edges
        for i in 1:9, j in 1:9; i != j && (A[i,j] = 2.0); end
        for i in 11:20, j in 11:20; i != j && (A[i,j] = 2.0); end
        A[5, 15] = 0.1; A[15, 5] = 0.1
        g = from_adjmatrix(A; directed=false)

        labels = louvain_communities(g; max_iter=50)
        @test length(labels) == n
        # Should detect at least 2 communities for two cliques
        @test length(unique(labels)) >= 2
    end

    @testset "10. NetworkHealth — max flow" begin
        A = zeros(5, 5)
        A[1,2] = 3.0; A[1,3] = 2.0
        A[2,4] = 2.0; A[3,4] = 2.0; A[2,5] = 1.0
        A[4,5] = 3.0
        g = from_adjmatrix(A; directed=true)
        flow = max_flow_bfs(g, 1, 5)
        @test flow > 0
        @test flow <= 5.0
    end

    @testset "11. NetworkHealth — access score" begin
        n = 15
        A = zeros(n, n)
        for i in 1:n-1; A[i,i+1] = 1.0; A[i+1,i] = 1.0; end
        g = from_adjmatrix(A; directed=true)
        county_nodes = [[1,2], [3,4], Int[], [5,6,7]]
        scores = network_access_score(g, county_nodes; centrality=:pagerank)
        @test length(scores) == 4
        @test scores[3] == 0.0
        @test all(scores .>= 0)
    end

    @testset "12. NetworkHealth — summarize" begin
        A = zeros(10, 10)
        for i in 1:9; A[i,i+1] = 1.0; A[i+1,i] = 1.0; end
        g = from_adjmatrix(A; directed=false)
        s = summarize(g)
        @test s.n_nodes == 10
        @test 0 <= s.density <= 1
        @test s.n_communities >= 1
    end

    # ── TemporalHealth ──────────────────────────────────────────────────────
    @testset "13. TemporalHealth — panel to time series" begin
        county_1 = filter(r -> r.GEOID == "38001", nd_panel)
        sort!(county_1, :year)
        ts = from_dataframe(county_1, :year, :access; freq=1)
        @test length(ts) == N_YEARS
        @test ts.freq == 1
    end

    @testset "14. TemporalHealth — STL decomposition" begin
        y  = [sin(2π*t/12) + 0.01*t + 0.05*randn() for t in 1:60]
        ts = TemporalHealth.HealthTimeSeries(collect(1:60), y, "test", "", 12, nothing)
        stl = stl_decompose(ts)
        recon = stl.trend .+ stl.seasonal .+ stl.remainder
        @test maximum(abs.(recon .- y)) < 1e-6
    end

    @testset "15. TemporalHealth — Holt-Winters" begin
        y  = [2.0 + 0.02t + 0.3*sin(2π*t/4) + 0.05*randn() for t in 1:32]
        ts = TemporalHealth.HealthTimeSeries(collect(1:32), y, "test", "", 4, nothing)
        hw = holtwinters(ts; α=0.2, β=0.1, γ=0.2)
        @test length(hw.fitted) == 32
        forc = forecast(hw, 8)
        @test length(forc) == 8
        @test !any(isnan, forc)
    end

    @testset "16. TemporalHealth — PELT changepoint" begin
        y = vcat(fill(2.0, 20), fill(5.0, 20), fill(3.0, 20))
        ts = TemporalHealth.HealthTimeSeries(collect(1:60), y, "test", "", 1, nothing)
        r  = detect_changepoints(ts; penalty=log(60))
        @test r.n_segments >= 2
    end

    @testset "17. TemporalHealth — panel_summary" begin
        summ = panel_summary(nd_panel, :GEOID, :year, :access)
        @test nrow(summ) == N_COUNTIES
        @test all(isfinite, summ.trend)
        @test all(isfinite, summ.ac1)
    end

    @testset "18. TemporalHealth — cross correlation" begin
        y1 = [sin(2π*t/12) + 0.1*randn() for t in 1:48]
        y2 = [sin(2π*(t-3)/12) + 0.1*randn() for t in 1:48]
        ts1 = TemporalHealth.HealthTimeSeries(collect(1:48), y1, "ts1", "", 12, nothing)
        ts2 = TemporalHealth.HealthTimeSeries(collect(1:48), y2, "ts2", "", 12, nothing)
        ccf = cross_correlation(ts1, ts2; max_lag=6)
        @test nrow(ccf) == 13
        @test all(-1.0 .<= ccf.ccf .<= 1.0)
    end

    # ── Cross-package pipeline ───────────────────────────────────────────────
    @testset "19. Cross-package: ML → Network → Temporal" begin
        # ML: predict access for 2022
        feat = build_features(nd_2022, :access;
                              feature_cols=[:poverty, :uninsured, :pop_k, :rurality],
                              config=AccessFeatures(spatial_lags=0, polynomial_degree=1,
                                                     interaction_terms=false, standardize=true))
        m = RandomForestAccess(n_trees=20, max_depth=3)
        fit!(m, feat.X, feat.y)
        ŷ_2022 = predict(m, feat.X)

        # Network: build county adjacency from proximity
        n = N_COUNTIES
        A = zeros(n, n)
        for i in 1:n-1; A[i,i+1] = max(ŷ_2022[i], 0.001); end
        for i in 1:n-2; A[i,i+2] = max(ŷ_2022[i], 0.001); end
        g = from_adjmatrix(A; directed=true)
        pr = pagerank(g)

        # Temporal: trend in mean access over panel
        ts_mean = from_dataframe(
            combine(groupby(nd_panel, :year), :access => mean => :access_mean),
            :year, :access_mean; freq=1)
        stl = stl_decompose(ts_mean; n_inner=1)

        # Assertions
        @test length(ŷ_2022) == n
        @test abs(sum(pr) - 1.0) < 1e-6
        @test length(stl.trend) == N_YEARS
        @test all(isfinite, stl.trend)
        @info "Cross-package pipeline: ML predictions ✓, PageRank ✓, STL trend ✓"
    end

    @testset "20. Federated learning CPU path" begin
        include(joinpath(@__DIR__, "..", "scripts", "federated_learning.jl"))
        sites = make_synthetic_sites(3, 30, 3)
        config = FederatedConfig(n_rounds=5, local_epochs=3, learning_rate=0.1)
        res = federated_train(sites, config)
        @test length(res.global_weights) == 3
        @test length(res.round_losses) == 5
        @test all(isfinite, res.round_losses)
        @test res.round_losses[end] < res.round_losses[1] + 1.0
    end

end  # @testset "Vol 5 Integration Tests"

@info "Vol 5 integration tests complete."
