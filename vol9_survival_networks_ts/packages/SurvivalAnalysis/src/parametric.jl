# parametric.jl — Parametric AFT survival models
# Weibull, Exponential, Log-logistic MLE

using Statistics, LinearAlgebra

# ── Model structs ─────────────────────────────────────────────────────────────

"""
    ParametricModel

Fitted parametric AFT survival model.

Fields: dist (:weibull/:exponential/:loglogistic), β (p+1 coefs including
intercept), log_scale (log of Weibull/LL shape), se, log_lik, aic, feature_names.
"""
struct ParametricModel
    dist         ::Symbol
    β            ::Vector{Float64}   # AFT coefs: log(T) = Xβ + σε
    log_scale    ::Float64           # log(σ); shape = 1/σ for Weibull
    se_β         ::Vector{Float64}
    se_log_scale ::Float64
    log_lik      ::Float64
    aic          ::Float64
    feature_names::Vector{String}
    converged    ::Bool
end

# ── Log-likelihoods ───────────────────────────────────────────────────────────

function _weibull_loglik(β, log_σ, times, status, X)
    σ   = exp(log_σ)
    μ   = X * β
    w   = (log.(times) .- μ) ./ σ   # standardised log-time
    ll  = 0.0
    for i in eachindex(times)
        if status[i] == 1
            # PDF of Weibull AFT: f(t) = (1/σt) φ(w) where φ is Gumbel
            ll += -log(σ) - log(times[i]) + w[i] - exp(w[i])
        else
            # Survival: S(t) = exp(-exp(w))
            ll += -exp(w[i])
        end
    end
    ll
end

function _loglogistic_loglik(β, log_σ, times, status, X)
    σ   = exp(log_σ)
    μ   = X * β
    w   = (log.(times) .- μ) ./ σ
    ll  = 0.0
    for i in eachindex(times)
        lS = -log1p(exp(w[i]))   # log S(t) = -log(1+exp(w))
        if status[i] == 1
            # log f(t) = log(1/σt) + w - 2log(1+exp(w))
            ll += -log(σ) - log(times[i]) + w[i] + 2*lS
        else
            ll += lS
        end
    end
    ll
end

function _exponential_loglik(β, times, status, X)
    # Exponential = Weibull with σ=1 (log_scale=0)
    _weibull_loglik(β, 0.0, times, status, X)
end

# ── Gradient via finite differences ──────────────────────────────────────────

function _aft_grad_hess(ll_fn, θ; h=1e-5)
    p    = length(θ)
    g    = zeros(p)
    H    = zeros(p, p)
    ll0  = ll_fn(θ)
    for i in 1:p
        θp = copy(θ); θp[i] += h
        θm = copy(θ); θm[i] -= h
        g[i] = (ll_fn(θp) - ll_fn(θm)) / (2h)
        H[i,i] = (ll_fn(θp) - 2ll0 + ll_fn(θm)) / h^2
        for j in i+1:p
            θpp = copy(θ); θpp[i] += h; θpp[j] += h
            θpm = copy(θ); θpm[i] += h; θpm[j] -= h
            θmp = copy(θ); θmp[i] -= h; θmp[j] += h
            θmm = copy(θ); θmm[i] -= h; θmm[j] -= h
            H[i,j] = H[j,i] = (ll_fn(θpp)-ll_fn(θpm)-ll_fn(θmp)+ll_fn(θmm))/(4h^2)
        end
    end
    g, H, ll0
end

# ── Fitter ────────────────────────────────────────────────────────────────────

