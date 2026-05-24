# cox.jl — Cox proportional hazards model
# Partial likelihood maximisation via Newton-Raphson with Optim.jl fallback

using Statistics, LinearAlgebra

"""
    CoxModel

Fitted Cox PH model.

- `β`          : coefficient vector (p)
- `se`         : standard errors from inverse observed information
- `z_stats`    : z = β/se
- `p_values`   : two-sided Wald p-values
- `log_lik`    : partial log-likelihood at convergence
- `concordance`: Harrell's C-statistic
- `feature_names`
- `baseline_hazard`: Breslow baseline hazard at event times
- `converged`
"""
struct CoxModel
    β              ::Vector{Float64}
    se             ::Vector{Float64}
    z_stats        ::Vector{Float64}
    p_values       ::Vector{Float64}
    log_lik        ::Float64
    concordance    ::Float64
    feature_names  ::Vector{String}
    event_times    ::Vector{Float64}
    baseline_hazard::Vector{Float64}
    converged      ::Bool
end

"""
    cox_fit(times, status, X; feature_names, max_iter, tol, step_size) -> CoxModel

Fit a Cox proportional hazards model using Newton-Raphson on the
Breslow partial likelihood, with Optim.jl for robust optimisation.

  log L(β) = Σ_{i:δᵢ=1} [ xᵢ'β - log Σ_{j∈R(tᵢ)} exp(xⱼ'β) ]
"""
function cox_fit(times::AbstractVector, status::AbstractVector{<:Integer},
                 X::AbstractMatrix;
                 feature_names::Vector{String}=["x$i" for i in 1:size(X,2)],
                 max_iter::Int=100,
                 tol::Float64=1e-7,
                 step_size::Float64=1.0)
    n, p = size(X)
    @assert length(times) == n && length(status) == n

    # Sort by time (ascending)
    ord   = sortperm(times)
    t_s   = times[ord]
    d_s   = status[ord]
    X_s   = X[ord, :]

    # Use Optim.jl with Newton's method for robust optimisation
    # Negative log-likelihood (Optim minimises)
    function neg_ll(β_vec)
        _, _, ll = _cox_grad_hess(β_vec, t_s, d_s, X_s)
        return -ll
    end

    function neg_ll_grad!(g, β_vec)
        grad, _, _ = _cox_grad_hess(β_vec, t_s, d_s, X_s)
        g .= -grad
    end

    function neg_ll_hess!(H, β_vec)
        _, hess, _ = _cox_grad_hess(β_vec, t_s, d_s, X_s)
        H .= -hess
    end

    β0 = zeros(p)

    result = Optim.optimize(
        neg_ll, neg_ll_grad!, neg_ll_hess!, β0,
        Optim.Newton(),
        Optim.Options(iterations=max_iter, g_tol=tol, show_trace=false)
    )

    β = Optim.minimizer(result)
    converged = Optim.converged(result)

    grad, hess, log_lik = _cox_grad_hess(β, t_s, d_s, X_s)
    # SE from inverse observed information = -hess
    info = -hess
    se   = sqrt.(max.(diag(inv(info .+ 1e-10I)), 1e-20))
    z    = β ./ se
    pv   = 2.0 .* (1.0 .- _norm_cdf.(abs.(z)))

    # Breslow baseline hazard
    ev_times, bh = _breslow_baseline(β, t_s, d_s, X_s)

    # Concordance (Harrell's C)
    η   = X * β
    con = _concordance(times, status, η)

    CoxModel(β, se, z, pv, log_lik, con, feature_names,
             ev_times, bh, converged)
end

function _cox_grad_hess(β, times, status, X)
    n, p = size(X)
    η    = X * β           # linear predictor
    expη = exp.(η)

    ll   = 0.0
    grad = zeros(p)
    hess = zeros(p, p)

    event_times = unique(times[status .== 1])

    for t in sort(event_times)
        risk_mask  = times .>= t
        event_mask = (times .== t) .& (status .== 1)

        X_risk   = X[risk_mask, :]
        expη_risk = expη[risk_mask]
        S0 = sum(expη_risk)
        S0 == 0.0 && continue

        S1 = vec(sum(X_risk .* expη_risk, dims=1))   # p-vector
        S2 = X_risk' * (X_risk .* expη_risk)          # p×p matrix

        d = sum(event_mask)  # number of events at t (ties handled via Breslow)
        X_ev = X[event_mask, :]
        for i in 1:sum(event_mask)
            ll   += X_ev[i,:]' * β - log(S0)
        end
        grad .+= d .* (vec(mean(X_ev, dims=1)) .- S1 ./ S0)
        hess .+= -d .* (S2 ./ S0 .- (S1 * S1') ./ S0^2)
    end
    return grad, hess, ll
end

function _breslow_baseline(β, times, status, X)
    η = X * β
    expη = exp.(η)
    event_times = sort(unique(times[status .== 1]))
    h0 = Float64[]
    for t in event_times
        d  = sum((times .== t) .& (status .== 1))
        r  = sum(expη[times .>= t])
        push!(h0, r > 0 ? d / r : 0.0)
    end
    event_times, h0
end

"""
    cox_predict(model, X_new; times) -> (hazard_ratio, survival_at_times)

Predict hazard ratios and survival probabilities for new observations.
`times` is a vector of time points; if empty, use model's event times.
"""
function cox_predict(model::CoxModel, X_new::AbstractMatrix;
                     times::Vector{Float64}=model.event_times)
    n    = size(X_new, 1)
    η    = X_new * model.β
    hr   = exp.(η)   # hazard ratio relative to baseline

    # Cumulative baseline hazard via Breslow
    H0 = cumsum(model.baseline_hazard)

    surv = zeros(n, length(times))
    for (j, t) in enumerate(times)
        idx = findlast(model.event_times .<= t)
        H0_t = isnothing(idx) ? 0.0 : H0[idx]
        for i in 1:n
            surv[i, j] = exp(-H0_t * hr[i])
        end
    end
    (hazard_ratio=hr, survival=surv)
end

"""
    cox_summary(model) -> DataFrame
"""
function cox_summary(model::CoxModel)
    _make_dataframe(
        feature  = model.feature_names,
        coef     = round.(model.β, digits=4),
        exp_coef = round.(exp.(model.β), digits=4),
        se       = round.(model.se, digits=4),
        z        = round.(model.z_stats, digits=3),
        p_value  = round.(model.p_values, digits=4)
    )
end

# ── Utilities ────────────────────────────────────────────────────────────────

function _concordance(times, status, η)
    n = length(times)
    concordant = 0.0; total = 0.0
    for i in 1:n
        status[i] == 0 && continue
        for j in 1:n
            times[j] <= times[i] && j != i && continue
            times[j] > times[i] || continue
            total += 1.0
            if η[i] > η[j]; concordant += 1.0
            elseif η[i] == η[j]; concordant += 0.5
            end
        end
    end
    total == 0.0 ? 0.5 : concordant / total
end

function _norm_cdf(z)
    # Use Distributions.jl Normal CDF
    Distributions.cdf(Distributions.Normal(), z)
end

function _make_dataframe(; kwargs...)
    # Lightweight DataFrame substitute
    keys_   = collect(keys(kwargs))
    vals_   = [collect(v) for v in values(kwargs)]
    # Return as NamedTuple of vectors (avoids DataFrames dep)
    NamedTuple{Tuple(keys_)}(Tuple(vals_))
end
