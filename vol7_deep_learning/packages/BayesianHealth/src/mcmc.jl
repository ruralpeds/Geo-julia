# mcmc.jl — MCMC samplers for BayesianHealth (Turing.jl backend)
# Chapter 46 — Open-Source Healthcare GIS Textbook in Julia
#
# Wraps Turing.jl samplers (MH, HMC) behind the same public API:
#   MetropolisHastings, HMCSampler, Chains, sample_chains,
#   r_hat, ess, chain_summary

# ── Chains data structure ─────────────────────────────────────────────────────

"""
    Chains

Stores MCMC samples from one or more chains.
Shape: n_iter × n_params × n_chains

Internally uses `MCMCChains` and `MCMCDiagnosticTools` for convergence
diagnostics while preserving the original field-access pattern.
"""
struct Chains
    samples      :: Array{Float64, 3}   # iter × params × chains
    log_probs    :: Matrix{Float64}     # iter × chains
    n_warmup     :: Int
    param_names  :: Vector{String}
    accept_rate  :: Vector{Float64}     # per chain
end

function n_iter(c::Chains)    size(c.samples, 1) end
function n_params(c::Chains)  size(c.samples, 2) end
function n_chains(c::Chains)  size(c.samples, 3) end
function post_warmup(c::Chains)
    c.samples[c.n_warmup+1:end, :, :]
end

"""
    _to_mcmcchains(c::Chains) -> MCMCChains.Chains

Convert post-warmup samples to an MCMCChains.Chains object for diagnostics.
"""
function _to_mcmcchains(c::Chains)
    draws = post_warmup(c)
    MCMCChains.Chains(draws, Symbol.(c.param_names))
end

# ── R-hat convergence diagnostic ─────────────────────────────────────────────

"""
    r_hat(chains) -> Vector{Float64}

Gelman-Rubin R-hat per parameter.
Delegates to MCMCDiagnosticTools.rhat via MCMCChains.
"""
function r_hat(c::Chains)
    draws = post_warmup(c)
    _, p, m = size(draws)

    if m < 2
        return ones(p)
    end

    # Use MCMCDiagnosticTools.rhat on each parameter
    # rhat expects a matrix of shape (n_draws, n_chains)
    rhat_vals = Float64[]
    for j in 1:p
        param_draws = draws[:, j, :]  # n_draws × n_chains
        rh = MCMCDiagnosticTools.rhat(param_draws)
        push!(rhat_vals, rh)
    end
    rhat_vals
end

"""
    ess(chains) -> Vector{Float64}

Effective sample size per parameter.
Delegates to MCMCDiagnosticTools.ess.
"""
function ess(c::Chains)
    draws = post_warmup(c)
    _, p, m = size(draws)

    ess_vals = Float64[]
    for j in 1:p
        param_draws = draws[:, j, :]  # n_draws × n_chains
        # MCMCDiagnosticTools.ess returns a named tuple or vector
        e = MCMCDiagnosticTools.ess(param_draws)
        # Handle both scalar and vector returns
        push!(ess_vals, Float64(first(e)))
    end
    ess_vals
end

"""
    chain_summary(c::Chains) -> DataFrame

Summary statistics for each parameter: mean, std, quantiles, R-hat, ESS.
"""
function chain_summary(c::Chains)
    draws = post_warmup(c)
    n, p, m = size(draws)
    all_draws = reshape(draws, n*m, p)

    rh  = r_hat(c)
    es  = ess(c)

    DataFrame(
        parameter = c.param_names,
        mean      = vec(mean(all_draws; dims=1)),
        std       = vec(std(all_draws; dims=1)),
        q5        = [quantile(all_draws[:, j], 0.05) for j in 1:p],
        q50       = [quantile(all_draws[:, j], 0.50) for j in 1:p],
        q95       = [quantile(all_draws[:, j], 0.95) for j in 1:p],
        r_hat     = rh,
        ess       = es,
        converged = rh .< 1.1,
    )
end

# ── Sampler config structs (API-compatible) ──────────────────────────────────

"""
    MetropolisHastings

Random-walk Metropolis-Hastings sampler configuration.
Internally mapped to `Turing.MH()`.
"""
struct MetropolisHastings
    step_size    :: Float64
    adapt_steps  :: Int
    target_rate  :: Float64
end

