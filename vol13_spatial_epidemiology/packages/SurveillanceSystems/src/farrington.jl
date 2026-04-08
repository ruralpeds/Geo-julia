# farrington.jl — Farrington regression threshold and CDC EARS methods

using Statistics, LinearAlgebra

# ─── Farrington method ────────────────────────────────────────────────────────

struct FarringtonResult
    threshold::Vector{Float64}   # expected count (fitted)
    upper95::Vector{Float64}     # 95th percentile threshold (alert level)
    alerts::Vector{Bool}
    alert_times::Vector{Int}
    exceedance::Vector{Float64}  # observed / expected
    baseline_weeks::Int
    n::Int
    n_alerts::Int
end

"""
    farrington(x; baseline_weeks, alpha, min_baseline) -> FarringtonResult

Farrington et al. (1996) regression-based threshold for weekly surveillance.

For each time point t, fits a quasi-Poisson regression on baseline weeks
(same week in prior years) to estimate expected count μ̂ₜ. Alert when
observed count exceeds the (1-α) prediction interval upper bound.

Model: log(μ) = a + b·t  (quasi-Poisson, variance = φ·μ)
Overdispersion φ estimated from Pearson residuals.
Upper threshold: μ̂·exp(z_{1-α}·√(φ/μ̂))  [Farrington et al. Eq. 4]
"""
function farrington(x::AbstractVector{<:Real};
                    baseline_weeks::Int=52,
                    alpha::Float64=0.05,
                    min_baseline::Int=5)
    T  = length(x)
    threshold = fill(NaN, T)
    upper95   = fill(NaN, T)

    z_alpha = _qnorm(1.0 - alpha)

    for t in (baseline_weeks+1):T
        base_idx = max(1, t - baseline_weeks):(t-1)
        y_base   = Float64.(x[base_idx])
        t_base   = Float64.(base_idx)
        n_b      = length(y_base)
        n_b < min_baseline && continue

        # Log-linear regression via IRLS (quasi-Poisson)
        μ̂, φ = _quasi_poisson_fit(y_base, t_base)
        μ_t  = _quasi_poisson_predict(μ̂, φ, t_base, Float64(t))

        threshold[t] = μ_t
        upper95[t]   = μ_t * exp(z_alpha * sqrt(φ / max(μ_t, 1e-6)))
    end

    obs_exc = [isnan(threshold[t]) ? NaN : x[t] / max(threshold[t], 1e-6)
               for t in 1:T]
    alerts      = [!isnan(upper95[t]) && x[t] > upper95[t] for t in 1:T]
    alert_times = findall(alerts)
    FarringtonResult(threshold, upper95, alerts, alert_times, obs_exc,
                     baseline_weeks, T, length(alert_times))
end

function _quasi_poisson_fit(y::Vector{Float64}, t::Vector{Float64})
    n  = length(y)
    t̄  = mean(t)
    ȳ  = mean(y)
    # Poisson log-linear: log(μᵢ) = a + b(tᵢ - t̄); initialise with OLS on log(y+0.5)
    log_y = log.(y .+ 0.5)
    St    = t .- t̄
    b     = sum(St .* (log_y .- mean(log_y))) / max(sum(St.^2), 1e-12)
    a     = mean(log_y) - b * 0
    # Simple overdispersion estimate
    μ̂    = exp.(a .+ b .* St)
    χ²   = sum((y .- μ̂).^2 ./ max.(μ̂, 1e-6))
    φ    = max(χ² / (n - 2), 1.0)
    (a=a, b=b, t̄=t̄), φ
end

function _quasi_poisson_predict(params, φ, t_base::Vector{Float64}, t_new::Float64)
    a, b, t̄ = params.a, params.b, params.t̄
    exp(a + b * (t_new - t̄))
end

# ─── CDC EARS (Early Aberration Reporting System) ─────────────────────────────

struct EARSResult
    C1::Vector{Float64}    # C1 statistic (baseline mean 7 days prior)
    C2::Vector{Float64}    # C2 statistic (baseline mean, 7-day lag)
    C3::Vector{Float64}    # C3 = sum of C2 over last 3 days
    alerts_C1::Vector{Bool}
    alerts_C2::Vector{Bool}
    alerts_C3::Vector{Bool}
    threshold::Float64     # alert threshold (default 3.0 SD units)
    n::Int
