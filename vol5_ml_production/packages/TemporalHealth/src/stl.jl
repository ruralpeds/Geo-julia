# stl.jl — STL decomposition + Holt-Winters smoothing
# Chapter 37.2
#
# STL: Cleveland et al. (1990) "STL: A Seasonal-Trend Decomposition Procedure
# Based on Loess"  Journal of Official Statistics 6(1), 3-73.

"""
    STLResult

Result of STL decomposition.

Fields: trend, seasonal, remainder, seasonal_strength, trend_strength
"""
struct STLResult
    trend    ::Vector{Float64}
    seasonal ::Vector{Float64}
    remainder::Vector{Float64}
    seasonal_strength::Float64  # Var(S) / (Var(S) + Var(R))
    trend_strength   ::Float64  # Var(T) / (Var(T) + Var(R))
    n_inner  ::Int
    n_outer  ::Int
end

"""
    stl_decompose(ts; n_inner=2, n_outer=1, s_window=7, t_window=nothing)
                 -> STLResult

Seasonal-Trend decomposition via LOESS.

Simplified inner loop:
1. Detrend: Y - T
2. Seasonal smoother: LOESS each sub-series of length ⌊n/period⌋
3. Low-pass filter: moving average of seasonal
4. Deseasonalise: Y - S
5. Trend smoother: LOESS on deseasonalised series

`s_window`: span for seasonal LOESS (must be odd, ≥ 7)
`t_window`: span for trend LOESS (default: next odd ≥ 1.5·period + 0.5)
"""
function stl_decompose(ts::HealthTimeSeries;
                       n_inner::Int = 2,
                       n_outer::Int = 1,
                       s_window::Int = 7,
                       t_window::Union{Int,Nothing} = nothing)
    y    = ts.values
    n    = length(y)
    freq = max(ts.freq, 1)

    t_win = isnothing(t_window) ? _next_odd(ceil(Int, 1.5*freq + 0.5) + 2) : t_window
    s_win = max(s_window, 3)

    trend    = zeros(n)
    seasonal = zeros(n)

    for outer in 1:max(n_outer, 1)
        for inner in 1:n_inner
            # 1. Detrend
            detrended = y .- trend

            # 2. Seasonal: average per sub-period position, then LOESS smooth
            for s in 0:freq-1
                idx = s+1:freq:n
                sub = detrended[idx]
                # LOESS smooth of sub-series
                seasonal[idx] .= _loess_smooth(collect(1:length(idx)), sub, s_win)
            end

            # 3. Low-pass filter seasonal (3× moving average of period-length)
            lp = _moving_average(_moving_average(_moving_average(seasonal, freq), freq), 3)
            seasonal .-= lp

            # 4. Trend: LOESS of (y - seasonal)
            deseasoned = y .- seasonal
            trend      = _loess_smooth(collect(1.0:n), deseasoned, t_win)
        end
    end

    remainder = y .- trend .- seasonal
    var_s = var(seasonal)
    var_t = var(trend)
    var_r = var(remainder)
    ss = var_r < 1e-12 ? 1.0 : var_s / (var_s + var_r)
    ts_ = var_r < 1e-12 ? 1.0 : var_t / (var_t + var_r)
    STLResult(trend, seasonal, remainder, ss, ts_, n_inner, n_outer)
end

function _loess_smooth(x, y, span)
    n   = length(x)
    out = zeros(n)
    h   = max(round(Int, span * n / 2), 2)
    for i in 1:n
        lo = max(1, i - h); hi = min(n, i + h)
        xi = x[i]; xw = x[lo:hi]; yw = y[lo:hi]
        # Tricube weights
        d  = maximum(abs.(xw .- xi)); d < 1e-10 && (d = 1.0)
        w  = @. max(1.0 - (abs(xw - xi)/d)^3, 0.0)^3
        w  = max.(w, 1e-10)
        # Weighted linear regression
        sw  = sum(w)
        swx = dot(w, xw)
        swx2= dot(w, xw.^2)
        swy = dot(w, yw)
        swxy= dot(w, xw .* yw)
        denom = sw * swx2 - swx^2
        if abs(denom) < 1e-10
            out[i] = sum(w .* yw) / sw
        else
            b1 = (sw * swxy - swx * swy) / denom
            b0 = (swy - b1 * swx) / sw
            out[i] = b0 + b1 * xi
        end
    end
    out
