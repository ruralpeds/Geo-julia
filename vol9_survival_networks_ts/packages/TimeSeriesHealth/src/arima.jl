# arima.jl — ARIMA(p,d,q) model: ACF/PACF, Yule-Walker, MLE, auto_arima

using Statistics, LinearAlgebra

# ── Differencing ──────────────────────────────────────────────────────────────

"""
    difference(y, d=1) -> Vector

Apply d-th order differencing to a time series.
"""
function difference(y::AbstractVector, d::Int=1)
    x = collect(Float64, y)
    for _ in 1:d
        x = diff(x)
    end
    x
end

"""
    undifference(dy, y_init, d) -> Vector

Reconstruct original series from differenced series.
`y_init` is the first d values of the original series.
"""
function undifference(dy::AbstractVector, y_init::AbstractVector, d::Int)
    if d == 0; return collect(Float64, dy); end
    x = vcat(y_init[1:d], collect(Float64, dy))
    for _ in 1:d
        x = cumsum(x)
        x = x[2:end]   # remove the init value that was already in y_init
    end
    x
end

# ── ACF / PACF ────────────────────────────────────────────────────────────────

"""
    acf(y, max_lag) -> Vector{Float64}

Sample autocorrelation function ρ(k) = Cov(y_t, y_{t-k}) / Var(y).
"""
function acf(y::AbstractVector, max_lag::Int)
    n  = length(y)
    μ  = mean(y)
    yc = y .- μ
    v  = sum(yc.^2) / n
    [sum(yc[1:n-k] .* yc[k+1:n]) / (n * max(v, 1e-12)) for k in 0:max_lag]
end

"""
    pacf(y, max_lag) -> Vector{Float64}

Sample partial autocorrelation via Yule-Walker (Durbin-Levinson recursion).
"""
function pacf(y::AbstractVector, max_lag::Int)
    ρ = acf(y, max_lag)
    n = max_lag
    φ = zeros(n, n)
    pa = zeros(n)
    φ[1, 1] = ρ[2]
    pa[1]   = ρ[2]
    for k in 2:n
        num = ρ[k+1] - sum(φ[k-1, j] * ρ[k-j+1] for j in 1:k-1; init=0.0)
        den = 1.0  - sum(φ[k-1, j] * ρ[j+1]     for j in 1:k-1; init=0.0)
        φ[k, k] = den != 0.0 ? num / den : 0.0
        for j in 1:k-1
            φ[k, j] = φ[k-1, j] - φ[k, k] * φ[k-1, k-j]
        end
        pa[k] = φ[k, k]
    end
    pa
end

# ── Yule-Walker AR(p) ─────────────────────────────────────────────────────────

"""
    yule_walker(y, p) -> (φ, σ²)

Yule-Walker estimates for AR(p) coefficients.
"""
function yule_walker(y::AbstractVector, p::Int)
    ρ = acf(y, p)
    R = [ρ[abs(i-j)+1] for i in 1:p, j in 1:p]
    r = ρ[2:p+1]
    φ = (R + 1e-8I) \ r
    σ² = var(y) * (1.0 - dot(φ, r))
    φ, max(σ², 1e-10)
end

# ── ARMA log-likelihood ───────────────────────────────────────────────────────

"""
    arma_loglik(y, φ, θ; σ²) -> Float64

Conditional log-likelihood for ARMA(p,q) via innovations algorithm.
"""
function arma_loglik(y::AbstractVector, φ::Vector{Float64}, θ::Vector{Float64};
                     σ²::Float64=1.0)
    n = length(y); p = length(φ); q = length(θ)
    ε = zeros(n)
    ll = 0.0
    for t in 1:n
        ar_part = sum(j <= t-1 ? φ[j] * y[t-j] : 0.0 for j in 1:p; init=0.0)
        ma_part = sum(j <= t-1 ? θ[j] * ε[t-j] : 0.0 for j in 1:q; init=0.0)
        ε[t] = y[t] - ar_part - ma_part
        ll  -= 0.5 * (log(2π * σ²) + ε[t]^2 / σ²)
    end
    ll
end

# ── ARMA model struct ─────────────────────────────────────────────────────────

"""
    ARIMAModel

Fitted ARIMA(p,d,q) model.
"""
mutable struct ARIMAModel
    p     ::Int
    d     ::Int
    q     ::Int
    φ     ::Vector{Float64}   # AR coefficients
    θ     ::Vector{Float64}   # MA coefficients
    μ     ::Float64           # intercept (of differenced series)
    σ²    ::Float64           # innovation variance
    aic   ::Float64
    bic   ::Float64
    log_lik::Float64
    residuals::Vector{Float64}
    fitted   ::Vector{Float64}
    y_orig   ::Vector{Float64}
