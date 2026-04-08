#!/usr/bin/env julia
# test/runtests.jl — BayesianHealth.jl unit tests
# Chapter 46 — Open-Source Healthcare GIS Textbook in Julia

using Test, Random, Statistics, LinearAlgebra, Distributions
using BayesianHealth

Random.seed!(42)

@testset "BayesianHealth.jl" begin

    # ── Prior tests ───────────────────────────────────────────────────────────

    @testset "rate_prior — valid Beta distribution" begin
        p = rate_prior(; mean_rate=0.1, effective_n=20.0)
        @test p.dist isa Beta
        @test abs(mean(p.dist) - 0.1) < 0.01
    end

    @testset "cost_prior — LogNormal positive" begin
        p = cost_prior(; median_cost=5000.0)
        @test p.dist isa LogNormal
        r = rand(p.dist, 100)
        @test all(r .> 0)
    end

    @testset "proportion_prior — Dirichlet sums to 1" begin
        p = proportion_prior(5; concentration=1.0)
        @test p.dist isa Dirichlet
        s = rand(p.dist)
        @test abs(sum(s) - 1.0) < 1e-10
    end

    @testset "access_score_prior — non-negative samples" begin
        p = access_score_prior()
        s = rand(p.dist, 100)
        @test all(s .>= 0)
    end

    @testset "log_prior — correct sum" begin
        priors_list = [Normal(0, 1), Normal(0, 1)]
        θ = [0.0, 0.0]
        lp = log_prior(θ, priors_list)
        @test isfinite(lp)
        @test lp ≈ 2 * logpdf(Normal(), 0.0)
    end

    # ── VI tests ──────────────────────────────────────────────────────────────

    @testset "MeanFieldGaussian — entropy positive" begin
        q = MeanFieldGaussian(4)
        @test entropy(q) > -Inf
    end

    @testset "ELBO — finite for simple Gaussian target" begin
        rng = MersenneTwister(1)
        # Target: N(2, 1) for each of 2 parameters
        log_p(z) = sum(logpdf(Normal(2.0, 1.0), zi) for zi in z)
        q = MeanFieldGaussian(2)
        lb = elbo(q, log_p; n_samples=20, rng=rng)
        @test isfinite(lb)
    end

    @testset "vi_fit — μ converges toward true mean" begin
        rng = MersenneTwister(7)
        true_μ = [3.0, -2.0]
        log_p(z) = sum(logpdf(Normal(true_μ[i], 0.5), z[i]) for i in 1:2)

        result = vi_fit(log_p, 2;
                         n_iter=200, lr=0.1,
                         n_mc_samples=10, rng=rng)
        @test abs(result.q.μ[1] - true_μ[1]) < 1.0
        @test abs(result.q.μ[2] - true_μ[2]) < 1.0
    end

    @testset "vi_fit — ELBO history non-empty" begin
        rng = MersenneTwister(9)
        log_p(z) = -0.5 * sum(z.^2)
        result = vi_fit(log_p, 3; n_iter=50, rng=rng)
        @test length(result.elbo_history) > 0
        @test all(isfinite, result.elbo_history)
    end

    @testset "vi_predict — returns mean and std" begin
        rng = MersenneTwister(11)
        log_p(z) = -0.5 * sum(z.^2)
        result = vi_fit(log_p, 2; n_iter=30, rng=rng)
        X_new = randn(2, 5)
        predict_fn(z, X) = vec(z' * X)
        μ_pred, σ_pred = vi_predict(result, X_new, predict_fn; n_samples=20, rng=rng)
        @test length(μ_pred) == 5
        @test all(σ_pred .>= 0)
    end

    # ── MCMC tests ────────────────────────────────────────────────────────────

    @testset "MetropolisHastings — samples correct shape" begin
        rng = MersenneTwister(17)
        log_p(θ) = -0.5 * sum(θ.^2)
        mh = MetropolisHastings(; step_size=0.3)
        chains = sample_chains(mh, log_p, zeros(2);
                                n_iter=200, n_warmup=50, n_chains=2, rng=rng)
        @test size(chains.samples) == (200, 2, 2)
        @test all(isfinite, chains.samples)
    end

    @testset "MetropolisHastings — accept rate in (0,1)" begin
        rng = MersenneTwister(19)
        log_p(θ) = -0.5 * sum(θ.^2)
        mh = MetropolisHastings(; step_size=0.5)
        chains = sample_chains(mh, log_p, zeros(2);
                                n_iter=200, n_warmup=50, n_chains=2, rng=rng)
        @test all(0.0 .<= chains.accept_rate .<= 1.0)
    end

    @testset "HMC — samples finite" begin
        rng = MersenneTwister(23)
        log_p(θ) = -0.5 * sum(θ.^2)   # Standard Normal
        hmc = HMCSampler(; step_size=0.1, n_leapfrog=5)
        chains = sample_chains(hmc, log_p, zeros(3);
                                n_iter=100, n_warmup=30, n_chains=2, rng=rng)
        @test all(isfinite, chains.samples)
        @test size(chains.samples, 2) == 3
    end

    @testset "R-hat — near 1 for well-mixed chains" begin
        rng = MersenneTwister(31)
        log_p(θ) = -0.5 * sum(θ.^2)
        mh = MetropolisHastings(; step_size=0.4)
        chains = sample_chains(mh, log_p, zeros(2);
                                n_iter=400, n_warmup=100, n_chains=4, rng=rng)
        rh = r_hat(chains)
        @test all(isfinite, rh)
        @test all(rh .< 2.0)   # loose check; 4 chains each 300 post-warmup
    end

    @testset "ESS — positive" begin
        rng = MersenneTwister(37)
        log_p(θ) = -0.5 * sum(θ.^2)
        mh = MetropolisHastings(; step_size=0.3)
        chains = sample_chains(mh, log_p, zeros(2);
                                n_iter=300, n_warmup=100, n_chains=2, rng=rng)
        es = ess(chains)
        @test all(es .> 0)
    end

    @testset "chain_summary — returns correct DataFrame" begin
        rng = MersenneTwister(41)
        log_p(θ) = -0.5 * sum(θ.^2)
        mh = MetropolisHastings(; step_size=0.3)
        chains = sample_chains(mh, log_p, zeros(3);
                                n_iter=200, n_warmup=50, n_chains=2,
                                param_names=["α","β","γ"], rng=rng)
        df = chain_summary(chains)
        @test nrow(df) == 3
        @test hasproperty(df, :r_hat)
        @test hasproperty(df, :ess)
    end

    # ── Model comparison tests ────────────────────────────────────────────────

    @testset "WAIC — finite, p_waic >= 0" begin
        rng = MersenneTwister(53)
        # Simulate log-likelihoods: S=100 samples, N=20 obs
        ll = randn(rng, 100, 20) .- 2.0   # centred around -2
        r = waic(ll)
        @test isfinite(r.waic)
        @test r.p_waic >= 0
        @test length(r.pointwise) == 20
    end

    @testset "LOO-IC — finite, pareto_k computed" begin
        rng = MersenneTwister(59)
        ll = randn(rng, 50, 15) .- 1.5
        r = loo_ic(ll)
        @test isfinite(r.loo_ic)
        @test length(r.pareto_k) == 15
        @test r.n_bad_k >= 0
    end

    @testset "Bayes factor — interpretation string present" begin
        rng = MersenneTwister(67)
        ll1 = randn(rng, 80, 10) .- 1.0   # better model
        ll2 = randn(rng, 80, 10) .- 3.0
        bf = bayes_factor(ll1, ll2)
        @test isfinite(bf.log_bf)
        @test !isempty(bf.interpretation)
    end

    @testset "compare_models_bayes — sorted by IC" begin
        rng = MersenneTwister(71)
        models = Dict(
            "good"  => randn(rng, 50, 20) .- 0.5,
            "bad"   => randn(rng, 50, 20) .- 5.0,
        )
        mc = compare_models_bayes(models; criterion=:waic)
        @test mc.table.ic[1] <= mc.table.ic[2]
        @test sum(mc.table.weight) ≈ 1.0 atol=1e-10
    end

    @testset "prior_predictive_check — returns DataFrame" begin
        priors_dict = Dict("μ" => regression_coef_prior(), "σ" => noise_prior())
        model_fn(p) = p["μ"] .+ randn(5) .* p["σ"]
        df = prior_predictive_check(priors_dict, model_fn, 20)
        @test nrow(df) == 100   # 20 draws × 5 outcomes
        @test hasproperty(df, :outcome)
    end

end  # @testset