end

function _moving_average(x, k)
    n   = length(x)
    out = copy(x)
    for i in 1:n
        lo = max(1, i - k÷2); hi = min(n, i + k÷2)
        out[i] = mean(x[lo:hi])
    end
    out
end

_next_odd(x) = iseven(x) ? x + 1 : x

# ── Holt-Winters ──────────────────────────────────────────────────────────────

"""
    HoltWintersModel

Fitted Holt-Winters exponential smoothing model.
"""
struct HoltWintersModel
    α::Float64  # level smoothing
    β::Float64  # trend smoothing
    γ::Float64  # seasonal smoothing
    level    ::Vector{Float64}
    trend    ::Vector{Float64}
    seasonal ::Vector{Float64}
    fitted   ::Vector{Float64}
    freq     ::Int
    multiplicative::Bool
end

"""
    holtwinters(ts; α=0.3, β=0.1, γ=0.1, multiplicative=false) -> HoltWintersModel

Holt-Winters triple exponential smoothing for healthcare time series.

Additive model:
  L_t = α(y_t - S_{t-m}) + (1-α)(L_{t-1} + B_{t-1})
  B_t = β(L_t - L_{t-1}) + (1-β)B_{t-1}
  S_t = γ(y_t - L_{t-1} - B_{t-1}) + (1-γ)S_{t-m}
  ŷ_{t+h} = L_t + h·B_t + S_{t+h-m}
"""
function holtwinters(ts::HealthTimeSeries;
                     α::Float64 = 0.3,
                     β::Float64 = 0.1,
                     γ::Float64 = 0.1,
                     multiplicative::Bool = false)
    y    = ts.values
    n    = length(y)
    m    = max(ts.freq, 2)

    # Initialise
    L = mean(y[1:min(m, n)])
    B = n >= 2m ? (mean(y[m+1:2m]) - mean(y[1:m])) / m : 0.0
    S = zeros(m)
    for i in 1:min(m, n)
        S[i] = multiplicative ? y[i] / max(L, 1e-9) : y[i] - L
    end

    levels   = zeros(n)
    trends   = zeros(n)
    seasonal = zeros(n)
    fitted   = zeros(n)

    for t in 1:n
        s_prev = S[mod(t-1, m) + 1]
        if multiplicative
            L_new = α * (y[t] / max(s_prev, 1e-9)) + (1-α) * (L + B)
            B_new = β * (L_new - L) + (1-β) * B
            S[mod(t-1, m) + 1] = γ * (y[t] / max(L_new, 1e-9)) + (1-γ) * s_prev
            fitted[t] = (L + B) * s_prev
        else
            L_new = α * (y[t] - s_prev) + (1-α) * (L + B)
            B_new = β * (L_new - L) + (1-β) * B
            S[mod(t-1, m) + 1] = γ * (y[t] - L_new) + (1-γ) * s_prev
            fitted[t] = L + B + s_prev
        end
        levels[t] = L_new; trends[t] = B_new
        seasonal[t] = S[mod(t-1, m) + 1]
        L = L_new; B = B_new
    end
    HoltWintersModel(α, β, γ, levels, trends, seasonal, fitted, m, multiplicative)
end

"""
    forecast(model::HoltWintersModel, h) -> Vector{Float64}

h-step ahead point forecasts.
"""
function forecast(model::HoltWintersModel, h::Int)::Vector{Float64}
    L = model.level[end]
    B = model.trend[end]
    S = model.seasonal[end-model.freq+1:end]
    [model.multiplicative ?
        (L + k*B) * S[mod(k-1, model.freq) + 1] :
        (L + k*B) + S[mod(k-1, model.freq) + 1]
     for k in 1:h]
end

# ── Seasonal adjustment ───────────────────────────────────────────────────────

"""
    seasonal_adjustment(ts) -> HealthTimeSeries

Return seasonally adjusted series via STL (remove seasonal component).
"""
function seasonal_adjustment(ts::HealthTimeSeries)
    stl = stl_decompose(ts)
    adj = ts.values .- stl.seasonal
    HealthTimeSeries(ts.times, adj, ts.name * "_sa", ts.unit, ts.freq, ts.metadata)
end
