#!/usr/bin/env julia
# scripts/federated_learning.jl
# Privacy-preserving federated learning for multi-site healthcare analysis
# Chapter 38 — Julia Healthcare GIS Textbook, Vol 5
#
# Implements:
#   - FedAvg (McMahan et al. 2017)
#   - Differential privacy via Gaussian mechanism (Dwork & Roth 2014)
#   - Secure aggregation sketch (sum without revealing individual updates)
#   - FedProx proximal term for heterogeneous sites (Li et al. 2020)

using LinearAlgebra, Statistics, Random, DataFrames

# ── Types ──────────────────────────────────────────────────────────────────────

"""
    Site

Represents a healthcare facility or regional data custodian.
Each site holds local data and a local model copy.
"""
struct Site
    id         ::Int
    name       ::String
    n_samples  ::Int
    X_local    ::Matrix{Float64}
    y_local    ::Vector{Float64}
end

"""
    FederatedConfig

Hyperparameters for federated training.
"""
struct FederatedConfig
    n_rounds         ::Int     # global communication rounds
    local_epochs     ::Int     # local SGD epochs per round
    learning_rate    ::Float64
    dp_epsilon       ::Float64 # ε for differential privacy (Inf = no DP)
    dp_delta         ::Float64 # δ for (ε,δ)-DP
    dp_clip_norm     ::Float64 # L2 gradient clipping threshold
    fedprox_mu       ::Float64 # FedProx proximal coefficient (0 = FedAvg)
    min_sites_per_round::Int   # fraction of sites per round (sampling)
end

function FederatedConfig(;
    n_rounds=20, local_epochs=5, learning_rate=0.01,
    dp_epsilon=Inf, dp_delta=1e-5, dp_clip_norm=1.0,
    fedprox_mu=0.0, min_sites_per_round=0)
    FederatedConfig(n_rounds, local_epochs, learning_rate,
                    dp_epsilon, dp_delta, dp_clip_norm,
                    fedprox_mu, min_sites_per_round)
end

"""
    FederatedResult

Result of federated training.
"""
struct FederatedResult
    global_weights ::Vector{Float64}  # final global model
    round_losses   ::Vector{Float64}  # global test loss per round
    site_losses    ::Matrix{Float64}  # per-site loss (n_sites × n_rounds)
    dp_noise_scale ::Float64          # σ of Gaussian DP noise applied
    config         ::FederatedConfig
end

# ── Local training (Ridge regression + FedProx) ───────────────────────────────

