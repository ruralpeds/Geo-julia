# cusum.jl — CUSUM and EWMA control charts for disease surveillance

using Statistics

# ─── CUSUM ────────────────────────────────────────────────────────────────────

struct CUSUMResult
    S::Vector{Float64}       # CUSUM statistic S_t = max(0, S_{t-1} + x_t - μ₀ - k)
    alerts::Vector{Bool}     # alert[t] = true if S_t > h
    alert_times::Vector{Int} # time indices where alerts fired
    μ₀::Float64              # in-control mean
    σ₀::Float64              # in-control SD
    k::Float64               # reference value (allowance)
    h::Float64               # decision interval (threshold)
    n::Int
    n_alerts::Int
end

"""
    cusum(x; μ₀, σ₀, k, h, two_sided) -> CUSUMResult

One-sided upper CUSUM for Poisson/normal count data (Page 1954).

- `x`     — observed count time series (length T)
- `μ₀`   — in-control mean (default = mean(x))
- `σ₀`   — in-control SD (default = √μ₀, i.e., Poisson assumption)
- `k`     — reference value = (μ₁-μ₀)/2; default = σ₀/2 (detects 1σ shift)
- `h`     — decision interval; default = 5σ₀ (Hawkins & Olwell recommendation)
- `two_sided` — also track lower CUSUM (not returned, but affects n_alerts)

CUSUM statistic: Sₜ = max(0, Sₜ₋₁ + (xₜ − μ₀ − k))
Alert at time t: Sₜ > h
"""
function cusum(x::AbstractVector{<:Real};
               μ₀::Float64=mean(x),
               σ₀::Float64=sqrt(max(μ₀, 1.0)),
               k::Float64=σ₀/2,
               h::Float64=5.0*σ₀,
               two_sided::Bool=false)
    T   = length(x)
    S   = zeros(T)
    SL  = zeros(T)   # lower (two-sided)
    S[1]  = max(0.0, x[1] - μ₀ - k)
    SL[1] = two_sided ? max(0.0, μ₀ - k - x[1]) : 0.0
    for t in 2:T
        S[t]  = max(0.0, S[t-1]  + (x[t] - μ₀ - k))
        SL[t] = two_sided ? max(0.0, SL[t-1] + (μ₀ - k - x[t])) : 0.0
    end
    alerts      = two_sided ? (S .> h) .| (SL .> h) : (S .> h)
    alert_times = findall(alerts)
    CUSUMResult(S, alerts, alert_times, μ₀, σ₀, k, h, T, length(alert_times))
end

"""
    cusum_reset(x; μ₀, k, h) -> CUSUMResult

CUSUM with automatic reset: after an alert, S is reset to 0.
Useful for tracking successive outbreaks in a long series.
"""
function cusum_reset(x::AbstractVector{<:Real};
                     μ₀::Float64=mean(x),
                     σ₀::Float64=sqrt(max(μ₀,1.0)),
                     k::Float64=σ₀/2,
                     h::Float64=5.0*σ₀)
    T   = length(x)
    S   = zeros(T)
    S[1] = max(0.0, x[1] - μ₀ - k)
    for t in 2:T
        prev = S[t-1] > h ? 0.0 : S[t-1]   # reset after alert
        S[t] = max(0.0, prev + (x[t] - μ₀ - k))
    end
    alerts      = S .> h
    alert_times = findall(alerts)
    CUSUMResult(S, alerts, alert_times, μ₀, σ₀, k, h, T, length(alert_times))
end

# ─── EWMA ─────────────────────────────────────────────────────────────────────

struct EWMAResult
    Z::Vector{Float64}       # EWMA statistic Zₜ = λxₜ + (1-λ)Zₜ₋₁
    ucl::Vector{Float64}     # upper control limit UCLₜ
    lcl::Vector{Float64}     # lower control limit LCLₜ
    alerts::Vector{Bool}
    alert_times::Vector{Int}
    λ::Float64               # smoothing weight ∈ (0,1]
    L::Float64               # number of sigmas for control limits
    μ₀::Float64
    σ₀::Float64
    n::Int
    n_alerts::Int
end

"""
    ewma(x; λ, L, μ₀, σ₀) -> EWMAResult

Exponentially Weighted Moving Average control chart (Roberts 1959).

- `λ`  — smoothing parameter ∈ (0,1]; small λ → more smoothing (default 0.2)
- `L`  — control limit width in sigma units (default 3.0)

Statistic: Zₜ = λxₜ + (1-λ)Zₜ₋₁,  Z₀ = μ₀
Variance:  Var(Zₜ) ≈ σ₀²·λ/(2-λ)·[1-(1-λ)^{2t}]
UCL/LCLₜ = μ₀ ± L·σ₀·√(λ/(2-λ)·[1-(1-λ)^{2t}])
"""
function ewma(x::AbstractVector{<:Real};
              λ::Float64=0.2,
              L::Float64=3.0,
              μ₀::Float64=mean(x),
              σ₀::Float64=sqrt(max(μ₀,1.0)))
    T   = length(x)
    Z   = zeros(T)
    ucl = zeros(T)
    lcl = zeros(T)
    Z[1] = λ * x[1] + (1-λ) * μ₀
    for t in 1:T
        if t > 1; Z[t] = λ * x[t] + (1-λ) * Z[t-1]; end
        half_width = L * σ₀ * sqrt(λ/(2-λ) * (1 - (1-λ)^(2t)))
        ucl[t] = μ₀ + half_width
        lcl[t] = μ₀ - half_width
    end
    alerts      = (Z .> ucl) .| (Z .< lcl)
    alert_times = findall(alerts)
    EWMAResult(Z, ucl, lcl, alerts, alert_times, λ, L, μ₀, σ₀, T, length(alert_times))
end

# ─── Alarm aggregation ────────────────────────────────────────────────────────

"""
    combine_alerts(results...) -> Vector{Bool}

Logical OR of alert vectors from multiple surveillance methods.
Returns a composite alert vector for ensemble surveillance.
"""
function combine_alerts(results...)
    isempty(results) && return Bool[]
    n = length(first(results).alerts)
    out = falses(n)
    for r in results
        out .|= r.alerts
    end
    out
end

"""
    sensitivity_specificity(alerts::Vector{Bool}, true_outbreak::Vector{Bool}) -> NamedTuple

Compute sensitivity, specificity, PPV, NPV, and F1 for a binary alert vector
against a known outbreak indicator.
"""
function sensitivity_specificity(alerts::Vector{Bool}, truth::Vector{Bool})
    length(alerts) == length(truth) ||
        error("alerts and truth must have the same length")
    tp = sum(alerts .& truth)
    fp = sum(alerts .& .!truth)
    fn = sum(.!alerts .& truth)
    tn = sum(.!alerts .& .!truth)
    sens = tp / max(tp + fn, 1)
    spec = tn / max(tn + fp, 1)
    ppv  = tp / max(tp + fp, 1)
    npv  = tn / max(tn + fn, 1)
    f1   = 2tp / max(2tp + fp + fn, 1)
    (sensitivity=sens, specificity=spec, ppv=ppv, npv=npv, f1=f1,
     tp=tp, fp=fp, fn=fn, tn=tn)
end