end

"""
    arima_fit(y, p, d, q; max_iter, tol) -> ARIMAModel

Fit ARIMA(p,d,q) by:
1. Differencing d times
2. Yule-Walker initialisation for AR(p)
3. Gradient ascent on conditional log-likelihood for joint (φ,θ,σ²)
"""
function arima_fit(y::AbstractVector, p::Int=1, d::Int=0, q::Int=0;
                   max_iter::Int=100, tol::Float64=1e-6)
    y_orig = collect(Float64, y)
    # Difference
    y_diff = difference(y_orig, d)
    n      = length(y_diff)
    μ      = mean(y_diff)
    yd     = y_diff .- μ

    # Initialise AR by Yule-Walker
    φ0 = p > 0 ? yule_walker(yd, p)[1] : Float64[]
    θ0 = zeros(q)
    σ²0 = var(yd)

    # Joint optimisation via gradient ascent (finite differences)
    θ = vcat(φ0, θ0, log(σ²0))
    ll_fn = function(v)
        φv = v[1:p]
        θv = v[p+1:p+q]
        σ²v = exp(v[end])
        arma_loglik(yd, φv, θv; σ²=σ²v)
    end

    for iter in 1:max_iter
        g = _fd_gradient(ll_fn, θ; h=1e-5)
        α = 0.01
        for _ in 1:8
            if ll_fn(θ .+ α .* g) > ll_fn(θ) - 1e-10; break; end
            α *= 0.5
        end
        θ_new = θ .+ α .* g
        if maximum(abs.(θ_new .- θ)) < tol; θ = θ_new; break; end
        θ = θ_new
    end

    φ_fit = p > 0 ? θ[1:p] : Float64[]
    θ_fit = q > 0 ? θ[p+1:p+q] : Float64[]
    σ²_fit = exp(θ[end])
    ll_fin = arma_loglik(yd, φ_fit, θ_fit; σ²=σ²_fit)

    # Compute residuals
    n_p = p + q + 1 + (d > 0 ? 1 : 0)  # free parameters
    k   = n_p + 1  # +1 for μ
    aic = -2ll_fin + 2k
    bic = -2ll_fin + k * log(n)

    # In-sample fitted values
    ε_all  = _arma_residuals(yd, φ_fit, θ_fit)
    fitted_diff = yd .- ε_all .+ μ   # add back mean

    # Re-integrate if d > 0 (prepend original init values)
    fitted_orig = if d > 0
        init = y_orig[1:d]
        undifference(fitted_diff, init, d)
    else
        fitted_diff
    end

    ARIMAModel(p, d, q, φ_fit, θ_fit, μ, σ²_fit,
               aic, bic, ll_fin, ε_all, fitted_orig[1:length(y_orig)], y_orig)
end

function _arma_residuals(y, φ, θ)
    n = length(y); p = length(φ); q = length(θ)
    ε = zeros(n)
    for t in 1:n
        ar = sum(j <= t-1 ? φ[j] * y[t-j]  : 0.0 for j in 1:p; init=0.0)
        ma = sum(j <= t-1 ? θ[j] * ε[t-j] : 0.0 for j in 1:q; init=0.0)
        ε[t] = y[t] - ar - ma
    end
    ε
end

function _fd_gradient(f, x; h=1e-5)
    g = zeros(length(x))
    for i in eachindex(x)
        xp = copy(x); xp[i] += h
        xm = copy(x); xm[i] -= h
        g[i] = (f(xp) - f(xm)) / (2h)
    end
    g
end

# ── Auto-ARIMA ────────────────────────────────────────────────────────────────

"""
    auto_arima(y; max_p, max_q, d, ic) -> ARIMAModel

Grid search over ARIMA(p,d,q) models, selecting by AIC or BIC.
"""
function auto_arima(y::AbstractVector;
                    max_p::Int=3, max_q::Int=2, d::Int=1,
                    ic::Symbol=:aic, max_iter::Int=60)
    best_model = nothing
    best_ic    = Inf
    for p in 0:max_p, q in 0:max_q
        (p == 0 && q == 0) && continue
        try
            m   = arima_fit(y, p, d, q; max_iter=max_iter)
            val = ic == :aic ? m.aic : m.bic
            if val < best_ic
                best_ic = val; best_model = m
            end
        catch; end
    end
    isnothing(best_model) && (best_model = arima_fit(y, 1, d, 0))
    best_model
end