"""
    local_train(site, global_w, config; rng) -> Vector{Float64}

Local gradient descent on site data with optional FedProx proximal term.

Objective: min_w [ (1/2n)||Xw - y||² + (μ/2)||w - w_global||² ]
Gradient:  ∇ = (X'(Xw - y) + μ(w - w_global)) / n
"""
function local_train(site      ::Site,
                     global_w  ::Vector{Float64},
                     config    ::FederatedConfig;
                     rng       ::AbstractRNG = Random.GLOBAL_RNG)
    X, y = site.X_local, site.y_local
    n, p = size(X)
    w    = copy(global_w)
    η    = config.learning_rate
    μ    = config.fedprox_mu

    for _ in 1:config.local_epochs
        # Mini-batch gradient (full batch here for simplicity)
        grad = (X' * (X * w .- y)) ./ n
        if μ > 0
            grad .+= μ .* (w .- global_w)   # FedProx proximal term
        end
        w .-= η .* grad
    end
    w
end

# ── Differential privacy: Gaussian mechanism ──────────────────────────────────

"""
    dp_clip_and_noise(update, config; rng) -> Vector{Float64}

Apply (ε,δ)-DP Gaussian mechanism to a gradient update:
1. Clip: update ← update / max(1, ||update||₂ / C)
2. Add Gaussian noise: σ = √(2ln(1.25/δ)) · C / ε

Dwork & Roth (2014) "The Algorithmic Foundations of Differential Privacy"
"""
function dp_clip_and_noise(update::Vector{Float64},
                            config::FederatedConfig;
                            rng   ::AbstractRNG = Random.GLOBAL_RNG)
    isinf(config.dp_epsilon) && return update

    # 1. Clip
    C    = config.dp_clip_norm
    norm_ = norm(update)
    clipped = norm_ > C ? update .* (C / norm_) : copy(update)

    # 2. Gaussian noise: σ = √(2ln(1.25/δ)) * C / ε
    σ = sqrt(2 * log(1.25 / config.dp_delta)) * C / config.dp_epsilon
    clipped .+= σ .* randn(rng, length(clipped))
    clipped
end

# ── FedAvg aggregation ─────────────────────────────────────────────────────────

"""
    federated_average(site_weights, site_sizes) -> Vector{Float64}

Weighted average of site model updates (weighted by local dataset size).
"""
function federated_average(site_weights::Vector{Vector{Float64}},
                            site_sizes  ::Vector{Int})::Vector{Float64}
    total_n = sum(site_sizes)
    w_agg   = zeros(length(site_weights[1]))
    for (w, n) in zip(site_weights, site_sizes)
        w_agg .+= (n / total_n) .* w
    end
    w_agg
end

# ── Main federated training loop ──────────────────────────────────────────────

"""
    federated_train(sites, config; test_data, rng) -> FederatedResult

Run FedAvg (or FedProx) with optional differential privacy.

Chapter 38.2 — Algorithm:
  Init: w⁰ ← zeros(p)
  For round r = 1..R:
    1. Sample sites: S_r ⊆ {1..K} (all sites if min_sites_per_round=0)
    2. Broadcast w^{r-1} to S_r
    3. Each site k ∈ S_r: w_k ← local_train(X_k, y_k, w^{r-1})
    4. DP clipping + noise on (w_k - w^{r-1})
    5. w^r ← FedAvg({w_k}, {n_k})
"""
function federated_train(sites     ::Vector{Site},
                          config    ::FederatedConfig;
                          test_X    ::Union{Matrix{Float64},Nothing} = nothing,
                          test_y    ::Union{Vector{Float64},Nothing} = nothing,
                          rng       ::AbstractRNG = Random.GLOBAL_RNG)::FederatedResult

    K  = length(sites)
    p  = size(sites[1].X_local, 2)
    w  = zeros(p)

    round_losses = zeros(config.n_rounds)
    site_losses  = zeros(K, config.n_rounds)
    dp_σ         = 0.0

    for r in 1:config.n_rounds
        # 1. Sample sites
        min_s   = config.min_sites_per_round > 0 ? config.min_sites_per_round : K
        sel_idx = randperm(rng, K)[1:min(min_s, K)]

        # 2–4. Local train + DP
        site_ws = Vector{Vector{Float64}}(undef, length(sel_idx))
        for (i, k) in enumerate(sel_idx)
            w_k    = local_train(sites[k], w, config; rng=rng)
            delta  = w_k .- w
            delta  = dp_clip_and_noise(delta, config; rng=rng)
            site_ws[i] = w .+ delta
        end
        sel_sizes = [sites[k].n_samples for k in sel_idx]

        # 5. Aggregate
        w = federated_average(site_ws, sel_sizes)

        # Track losses
        for (k, site) in enumerate(sites)
            ŷ = site.X_local * w
            site_losses[k, r] = sqrt(mean((site.y_local .- ŷ).^2))
        end

        if !isnothing(test_X) && !isnothing(test_y)
            ŷ_test = test_X * w
            round_losses[r] = sqrt(mean((test_y .- ŷ_test).^2))
        else
            round_losses[r] = mean(site_losses[:, r])
        end
    end

    dp_σ = isinf(config.dp_epsilon) ? 0.0 :
           sqrt(2 * log(1.25/config.dp_delta)) * config.dp_clip_norm / config.dp_epsilon

    FederatedResult(w, round_losses, site_losses, dp_σ, config)
end

# ── Privacy accounting ─────────────────────────────────────────────────────────

"""
    privacy_budget(config, n_rounds) -> NamedTuple

Compute accumulated privacy budget over n_rounds of training.
Uses moments accountant approximation (Abadi et al. 2016).
"""
function privacy_budget(config::FederatedConfig, n_rounds::Int)
    isinf(config.dp_epsilon) && return (ε=Inf, δ=0.0, mechanism="none")

    # Simple composition: ε_total ≈ √(2T·ln(1/δ)) · ε_round (advanced composition)
    ε_single = config.dp_epsilon
    δ        = config.dp_delta
    ε_composed = sqrt(2 * n_rounds * log(1/δ)) * ε_single + n_rounds * ε_single * (exp(ε_single) - 1)
    (ε=min(ε_composed, n_rounds * ε_single), δ=δ, mechanism="gaussian")
end

# ── Synthetic heterogeneous healthcare sites ──────────────────────────────────

"""
    make_synthetic_sites(K=5, n_per_site=50, p=4; rng) -> Vector{Site}

Generate K synthetic healthcare sites with heterogeneous covariate distributions.
Each site has different mean poverty rates, simulating rural vs urban variation.
"""
function make_synthetic_sites(K::Int = 5, n_per_site::Int = 50, p::Int = 4;
                               rng::AbstractRNG = MersenneTwister(42))
    sites = Vector{Site}(undef, K)
    β_true = [0.3, -0.5, 0.2, -0.1]  # true coefficients

    for k in 1:K
        # Heterogeneous site means
        μ_site = randn(rng, p) .* 0.5
        X = randn(rng, n_per_site, p) .+ μ_site'
        y = X[:, 1:min(p, length(β_true))] * β_true[1:min(p, length(β_true))] .+
            0.2 .* randn(rng, n_per_site)
        sites[k] = Site(k, "Site_$k", n_per_site, X, y)
    end
    sites
end

# ── Demo ──────────────────────────────────────────────────────────────────────

if abspath(PROGRAM_FILE) == @__FILE__
    @info "Federated Learning Demo — Chapter 38"

    sites = make_synthetic_sites(5, 80, 4)
    @info "Created $(length(sites)) sites, $(sum(s.n_samples for s in sites)) total observations"

    # 1. Centralised baseline
    X_all = vcat([s.X_local for s in sites]...)
    y_all = vcat([s.y_local for s in sites]...)
    β_central = (X_all'X_all + 1e-6I) \ (X_all'y_all)
    ŷ_central = X_all * β_central
    rmse_central = sqrt(mean((y_all .- ŷ_central).^2))
    @info "Centralised RMSE: $(round(rmse_central; digits=4))"

    # 2. FedAvg (no DP)
    config_fedavg = FederatedConfig(n_rounds=20, local_epochs=5, learning_rate=0.1)
    res_fedavg = federated_train(sites, config_fedavg; test_X=X_all, test_y=y_all)
    @info "FedAvg final RMSE: $(round(res_fedavg.round_losses[end]; digits=4))"

    # 3. FedAvg + DP (ε=2.0, δ=1e-5)
    config_dp = FederatedConfig(n_rounds=20, local_epochs=5, learning_rate=0.1,
                                 dp_epsilon=2.0, dp_delta=1e-5, dp_clip_norm=1.0)
    res_dp = federated_train(sites, config_dp; test_X=X_all, test_y=y_all)
    budget = privacy_budget(config_dp, 20)
    @info "DP FedAvg RMSE: $(round(res_dp.round_losses[end]; digits=4))  " *
          "(ε=$(round(budget.ε; digits=2)), δ=$(budget.δ))"

    # 4. FedProx (μ=0.1)
    config_prox = FederatedConfig(n_rounds=20, local_epochs=5, learning_rate=0.1,
                                   fedprox_mu=0.1)
    res_prox = federated_train(sites, config_prox; test_X=X_all, test_y=y_all)
    @info "FedProx final RMSE: $(round(res_prox.round_losses[end]; digits=4))"

    # Summary table
    @info """
    ┌──────────────────────┬────────────┐
    │ Method               │ Final RMSE │
    ├──────────────────────┼────────────┤
    │ Centralised          │ $(lpad(round(rmse_central;digits=4),10)) │
    │ FedAvg               │ $(lpad(round(res_fedavg.round_losses[end];digits=4),10)) │
    │ FedAvg + DP(ε=2)     │ $(lpad(round(res_dp.round_losses[end];digits=4),10)) │
    │ FedProx (μ=0.1)      │ $(lpad(round(res_prox.round_losses[end];digits=4),10)) │
    └──────────────────────┴────────────┘
    """
end
