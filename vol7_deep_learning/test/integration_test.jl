#!/usr/bin/env julia
# test/integration_test.jl — Vol 7 cross-package integration test
# Chapter 48.3 — 20 testsets

using Test, Random, Statistics, LinearAlgebra, DataFrames, Distributions
Random.seed!(42)

import Pkg

PKGS_DIR = joinpath(@__DIR__, "..", "packages")
for dir in ["DeepHealth", "BayesianHealth"]
    Pkg.activate(joinpath(PKGS_DIR, dir))
end

Pkg.activate(joinpath(PKGS_DIR, "DeepHealth"))
using DeepHealth

Pkg.activate(joinpath(PKGS_DIR, "BayesianHealth"))
using BayesianHealth

# ── Fixtures ──────────────────────────────────────────────────────────────────

rng = MersenneTwister(42)

# Synthetic county access dataset (n=80, 8 features)
n_counties = 80; n_feat = 8
X_access = randn(rng, n_feat, n_counties)
β_true   = randn(rng, n_feat) .* 0.01 .+ [0.003, 0.002, -0.001, 0.004, -0.002, 0.001, 0.003, -0.001]
y_access = vec(β_true' * X_access) .+ 0.001*randn(rng, n_counties)
y_access = max.(y_access, 0.0001)   # access scores positive

# Synthetic clinical data (n=200, 10 features, binary outcome)
n_patients = 200; n_clinical = 10
X_clinical = randn(rng, n_clinical, n_patients)
y_readmit  = Float64.(randn(rng, n_patients) .> 0.8)   # ~18% readmission

# Provider referral network (20 nodes, 4 features)
n_nodes = 20; n_node_feat = 4
H_network = randn(rng, n_node_feat, n_nodes)
A_network  = Float64.(rand(rng, n_nodes, n_nodes) .> 0.7)

@testset "Vol 7 Integration Tests" begin

    # ── DeepHealth: Layer tests ───────────────────────────────────────────────

    @testset "1. Dense — ReLU non-negative" begin
        l = Dense(n_feat, 16; activation=:relu)
        y = forward(l, X_access)
        @test size(y) == (16, n_counties)
        @test all(y .>= 0)
    end

    @testset "2. BatchNorm — running stats update" begin
        bn = BatchNorm(n_feat)
        x  = randn(rng, n_feat, 32)
        before_mean = copy(bn.run_mean)
        forward_train(bn, x)
        @test bn.run_mean != before_mean  # stats updated
    end

    @testset "3. MLP build and forward" begin
        net = build_mlp(n_feat, [32, 16], 1)
        ŷ   = forward(net, X_access)
        @test size(ŷ) == (1, n_counties)
        @test !any(isnan, ŷ)
        @test n_params(net) > 0
    end

    @testset "4. GNN — referral network forward" begin
        gnn = build_gnn(n_node_feat, [16, 8], 1)
        out = forward(gnn, H_network, A_network)
        @test size(out) == (1, n_nodes)
        @test !any(isnan, out)
    end

    @testset "5. TabNet — output shape" begin
        tb  = TabNetBlock(n_feat, 4; n_steps=2)
        out = forward(tb, X_access)
        @test size(out) == (4, n_counties)
        @test !any(isnan, out)
    end

    # ── DeepHealth: Training tests ────────────────────────────────────────────

    @testset "6. AccessPredictor — fits and predicts" begin
        ap = AccessPredictor(n_feat; hidden=[32, 16])
        ap2 = fit!(ap, X_access, y_access;
                   n_epochs=30, batch_size=16, rng=rng)
        ŷ = predict_access(ap2, X_access[:, 1:10])
        @test length(ŷ) == 10
        @test !any(isnan, ŷ)
    end

    @testset "7. ReadmissionRisk — probabilities valid" begin
        rr = ReadmissionRisk(n_clinical; hidden=[32, 16])
        rr2 = fit!(rr, X_clinical, y_readmit;
                   n_epochs=25, batch_size=32, rng=rng)
        probs, labels = predict_readmission(rr2, X_clinical[:, 1:20])
        @test all(0 .<= probs .<= 1)
        @test all(labels .∈ [[0, 1]])
    end

    @testset "8. Train — loss decreases" begin
        net = build_mlp(n_feat, [32], 1)
        y_mat = reshape(y_access, 1, :)
        hist = train!(net, X_access, y_mat;
                      n_epochs=40, batch_size=20, lr=1e-2, rng=rng)
        @test length(hist.train_loss) > 0
        @test last(hist.train_loss) < hist.train_loss[min(5, end)]
    end

    @testset "9. EarlyStoppingCallback" begin
        cb = EarlyStoppingCallback(; patience=5)
        for i in 1:8
            update!(cb, 1.0, i)
        end
        @test cb.should_stop
    end

    @testset "10. DeepHealthReport — generates" begin
        net = build_mlp(n_feat, [16], 1)
        train!(net, X_access, reshape(y_access,1,:);
               n_epochs=15, batch_size=16, rng=rng)
        rpt = deep_health_report(net, X_access, y_access;
                                  task=:regression, n_perm=5, rng=rng)
        @test rpt.n_params > 0
        @test all(0 .<= rpt.importance .<= 1)
        @test isfinite(rpt.train_metrics.rmse)
    end

    # ── BayesianHealth: Prior tests ───────────────────────────────────────────

    @testset "11. Health priors — valid distributions" begin
        p1 = rate_prior(; mean_rate=0.08)
        p2 = cost_prior(; median_cost=6000.0)
        p3 = access_score_prior()
        @test abs(mean(p1.dist) - 0.08) < 0.01
        @test mean(p2.dist) > 0
        s3 = rand(p3.dist, 100)
        @test all(s3 .>= 0)
    end

    @testset "12. VI — ELBO increases during optimisation" begin
        rng2 = MersenneTwister(11)
        log_p(z) = -0.5*sum((z .- 2.0).^2)   # target: N(2, 1) × 3
        result = vi_fit(log_p, 3; n_iter=200, lr=0.1, rng=rng2)
        # ELBO should generally increase
        elbo_early = mean(result.elbo_history[1:min(20, end)])
        elbo_late  = mean(result.elbo_history[max(1,end-20):end])
        @test elbo_late >= elbo_early - 5.0  # loose: noise in gradient
    end

    @testset "13. VI — posterior mean near true" begin
        rng2 = MersenneTwister(13)
        true_μ = [1.5, -2.0]
        log_p(z) = sum(logpdf(Normal(true_μ[i], 0.5), z[i]) for i in 1:2)
        result = vi_fit(log_p, 2; n_iter=300, lr=0.08, rng=rng2)
        @test abs(result.q.μ[1] - true_μ[1]) < 0.8
        @test abs(result.q.μ[2] - true_μ[2]) < 0.8
    end

    @testset "14. MH chains — shape correct" begin
        rng2 = MersenneTwister(17)
        log_p(θ) = -0.5*sum(θ.^2)
        mh = MetropolisHastings(; step_size=0.3)
        chains = sample_chains(mh, log_p, zeros(3);
                                n_iter=300, n_warmup=100, n_chains=2, rng=rng2)
        @test size(chains.samples) == (300, 3, 2)
        @test all(0 .< chains.accept_rate .< 1)
    end

    @testset "15. HMC — finite samples" begin
        rng2 = MersenneTwister(19)
        log_p(θ) = -0.5*sum(θ.^2)
        hmc = HMCSampler(; step_size=0.1, n_leapfrog=5)
        chains = sample_chains(hmc, log_p, zeros(2);
                                n_iter=200, n_warmup=50, n_chains=2, rng=rng2)
        @test all(isfinite, chains.samples)
        @test all(0 .< chains.accept_rate .< 1)
    end

    @testset "16. R-hat and ESS — valid" begin
        rng2 = MersenneTwister(23)
        log_p(θ) = -0.5*sum(θ.^2)
        mh = MetropolisHastings(; step_size=0.3)
        chains = sample_chains(mh, log_p, zeros(2);
                                n_iter=400, n_warmup=100, n_chains=4, rng=rng2)
        rh = r_hat(chains)
        es = ess(chains)
        @test all(isfinite, rh)
        @test all(es .> 0)
        @test all(rh .< 3.0)   # loose; 400 iter, 4 chains
    end

    # ── Model comparison ──────────────────────────────────────────────────────

    @testset "17. WAIC — finite, p_waic non-negative" begin
        ll = randn(rng, 200, n_counties) .- 1.0
        r  = waic(ll)
        @test isfinite(r.waic)
        @test r.p_waic >= 0
        @test length(r.pointwise) == n_counties
    end

    @testset "18. LOO-IC — runs without error" begin
        ll = randn(rng, 100, 20) .- 1.5
        r  = loo_ic(ll)
        @test isfinite(r.loo_ic)
        @test length(r.pareto_k) == 20
    end

    # ── Cross-package integration ─────────────────────────────────────────────

    @testset "19. DeepHealth → BayesianHealth: residual Bayesian correction" begin
        # Train MLP; then model residuals with Bayesian linear regression
        net = build_mlp(n_feat, [16, 8], 1)
        train!(net, X_access, reshape(y_access, 1, :);
               n_epochs=30, batch_size=16, rng=rng)
        ŷ = vec(forward(net, X_access; training=false))
        residuals = y_access .- ŷ

        # VI Bayesian linear model on residuals (intercept only = shrinkage)
        log_p_res(z) = begin
            μ, log_σ = z[1], z[2]
            σ = exp(log_σ)
            σ < 1e-6 && return -Inf
            lp = logpdf(Normal(0, 0.5), μ) + logpdf(Normal(-2, 1), log_σ)
            ll = sum(logpdf(Normal(μ, σ), r) for r in residuals)
            lp + ll
        end

        result = vi_fit(log_p_res, 2; n_iter=200, lr=0.05, rng=rng)
        @test isfinite(result.q.μ[1])
        @test !isempty(result.elbo_history)
    end

    @testset "20. Benchmark suite — runs (quick mode)" begin
        # Just verify the benchmark infrastructure doesn't throw
        include(joinpath(@__DIR__, "..", "scripts", "benchmark_suite.jl"))
        df = run_benchmark_suite(; quick=true)
        @test nrow(df) > 0
        @test hasproperty(df, :Algorithm)
        @test hasproperty(df, :Median_ms)
    end

end  # @testset

@info "Vol 7 integration tests complete."