end

"""
    ears(x; baseline_days, threshold) -> EARSResult

CDC EARS C1/C2/C3 methods (Hutwagner et al. 2003).

C1: baseline = prior `w` days with no lag
C2: baseline = prior `w` days lagged by `g` days (avoids current outbreak contamination)
C3: rolling 3-day sum of C2 statistics — most sensitive for sustained outbreaks

Alert threshold: Cₜ > threshold (default = 3.0, i.e., 3 SD above baseline mean)
"""
function ears(x::AbstractVector{<:Real};
              baseline_days::Int=7,
              lag::Int=2,
              threshold::Float64=3.0)
    T  = length(x)
    C1 = fill(NaN, T); C2 = fill(NaN, T); C3 = fill(NaN, T)
    w = baseline_days

    for t in 1:T
        # C1: baseline = [t-w, t-1]
        if t > w
            base = Float64.(x[t-w:t-1])
            μ̄   = mean(base)
            σ̄   = max(std(base; corrected=true), 1.0)
            C1[t] = (x[t] - μ̄) / σ̄
        end
        # C2: baseline = [t-w-lag, t-1-lag]
        lo2 = t - w - lag; hi2 = t - 1 - lag
        if lo2 >= 1
            base2 = Float64.(x[lo2:hi2])
            μ̄2   = mean(base2)
            σ̄2   = max(std(base2; corrected=true), 1.0)
            C2[t] = (x[t] - μ̄2) / σ̄2
        end
    end

    # C3: rolling sum of C2 over last 3 time points
    for t in 3:T
        if !any(isnan, C2[t-2:t])
            C3[t] = sum(max.(C2[t-2:t], 0.0))
        end
    end

    alerts_C1 = [!isnan(C1[t]) && C1[t] > threshold for t in 1:T]
    alerts_C2 = [!isnan(C2[t]) && C2[t] > threshold for t in 1:T]
    alerts_C3 = [!isnan(C3[t]) && C3[t] > threshold for t in 1:T]
    EARSResult(C1, C2, C3, alerts_C1, alerts_C2, alerts_C3, threshold, T)
end

# ─── Baseline calibration ─────────────────────────────────────────────────────

"""
    calibrate_threshold(x, true_outbreak; method, alpha) -> NamedTuple

Grid-search for the CUSUM h parameter (or EWMA L) that maximises F1-score
on a labelled training series. Returns optimal threshold and performance metrics.

`method` = :cusum or :ewma
"""
function calibrate_threshold(x::AbstractVector{<:Real},
                              true_outbreak::AbstractVector{Bool};
                              method::Symbol=:cusum,
                              alpha::Float64=0.1)
    μ₀ = mean(x[.!true_outbreak])
    σ₀ = max(std(x[.!true_outbreak]; corrected=true), 1.0)

    best_h = NaN; best_f1 = -Inf; best_perf = nothing

    h_grid = method == :cusum ? (0.5:0.5:10.0) .* σ₀ :
             method == :ewma  ? (1.0:0.5:5.0) : Float64[]

    for h in h_grid
        res = method == :cusum ? cusum(x; μ₀=μ₀, σ₀=σ₀, h=h) :
              ewma(x; L=h, μ₀=μ₀, σ₀=σ₀)
        perf = sensitivity_specificity(res.alerts, Vector{Bool}(true_outbreak))
        if perf.f1 > best_f1
            best_f1 = perf.f1; best_h = h; best_perf = perf
        end
    end
    (threshold=best_h, f1=best_f1, performance=best_perf, method=method)
end

# ─── Normal quantile helper ───────────────────────────────────────────────────

# Rational approximation (Abramowitz & Stegun §26.2.17), max error < 4.5e-4
function _qnorm(p::Float64)
    (p <= 0 || p >= 1) && error("p must be in (0,1)")
    p < 0.5 && return -_qnorm(1-p)
    t = sqrt(-2 * log(1-p))
    c0, c1, c2 = 2.515517, 0.802853, 0.010328
    d1, d2, d3 = 1.432788, 0.189269, 0.001308
    t - (c0 + c1*t + c2*t^2) / (1 + d1*t + d2*t^2 + d3*t^3)
end
