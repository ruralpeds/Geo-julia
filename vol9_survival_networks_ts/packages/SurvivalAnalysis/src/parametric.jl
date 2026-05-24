# parametric.jl — Parametric AFT survival models
# Weibull, Exponential, Log-logistic MLE using Distributions.jl + Optim.jl

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

# ── Log-likelihoods using Distributions.jl ───────────────────────────────────

function _weibull_loglik(β, log_σ, times, status, X)
    σ   = exp(log_σ)
    μ   = X * β
    w   = (log.(times) .- μ) ./ σ   # standardised log-time
    # Gumbel (minimum) distribution for AFT error
    gumbel = Distributions.Gumbel(0.0, 1.0)
    ll  = 0.0
    for i in eachindex(times)
        if status[i] == 1
            # log f(t) = -log(σ) - log(t) + logpdf(Gumbel, w)
            ll += -log(σ) - log(times[i]) + Distributions.logpdf(gumbel, w[i])
        else
            # log S(t) = logccdf(Gumbel, w) = -exp(w)
            ll += Distributions.logccdf(gumbel, w[i])
        end
    end
    ll
end

function _loglogistic_loglik(β, log_σ, times, status, X)
    σ   = exp(log_σ)
    μ   = X * β
    w   = (log.(times) .- μ) ./ σ
    # Logistic distribution for AFT error in log-logistic model
    logistic_d = Distributions.Logistic(0.0, 1.0)
    ll  = 0.0
    for i in eachindex(times)
        if status[i] == 1
            # log f(t) = -log(σ) - log(t) + logpdf(Logistic, w)
            ll += -log(σ) - log(times[i]) + Distributions.logpdf(logistic_d, w[i])
        else
            # log S(t) = logccdf(Logistic, w)
            ll += Distributions.logccdf(logistic_d, w[i])
        end
    end
    ll
end

function _exponential_loglik(β, times, status, X)
    # Exponential = Weibull with σ=1 (log_scale=0)
    _weibull_loglik(β, 0.0, times, status, X)
end

# ── Fitter ────────────────────────────────────────────────────────────────────

"""
    parametric_fit(times, status, X; dist, feature_names, max_iter, tol) -> ParametricModel

Fit a parametric AFT model by maximising the log-likelihood using Optim.jl.

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

    if dist == :exponential
        # Fix log_scale = 0; optimise only β
        neg_ll = θ -> -_exponential_loglik(θ, times, status, X_aug)

        result = Optim.optimize(
            neg_ll, copy(β0),
            Optim.LBFGS(),
            Optim.Options(iterations=max_iter, g_tol=tol, show_trace=false);
            autodiff=:forward
        )

        θ = Optim.minimizer(result)
        converged = Optim.converged(result)
        ll0 = -Optim.minimum(result)

        # Compute SEs via numerical Hessian at optimum
        se = _compute_se_numerical(neg_ll, θ)

        return ParametricModel(dist, θ, 0.0, se, 0.0, ll0,
                               -2ll0 + 2*(p_aug), fnames, converged)
    end

    # Weibull or Log-logistic: optimise β and log_scale jointly
    if dist == :weibull
        neg_ll = θ -> -_weibull_loglik(θ[1:p_aug], θ[end], times, status, X_aug)
    elseif dist == :loglogistic
        neg_ll = θ -> -_loglogistic_loglik(θ[1:p_aug], θ[end], times, status, X_aug)
    else
        error("Unknown distribution: $dist. Choose :weibull, :exponential, or :loglogistic")
    end

    θ0 = vcat(β0, ls0)

    result = Optim.optimize(
        neg_ll, θ0,
        Optim.LBFGS(),
        Optim.Options(iterations=max_iter, g_tol=tol, show_trace=false);
        autodiff=:forward
    )

    θ = Optim.minimizer(result)
    converged = Optim.converged(result)
    ll_fin = -Optim.minimum(result)

    # Compute SEs via numerical Hessian
    se = _compute_se_numerical(neg_ll, θ)

    β_fit  = θ[1:p_aug]
    ls_fit = θ[end]

    ParametricModel(dist, β_fit, ls_fit, se[1:p_aug], se[end], ll_fin,
                    -2ll_fin + 2*(p_aug+1), fnames, converged)
end

"""
    _compute_se_numerical(neg_ll, θ; h=1e-5) -> Vector{Float64}

Compute standard errors from numerically estimated Hessian of the
negative log-likelihood at the optimum.
"""
function _compute_se_numerical(neg_ll, θ; h=1e-5)
    p = length(θ)
    H = zeros(p, p)
    f0 = neg_ll(θ)
    for i in 1:p
        θp = copy(θ); θp[i] += h
        θm = copy(θ); θm[i] -= h
        H[i,i] = (neg_ll(θp) - 2f0 + neg_ll(θm)) / h^2
        for j in i+1:p
            θpp = copy(θ); θpp[i] += h; θpp[j] += h
            θpm = copy(θ); θpm[i] += h; θpm[j] -= h
            θmp = copy(θ); θmp[i] -= h; θmp[j] += h
            θmm = copy(θ); θmm[i] -= h; θmm[j] -= h
            H[i,j] = H[j,i] = (neg_ll(θpp) - neg_ll(θpm) - neg_ll(θmp) + neg_ll(θmm)) / (4h^2)
        end
    end
    # H is the Hessian of neg_ll = observed information
    info = H + 1e-10I
    sqrt.(max.(diag(inv(info)), 1e-20))
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
