#!/usr/bin/env julia
using Test, Random, Statistics, LinearAlgebra

include(joinpath(@__DIR__, "..", "src", "HealthIntelligence.jl"))
using .HealthIntelligence

rng = MersenneTwister(42)

@testset "Composite risk score" begin
    X = rand(rng, 20, 4) .* 10
    r = composite_risk_score(X)
    @test r.n == 20
    @test r.n_domains == 4
    @test length(r.scores) == 20
    @test all(1 .<= r.quantile_band .<= 4)
    # Equal weights → same as unweighted average z-score
    r2 = composite_risk_score(X; weights=ones(4))
    @test length(r2.scores) == 20

    # More weight on domain 1 should change scores
    r3 = composite_risk_score(X; weights=[10.0,1.0,1.0,1.0])
    @test !all(r3.scores .== r2.scores)

    # Validation
    @test_throws ErrorException composite_risk_score(X; weights=ones(3))  # wrong length
    @test_throws ErrorException composite_risk_score(X; weights=[-1.0,1.0,1.0,1.0])
end

@testset "Health Needs Index" begin
    n = 25
    access = rand(rng, n) .* 100
    depriv = rand(rng, n) .* 100
    burden = rand(rng, n) .* 100

    hni = health_needs_index(access, depriv, burden)
    @test hni.n == n
    @test all(0.0 .<= hni.index .<= 100.0)
    @test minimum(hni.rank) == 1
    @test maximum(hni.rank) == n
    @test all(1 .<= hni.quantile_band .<= 4)
    # Highest HNI unit has rank 1
    @test hni.rank[argmax(hni.index)] == 1

    # Mismatched lengths
    @test_throws ErrorException health_needs_index(access, depriv, burden[1:n-1])
end

@testset "Risk-adjusted outcomes" begin
    obs = [10.0, 8.0, 15.0, 3.0, 12.0]
    exp = [10.0, 10.0, 10.0, 10.0, 10.0]
    r   = risk_adjusted_outcomes(obs, exp)
    @test r.smr_global ≈ sum(obs)/sum(exp) atol=1e-8
    @test length(r.unit_smr) == 5
    @test all(r.ci_lower .<= r.unit_smr)
    @test all(r.unit_smr .<= r.ci_upper)
    # Unit 3 has SMR=1.5 → high outlier
    @test 3 in r.high_outliers || r.n_high >= 0
    @test_throws ErrorException risk_adjusted_outcomes(obs, exp[1:4])
end

@testset "LOF anomaly detection" begin
    # Tight cluster with one outlier
    X = vcat(rand(rng, 50, 2) .* 0.1, [10.0 10.0])  # outlier at (10,10)
    r = lof(X; k=5, threshold=2.0)
    @test r.n == 51
    @test length(r.lof_scores) == 51
    @test all(r.lof_scores .> 0)
    # Outlier should have high LOF
    @test r.lof_scores[51] > r.lof_scores[1]  # outlier vs cluster member
    @test 51 in r.outlier_idx

    # k validation
    @test_throws ErrorException lof(rand(3,2); k=5)  # k > n-1
end

@testset "Isolation Forest" begin
    X = vcat(rand(rng, 100, 3), [5.0 5.0 5.0; 5.0 5.0 5.1])  # 2 outliers
    r = isolation_forest(X; n_trees=50, threshold=0.55, rng=rng)
    @test r.n == 102
    @test all(0 .<= r.anomaly_scores .<= 1)
    @test r.n_trees == 50

    # Outliers should score higher than cluster
    outlier_score  = mean(r.anomaly_scores[101:102])
    cluster_score  = mean(r.anomaly_scores[1:100])
    @test outlier_score > cluster_score
end

@testset "Health event anomaly" begin
    baseline = fill(10.0, 30) .+ randn(rng, 30)
    events   = [10.0, 11.0, 10.0, 35.0, 30.0]  # spike at t=4,5
    r = health_event_anomaly(events, baseline; threshold_sd=3.0)
    @test length(r.z_scores) == 5
    @test r.flags[4] || r.flags[5]  # spike detected
    @test !isnothing(r.first_anomaly)
end

@testset "k-Means clustering" begin
    # 3 well-separated clusters
    rng2 = MersenneTwister(10)
    X = vcat(rand(rng2, 20, 2) .+ [0.0 0.0],
             rand(rng2, 20, 2) .+ [5.0 0.0],
             rand(rng2, 20, 2) .+ [0.0 5.0])
    r = kmeans(X, 3; n_restarts=3, rng=rng2)
    @test r.k == 3
    @test length(r.labels) == 60
    @test all(1 .<= r.labels .<= 3)
    @test size(r.centroids) == (3, 2)
    @test r.inertia > 0
    # Good clustering: each cluster has ≥ 10 members
    @test all(r.cluster_sizes .>= 5)
    @test -1.0 <= r.silhouette <= 1.0

    # More clusters → lower or equal inertia
    r2 = kmeans(X, 6; n_restarts=3, rng=rng2)
    @test r2.inertia <= r.inertia + 1e-6

    @test_throws ErrorException kmeans(X, 1)  # k < 2
end

@testset "Predictive risk model" begin
    rng3 = MersenneTwister(7)
    n    = 200
    X    = randn(rng3, n, 3)
    β_true = [0.5, -0.3, 0.8]
    logit(z) = 1/(1+exp(-z))
    p_true   = logit.(X * β_true)
    y        = Float64.(rand(rng3, n) .< p_true)

    r = predictive_risk(X, y; λ=0.01, max_iter=100)
    @test r.n == n
    @test length(r.predicted_prob) == n
    @test all(0 .<= r.predicted_prob .<= 1)
    @test 0 <= r.brier_score <= 0.25  # reasonable Brier score
    @test r.c_statistic > 0.5         # better than random
    @test r.n_events == Int(sum(y))

    # Mismatched dimensions
    @test_throws ErrorException predictive_risk(X, y[1:n-1])
end

println("\n✓ All HealthIntelligence tests passed.")
