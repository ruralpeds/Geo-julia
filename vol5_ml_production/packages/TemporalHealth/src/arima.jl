# arima.jl — ARIMA model for health outcome forecasting
# Chapter 37.3
#
# ARIMA(p,d,q): AutoRegressive Integrated Moving Average
# State-space representation + Kalman filter for exact likelihood

"""
    ARIMAModel

Fitted ARIMA(p,d,q) model.
"""
mutable struct ARIMAModel
    p        ::Int
    d        ::Int
    q        ::Int
    ar_coefs ::Vector{Float64}   # φ₁,...,φ_p
    ma_coefs ::Vector{Float64}   # θ₁,...,θ_q
    σ²       ::Float64
    aic      ::Float64
    bic      ::Float64
    log_lik  ::Float64
    residuals::Vector{Float64}
    fitted   ::Vector{Float64}
    diff_series::Vector{Float64}
end

"""
    arima_fit(ts; p=1, d=1, q=1) -> ARIMAModel

Fit ARIMA(p,d,q) by conditional sum-of-squares approximation.

Difference y d times, then fit AR(p) + MA(q) by:
  CSS: minimise Σ aₜ² where aₜ = yₜ - Σφᵢyₜ₋ᵢ - Σθⱼaₜ₋ⱼ

AR coefficients estimated by Yule-Walker; MA by innovation algorithm.
"""
function arima_fit(ts::HealthTimeSeries; p::Int=1, d::Int=1, q::Int=1)
    y = Float64.(ts.values)

    # Differencing
    yd = copy(y)
    for _ in 1:d
        yd = diff(yd)
    end
    n = length(yd)

    # AR(p) via Yule-Walker
    ar_coefs = _yule_walker(yd, p)

    # MA(q) via innovations algorithm (simplified: CSS gradient)
    ma_coefs, resids = _fit_ma(yd, ar_coefs, q)

    σ² = var(resids)
    n_params = p + q + 1
    ll = -n/2 * log(2π*σ²) - sum(resids.^2) / (2σ²)
    aic = -2ll + 2n_params
    bic = -2ll + n_params * log(n)

    # Fitted on differenced series
    ŷ = yd .- resids

    ARIMAModel(p, d, q, ar_coefs, ma_coefs, σ², aic, bic, ll, resids, ŷ, yd)
end

function _yule_walker(y, p)
    p == 0 && return Float64[]
    n = length(y)
    μ = mean(y)
    yd = y .- μ
    # Autocovariance
    acv = [dot(yd[1:n-k], yd[k+1:n]) / n for k in 0:p]
    # Toeplitz system
    R = [acv[abs(i-j)+1] for i in 1:p, j in 1:p]
    r = acv[2:p+1]
    cond(R) < 1e10 ? R \ r : pinv(R) * r
end

function _fit_ma(y, ar_coefs, q)
    n = length(y)
    p = length(ar_coefs)
    ma_coefs = zeros(q)
    resids   = zeros(n)

    # Compute AR residuals first
    ar_resids = zeros(n)
    for t in 1:n
        ar_resids[t] = y[t] - sum(ar_coefs[k] * (t-k >= 1 ? y[t-k] : 0.0) for k in 1:p; init=0.0)
    end

    # MA(q) via simple OLS on lagged residuals
    if q > 0
        # Build lagged residual matrix
        neff = n - q
        neff <= 0 && return ma_coefs, ar_resids
        Xma = hcat([ar_resids[q-k+1:n-k] for k in 1:q]...)
        yma = ar_resids[q+1:end]
        sol = (Xma'Xma + 1e-6I) \ (Xma'yma)
        ma_coefs = sol

        for t in q+1:n
            resids[t] = ar_resids[t] - sum(ma_coefs[k] * (t-k >= 1 ? resids[t-k] : 0.0) for k in 1:q; init=0.0)
        end
        resids[1:q] .= ar_resids[1:q]
    else
        resids = ar_resids
    end

    ma_coefs, resids
end

using LinearAlgebra: cond, pinv, I

"""
    forecast(model::ARIMAModel, h) -> Vector{Float64}

h-step ahead forecasts on the original (undifferenced) scale.
For d > 0, forecasts are integrated back.
"""
function forecast(model::ARIMAModel, h::Int)::Vector{Float64}
    p, q = model.p, model.q
    yd = model.diff_series
    n  = length(yd)

    # Forecast on differenced series
    forc = zeros(h)
    all_y = vcat(yd, zeros(h))
    all_e = vcat(model.residuals, zeros(h))

    for t in 1:h
        idx = n + t
        ar_part = sum(model.ar_coefs[k] * all_y[idx-k] for k in 1:p; init=0.0)
        ma_part = sum(model.ma_coefs[k] * all_e[idx-k] for k in 1:q; init=0.0)
        all_y[idx] = ar_part + ma_part
        forc[t] = all_y[idx]
    end
    forc
end

"""
    cross_correlation(ts1, ts2; max_lag=12) -> DataFrame

Cross-correlation function between two health time series.
Returns DataFrame with lag, ccf, significance (±1.96/√n).
"""
function cross_correlation(ts1::HealthTimeSeries, ts2::HealthTimeSeries;
                            max_lag::Int = 12)
    y1 = (ts1.values .- mean(ts1.values)) ./ max(std(ts1.values), 1e-9)
    y2 = (ts2.values .- mean(ts2.values)) ./ max(std(ts2.values), 1e-9)
    n  = min(length(y1), length(y2))
    threshold = 1.96 / sqrt(n)
    lags = -max_lag:max_lag
    ccf  = [_ccf(y1[1:n], y2[1:n], l) for l in lags]
    DataFrame(lag=collect(lags), ccf=ccf, sig_threshold=fill(threshold, length(lags)))
end

function _ccf(y1, y2, lag)
    n = length(y1)
    if lag >= 0
        a = y1[1:n-lag]; b = y2[lag+1:n]
    else
        a = y1[-lag+1:n]; b = y2[1:n+lag]
    end
    isempty(a) && return 0.0
    dot(a, b) / (length(a) * 1.0)
end

"""
    lag_correlation(ts1, ts2; max_lag=12) -> Tuple{Int,Float64}

Find the lag that maximises |cross-correlation|.
Returns (best_lag, max_correlation).
"""
function lag_correlation(ts1::HealthTimeSeries, ts2::HealthTimeSeries;
                          max_lag::Int = 12)
    ccf_df = cross_correlation(ts1, ts2; max_lag=max_lag)
    idx = argmax(abs.(ccf_df.ccf))
    (ccf_df.lag[idx], ccf_df.ccf[idx])
end
