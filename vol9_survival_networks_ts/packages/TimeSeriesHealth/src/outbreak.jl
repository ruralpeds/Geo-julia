# outbreak.jl — Outbreak detection algorithms
# CUSUM, Farrington algorithm, Poisson EWMA

using Statistics, LinearAlgebra

# ── CUSUM (Page 1954) ─────────────────────────────────────────────────────────

"""
    CUSUMResult

CUSUM outbreak detection result.

Fields: statistics (upper CUSUM), alarms (Bool vector), threshold,
        alarm_times, reset_times.
"""
struct CUSUMResult
    statistics  ::Vector{Float64}
    alarms      ::Vector{Bool}
    threshold   ::Float64
    alarm_times ::Vector{Int}
    reset_times ::Vector{Int}
    μ0          ::Float64    # baseline mean
    k           ::Float64    # allowance parameter
end

"""
    cusum_detect(y; μ0, σ0, threshold, k, reset_on_alarm) -> CUSUMResult

One-sided CUSUM for detecting upward shifts in incidence.

C_0 = 0
C_t = max(0, C_{t-1} + (y_t - μ0)/σ0 - k)

Alarm when C_t > threshold (default h=4 = 4 standard deviations).
"""
function cusum_detect(y::AbstractVector;
                      μ0::Float64=mean(y[1:max(1,length(y)÷4)]),
                      σ0::Float64=std(y[1:max(1,length(y)÷4)]) + 1e-8,
                      threshold::Float64=4.0,
                      k::Float64=0.5,
                      reset_on_alarm::Bool=false)
    n      = length(y)
    C      = zeros(n)
    alarms = falses(n)
    alarm_times = Int[]
    reset_times = Int[]

    C_prev = 0.0
    for t in 1:n
        z      = (y[t] - μ0) / σ0
        C[t]   = max(0.0, C_prev + z - k)
        if C[t] > threshold
            alarms[t] = true
            push!(alarm_times, t)
            if reset_on_alarm
                C[t] = 0.0
                push!(reset_times, t)
            end
        end
        C_prev = C[t]
    end

    CUSUMResult(C, alarms, threshold, alarm_times, reset_times, μ0, k)
end

# ── Farrington algorithm (Farrington et al. 1996) ─────────────────────────────

"""
    FarringtonResult

Farrington outbreak detection result.
"""
struct FarringtonResult
    expected    ::Vector{Float64}   # Poisson expected counts
    upper_bound ::Vector{Float64}   # 95th percentile prediction interval
    alarms      ::Vector{Bool}
    alarm_times ::Vector{Int}
    overdispersion::Float64
    n_baseline  ::Int
end