"""
    parametric_fit(times, status, X; dist, feature_names, max_iter, tol) -> ParametricModel

Fit a parametric AFT model by maximising the log-likelihood.

`dist ∈ {:weibull, :exponential, :loglogistic}`
"""
function parametric_fit(times::AbstractVector, status::AbstractVector{<:Integer},
                         X::AbstractMatrix;
                         dist::Symbol=:weibull,
                         feature_names::Vector{String}=["x$i" for i in 1:size(X,2)],
                         max_iter::Int=200,
                         tol::Float64=1e-6)
    n, p = size(X)
    X_aug = hcat(ones(n), X)
    p_aug = p + 1
    fnames = vcat(["intercept"], feature_names)

    # Initial params: OLS on log(times) for β, log_scale=0
    log_t = log.(max.(times, 1e-10))
    β0    = (X_aug'X_aug + 1e-8I) \ X_aug'log_t
    ls0   = 0.0

    # Build LL closure based on dist
    if dist == :weibull
        ll_fn = θ -> _weibull_loglik(θ[1:p_aug], θ[end], times, status, X_aug)
    elseif dist == :exponential
        # Fix log_scale = 0
        ll_fn = θ -> _exponential_loglik(θ[1:p_aug], times, status, X_aug)
    elseif dist == :loglogistic
        ll_fn = θ -> _loglogistic_loglik(θ[1:p_aug], θ[end], times, status, X_aug)
    else
        error("Unknown distribution: $dist. Choose :weibull, :exponential, or :loglogistic")
    end

    if dist == :exponential
        θ = copy(β0)
        converged = false
        for iter in 1:max_iter
            g, H, ll = _aft_grad_hess(ll_fn, θ)
            H_reg = H - 1e-8I
            δθ = -(H_reg \ g)
            α  = 1.0
            for _ in 1:8
                if ll_fn(θ .+ α.*δθ) > ll - 1e-10; break; end
                α *= 0.5
            end
            θ_new = θ .+ α .* δθ
            if maximum(abs.(θ_new .- θ)) < tol; converged=true; end
            θ = θ_new
            converged && break
        end
        g, H, ll0 = _aft_grad_hess(ll_fn, θ)
        info = -H + 1e-10I
        se   = sqrt.(max.(diag(inv(info)), 1e-20))
        return ParametricModel(dist, θ, 0.0, se, 0.0, ll0,
                               -2ll0 + 2*(p_aug), fnames, converged)
    end

    θ = vcat(β0, ls0)
    converged = false
    for iter in 1:max_iter
        g, H, ll = _aft_grad_hess(ll_fn, θ)
        H_reg = H - 1e-8I
        δθ = -(H_reg \ g)
        α = 1.0
        for _ in 1:8
            if ll_fn(θ .+ α.*δθ) > ll - 1e-10; break; end
            α *= 0.5
        end
        θ_new = θ .+ α .* δθ
        if maximum(abs.(θ_new .- θ)) < tol; converged=true; end
        θ = θ_new
        converged && break
    end

    g, H, ll_fin = _aft_grad_hess(ll_fn, θ)
    info = -H + 1e-10I
    se   = sqrt.(max.(diag(inv(info)), 1e-20))
    β_fit  = θ[1:p_aug]
    ls_fit = θ[end]

    ParametricModel(dist, β_fit, ls_fit, se[1:p_aug], se[end], ll_fin,
                    -2ll_fin + 2*(p_aug+1), fnames, converged)
end

"""
    parametric_predict(model, X_new; percentiles) -> NamedTuple

Return predicted median (and other percentile) survival times for new observations.
"""
function parametric_predict(model::ParametricModel, X_new::AbstractMatrix;
                             percentiles::Vector{Float64}=[0.1, 0.25, 0.5, 0.75, 0.9])
    n  = size(X_new, 1)
    Xn = hcat(ones(n), X_new)
    μ  = Xn * model.β
    σ  = exp(model.log_scale)
    σ  = max(σ, 1e-8)

    out = Dict{Symbol, Vector{Float64}}()
    for pct in percentiles
        q = if model.dist == :weibull
            exp.(μ .+ σ .* log.(-log.(1 .- pct)))
        elseif model.dist == :loglogistic
            exp.(μ .+ σ .* log.(pct ./ (1 .- pct)))
        else  # exponential
            -exp.(μ) .* log.(1 .- pct)
        end
        out[Symbol("q$(round(Int, 100*pct))")] = q
    end
    out
end

"""
    parametric_survival(model, X_new, t) -> Vector{Float64}

Predicted survival probability S(t|X_new) for a scalar time `t`.
"""
function parametric_survival(model::ParametricModel, X_new::AbstractMatrix, t::Real)
    n  = size(X_new, 1)
    Xn = hcat(ones(n), X_new)
    μ  = Xn * model.β
    σ  = max(exp(model.log_scale), 1e-8)
    w  = (log(t) .- μ) ./ σ

    if model.dist == :weibull || model.dist == :exponential
        exp.(-exp.(w))
    elseif model.dist == :loglogistic
        1.0 ./ (1.0 .+ exp.(w))
    end
end