MetropolisHastings(; step_size=0.1, adapt_steps=100, target_rate=0.234) =
    MetropolisHastings(step_size, adapt_steps, target_rate)

"""
    HMCSampler

Hamiltonian Monte Carlo sampler configuration.
Internally mapped to `Turing.HMC()`.
"""
struct HMCSampler
    step_size    :: Float64   # ε
    n_leapfrog   :: Int       # L
    adapt_steps  :: Int
    target_rate  :: Float64
end

HMCSampler(; step_size=0.05, n_leapfrog=10, adapt_steps=100, target_rate=0.65) =
    HMCSampler(step_size, n_leapfrog, adapt_steps, target_rate)

# ── Turing model wrapper for raw log-probability functions ───────────────────

"""
Wraps a raw `log_p(θ)::Function` into a Turing-compatible `@model` so that
we can leverage Turing's sampling infrastructure while preserving the user's
plain log-probability function interface.
"""
Turing.@model function _generic_logp_model(log_p, dim)
    θ ~ filldist(Flat(), dim)
    Turing.@addlogprob! log_p(θ)
end

# ── sample_chains: run multiple chains via Turing ────────────────────────────

"""
    sample_chains(sampler, log_p, θ0; n_iter, n_warmup, n_chains, rng) -> Chains

Run `n_chains` MCMC chains using Turing.jl as the backend.
Each chain is initialised by adding small noise to `θ0`.
Returns a `Chains` object with convergence diagnostics.
"""
function sample_chains(
    sampler  :: Union{MetropolisHastings, HMCSampler},
    log_p    :: Function,
    θ0       :: AbstractVector;
    n_iter   :: Int    = 1000,
    n_warmup :: Int    = 200,
    n_chains :: Int    = 4,
    param_names :: Vector{String} = String[],
    rng             = Random.GLOBAL_RNG,
)
    dim = length(θ0)
    if isempty(param_names)
        param_names = ["θ$(i)" for i in 1:dim]
    end

    # Map our sampler configs to Turing samplers
    turing_sampler = if sampler isa MetropolisHastings
        # Use default Turing.MH() — it sets up a symmetric random walk proposal
        Turing.MH()
    else
        Turing.HMC(sampler.step_size, sampler.n_leapfrog)
    end

    model = _generic_logp_model(log_p, dim)

    all_samples  = zeros(n_iter, dim, n_chains)
    all_lp       = zeros(n_iter, n_chains)
    accept_rates = zeros(n_chains)

    for c_idx in 1:n_chains
        # Perturbed initial point
        θ_init = θ0 .+ 0.1 .* randn(rng, dim)

        # Sample using Turing — request total n_iter samples, then
        # warmup is handled post-hoc (our Chains struct tracks n_warmup)
        local turing_chain
        try
            turing_chain = Turing.sample(
                rng, model, turing_sampler, n_iter;
                initial_params=θ_init, progress=false,
                discard_initial=0,
            )
        catch
            # Fallback without initial_params if not supported
            turing_chain = Turing.sample(
                rng, model, turing_sampler, n_iter;
                progress=false, discard_initial=0,
            )
        end

        # Extract samples from the Turing chain
        for i in 1:dim
            param_sym = Symbol("θ[$i]")
            col = Array(turing_chain[param_sym])
            n_available = min(length(col), n_iter)
            all_samples[1:n_available, i, c_idx] = col[1:n_available]
            if n_available < n_iter
                all_samples[n_available+1:end, i, c_idx] .= col[end]
            end
        end

        # Extract log probabilities
        lp_col = try
            vec(Array(turing_chain[:lp]))
        catch
            Float64[log_p(all_samples[t, :, c_idx]) for t in 1:n_iter]
        end
        n_lp = min(length(lp_col), n_iter)
        all_lp[1:n_lp, c_idx] = lp_col[1:n_lp]
        if n_lp < n_iter
            all_lp[n_lp+1:end, c_idx] .= lp_col[end]
        end

        # Acceptance rate
        accept_rates[c_idx] = try
            mean(turing_chain[:acceptance_rate])
        catch
            # Estimate from unique consecutive samples
            1.0 - mean(
                all(all_samples[t, :, c_idx] .== all_samples[t-1, :, c_idx])
                for t in 2:n_iter
            )
        end
    end

    Chains(all_samples, all_lp, n_warmup, param_names, accept_rates)
end