"""
    farrington_detect(y; n_years, w, alpha, trend) -> FarringtonResult

Farrington algorithm for weekly/monthly count data.

For each time t:
1. Select historical observations in a window of ±w weeks over previous n_years
2. Fit weighted Poisson GLM: log(μ_t) = α + β·t (trend optional)
3. Estimate overdispersion φ = X²/(n-p)
4. Upper bound: μ̂ + z_{1-α} * sqrt(φ * μ̂)
5. Alarm if y_t > upper_bound

Winsorized weights reduce influence of past epidemics (Noufaily 2013).
"""
function farrington_detect(y::AbstractVector;
                            n_years::Int=3,
                            w::Int=2,
                            alpha::Float64=0.05,
                            trend::Bool=true,
                            period::Int=52)
    n       = length(y)
    expect  = zeros(n)
    upper   = zeros(n)
    alarms  = falses(n)
    alarm_t = Int[]
    phi_est = 1.0

    for t in max(1, n_years*period + 1):n
        # Collect reference weeks from previous years
        ref_idx = Int[]
        for yr in 1:n_years
            base = t - yr * period
            for δ in -w:w
                idx = base + δ
                1 <= idx < t && push!(ref_idx, idx)
            end
        end
        isempty(ref_idx) && continue
        sort!(unique!(ref_idx))

        y_ref = y[ref_idx]
        t_ref = ref_idx

        # Winsorize: cap observations above 95th percentile
        q95    = quantile(y_ref, 0.95)
        w_weights = [yv > q95 ? q95 / max(yv, 1e-8) : 1.0 for yv in y_ref]

        # Weighted Poisson GLM: log(μ) = α + β*t (IRLS, 1 cycle)
        μ_w  = mean(y_ref .* w_weights)
        if trend && length(t_ref) > 2
            t_c   = t_ref .- mean(t_ref)
            X_ref = hcat(ones(length(t_ref)), t_c)
            # IRLS step
            μ_est = fill(max(μ_w, 0.1), length(t_ref))
            for _ in 1:5
                W_irls = diagm(w_weights .* μ_est)
                β_irls = (X_ref'*W_irls*X_ref + 1e-8I) \ X_ref'*(W_irls*log.(max.(μ_est, 1e-8)) .+ w_weights.*(y_ref .- μ_est))
                μ_est  = exp.(X_ref * β_irls)
                μ_est  = max.(μ_est, 1e-8)
            end
            t_new  = t - mean(t_ref)
            β_f    = (X_ref'*diagm(w_weights.*μ_est)*X_ref + 1e-8I) \ X_ref'*(w_weights.*y_ref)
            expect[t] = max(exp(β_f[1] + β_f[2]*t_new), 0.01)
        else
            expect[t] = max(μ_w, 0.01)
        end

        # Overdispersion
        res2 = sum(w_weights .* (y_ref .- expect[t]).^2 ./ max(expect[t], 1e-8))
        df   = max(length(y_ref) - (trend ? 2 : 1), 1)
        phi_est = max(res2 / df, 1.0)

        # Upper prediction bound: negative binomial approximation
        z_α   = 1.6449   # z_{0.95}
        upper[t] = expect[t] + z_α * sqrt(phi_est * expect[t])

        if y[t] > upper[t]
            alarms[t] = true
            push!(alarm_t, t)
        end
    end

    FarringtonResult(expect, upper, alarms, alarm_t, phi_est,
                     n_years * period)
end

# ── Poisson EWMA ──────────────────────────────────────────────────────────────

"""
    PoissonEWMAResult

Poisson EWMA surveillance result.
"""
struct PoissonEWMAResult
    statistics  ::Vector{Float64}   # EWMA of counts
    ucl         ::Vector{Float64}   # upper control limit
    alarms      ::Vector{Bool}
    alarm_times ::Vector{Int}
    λ_ewma      ::Float64           # smoothing constant
    L           ::Float64           # multiplier for UCL
    baseline_μ  ::Float64
end

"""
    poisson_ewma(y; λ=0.2, L=3.0, n_baseline) -> PoissonEWMAResult

Poisson EWMA (Borror et al. 1998) for count surveillance.

Z_t = λ·y_t + (1-λ)·Z_{t-1}
UCL_t = Z_t + L·sqrt(λ/(2-λ) · μ_0)

Alarm when Z_t > UCL.
"""
function poisson_ewma(y::AbstractVector;
                      λ::Float64=0.2,
                      L::Float64=3.0,
                      n_baseline::Int=max(1, length(y)÷5))
    n       = length(y)
    μ_0     = mean(y[1:n_baseline])
    Z       = zeros(n)
    ucl     = zeros(n)
    alarms  = falses(n)
    alarm_t = Int[]

    Z_prev  = μ_0
    for t in 1:n
        Z[t]   = λ * y[t] + (1 - λ) * Z_prev
        # Asymptotic UCL
        ucl[t] = μ_0 + L * sqrt(λ / (2 - λ) * μ_0)
        if Z[t] > ucl[t]
            alarms[t] = true
            push!(alarm_t, t)
        end
        Z_prev = Z[t]
    end

    PoissonEWMAResult(Z, ucl, alarms, alarm_t, λ, L, μ_0)
end

# ── Aberration summary ────────────────────────────────────────────────────────

"""
    aberration_summary(y, results...) -> NamedTuple

Compare multiple detection methods and return a consensus alarm flag.
"""
function aberration_summary(y::AbstractVector, results::Union{CUSUMResult, FarringtonResult, PoissonEWMAResult}...)
    n = length(y)
    combined_alarms = falses(n)
    method_names    = String[]
    alarm_counts    = Int[]

    for r in results
        combined_alarms .|= r.alarms
        push!(alarm_counts, sum(r.alarms))
        if isa(r, CUSUMResult);       push!(method_names, "CUSUM")
        elseif isa(r, FarringtonResult); push!(method_names, "Farrington")
        else;                          push!(method_names, "PoissonEWMA")
        end
    end

    (method=method_names, n_alarms=alarm_counts,
     combined_alarms=combined_alarms,
     n_combined=sum(combined_alarms),
     alarm_rate=mean(combined_alarms))
end
