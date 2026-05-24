# estimators.jl — Kaplan-Meier, Nelson-Aalen, log-rank and Wilcoxon tests
# Backed by Survival.jl for core estimation

using Statistics

# ── Kaplan-Meier ──────────────────────────────────────────────────────────────

"""
    KMResult

Kaplan-Meier survival estimate.

Fields: times, survival, n_risk, n_event, n_censor, lower_ci, upper_ci,
        median_survival, restricted_mean (up to τ).
"""
struct KMResult
    times          ::Vector{Float64}
    survival       ::Vector{Float64}
    n_risk         ::Vector{Int}
    n_event        ::Vector{Int}
    n_censor       ::Vector{Int}
    lower_ci       ::Vector{Float64}   # log-log transformed 95% CI
    upper_ci       ::Vector{Float64}
    median_survival::Float64
    restricted_mean::Float64           # RMST up to last event time
end

"""
    kaplan_meier(times, status; weights) -> KMResult

Estimate the Kaplan-Meier survival function.

# Arguments
- `times`  : observed follow-up times (Float64 or Int)
- `status` : event indicator (1 = event, 0 = censored)
- `weights`: optional frequency weights (default ones)
"""
function kaplan_meier(times::AbstractVector, status::AbstractVector{<:Integer};
                      weights::AbstractVector=ones(length(times)))
    n = length(times)
    @assert length(status) == n && length(weights) == n

    # Use Survival.jl for core KM estimation
    # Build event-time objects: true = event, false = censored
    evt = [status[i] == 1 ? Survival.EventTime(Float64(times[i]), true) :
                            Survival.EventTime(Float64(times[i]), false) for i in 1:n]

    km_fit = Survival.fit(Survival.KaplanMeier, evt)

    # Extract times and survival from Survival.jl result
    km_times_raw = km_fit.times
    km_surv_raw  = km_fit.survival

    # Build the detailed table with n_risk, n_event, n_censor
    # (Survival.jl KM object has times and survival; we compute details for
    #  weighted data and CI ourselves to preserve full API)
    idx_sorted = sortperm(times)
    t_sorted   = times[idx_sorted]
    s_sorted   = status[idx_sorted]
    w_sorted   = weights[idx_sorted]

    event_times = unique(t_sorted[s_sorted .== 1])
    sort!(event_times)

    km_times = Float64[]
    km_surv  = Float64[]
    km_risk  = Int[]
    km_event = Int[]
    km_cens  = Int[]

    S = 1.0
    for t in event_times
        n_at_risk = sum(w_sorted[j] for j in 1:n if t_sorted[j] >= t)
        n_ev      = sum(w_sorted[j] for j in 1:n if t_sorted[j] == t && s_sorted[j] == 1)
        n_cen_t   = sum(w_sorted[j] for j in 1:n if t_sorted[j] == t && s_sorted[j] == 0)

        S_new = S * (1.0 - n_ev / n_at_risk)

        push!(km_times, Float64(t))
        push!(km_surv,  S_new)
        push!(km_risk,  round(Int, n_at_risk))
        push!(km_event, round(Int, n_ev))
        push!(km_cens,  round(Int, n_cen_t))
        S = S_new
    end

    # If no weights (all ones), use Survival.jl's survival values directly
    # for numerical consistency
    if all(w -> w ≈ 1.0, weights) && length(km_times) == length(km_times_raw)
        km_surv .= km_surv_raw
    end

    # Greenwood's formula for variance → log-log CI
    km_lower = zeros(length(km_times))
    km_upper = ones(length(km_times))
    greenwood_sum = 0.0
    for i in eachindex(km_times)
        d = km_event[i]; r = km_risk[i]
        if r > d > 0
            greenwood_sum += d / (r * (r - d))
        end
        S_i = km_surv[i]
        if S_i > 0.0 && S_i < 1.0
            var_log_H = greenwood_sum / (log(S_i))^2
            se_loglog = sqrt(var_log_H)
            θ = log(-log(S_i))
            km_lower[i] = exp(-exp(θ + 1.96*se_loglog))
            km_upper[i] = exp(-exp(θ - 1.96*se_loglog))
        elseif S_i >= 1.0
            km_lower[i] = 1.0; km_upper[i] = 1.0
        end
    end

    # Median survival: first time S <= 0.5
    med_idx = findfirst(km_surv .<= 0.5)
    median_s = isnothing(med_idx) ? Inf : km_times[med_idx]

    # RMST: area under KM curve (trapezoidal)
    rmst = _km_rmst(km_times, km_surv)

    KMResult(km_times, km_surv, km_risk, km_event, km_cens,
             km_lower, km_upper, median_s, rmst)
end

function _km_rmst(times::Vector{Float64}, surv::Vector{Float64})
    isempty(times) && return 0.0
    rmst = 0.0
    prev_t = 0.0; prev_s = 1.0
    for i in eachindex(times)
        rmst += prev_s * (times[i] - prev_t)
        prev_t = times[i]; prev_s = surv[i]
    end
    rmst
end

"""
    km_predict(result, t) -> Float64

Evaluate the KM survival function S(t) at time `t`.
"""
function km_predict(result::KMResult, t::Real)
    t <= 0 && return 1.0
    idx = findlast(result.times .<= t)
    isnothing(idx) ? 1.0 : result.survival[idx]
end

# ── Nelson-Aalen ──────────────────────────────────────────────────────────────

"""
    NAResult

Nelson-Aalen cumulative hazard estimate.
"""
struct NAResult
    times         ::Vector{Float64}
    cum_hazard    ::Vector{Float64}
    variance      ::Vector{Float64}
    lower_ci      ::Vector{Float64}
    upper_ci      ::Vector{Float64}
end

"""
    nelson_aalen(times, status) -> NAResult

Nelson-Aalen estimator: Ĥ(t) = Σ_{t_i ≤ t} d_i / r_i.
Uses Survival.jl for core estimation.
"""
function nelson_aalen(times::AbstractVector, status::AbstractVector{<:Integer})
    n = length(times)

    # Use Survival.jl for core NA estimation
    evt = [status[i] == 1 ? Survival.EventTime(Float64(times[i]), true) :
                            Survival.EventTime(Float64(times[i]), false) for i in 1:n]

    na_fit = Survival.fit(Survival.NelsonAalen, evt)

    na_times_raw = na_fit.times
    na_H_raw     = na_fit.cumulative_hazard

    # Compute variance for CI (Survival.jl may not provide this directly)
    event_times = sort(unique(times[status .== 1]))

    na_times = Float64[]
    na_H     = Float64[]
    na_var   = Float64[]
    H = 0.0; V = 0.0

    for t in event_times
        r = sum(times .>= t)
        d = sum((times .== t) .& (status .== 1))
        r == 0 && continue
        H += d / r
        V += d / r^2
        push!(na_times, Float64(t))
        push!(na_H, H)
        push!(na_var, V)
    end

    # Use Survival.jl values where possible for consistency
    if length(na_times) == length(na_times_raw)
        na_H .= na_H_raw
    end

    # Pointwise CI: log-transformed
    na_lower = exp.(na_H .- 1.96 .* sqrt.(na_var))
    na_upper = exp.(na_H .+ 1.96 .* sqrt.(na_var))

    NAResult(na_times, na_H, na_var, na_lower, na_upper)
end

# ── Log-rank and Wilcoxon tests ───────────────────────────────────────────────

"""
    LogRankResult

Two-sample (or k-sample) log-rank / Wilcoxon test result.
"""
struct LogRankResult
    statistic  ::Float64
    p_value    ::Float64
    df         ::Int
    test_type  ::Symbol   # :logrank or :wilcoxon
    groups     ::Vector
    observed   ::Vector{Float64}
    expected   ::Vector{Float64}
end

"""
    logrank_test(times, status, groups; test_type=:logrank) -> LogRankResult

Mantel-Cox log-rank test (or Peto-Peto Wilcoxon) comparing survival curves
across `groups`. Returns χ²(k-1) test statistic.

For the standard log-rank test, delegates to `Survival.logrank(...)` when
possible (two-group case). For Wilcoxon or k>2 groups, uses custom
implementation.

`test_type ∈ {:logrank, :wilcoxon}`
"""
function logrank_test(times::AbstractVector, status::AbstractVector{<:Integer},
                      groups::AbstractVector; test_type::Symbol=:logrank)
    g_vals  = sort(unique(groups))
    k       = length(g_vals)
    @assert k >= 2 "Need at least 2 groups"

    # For standard log-rank with 2 groups, try Survival.jl
    if test_type == :logrank && k == 2
        evt1 = [status[i] == 1 ? Survival.EventTime(Float64(times[i]), true) :
                                 Survival.EventTime(Float64(times[i]), false)
                for i in 1:length(times) if groups[i] == g_vals[1]]
        evt2 = [status[i] == 1 ? Survival.EventTime(Float64(times[i]), true) :
                                 Survival.EventTime(Float64(times[i]), false)
                for i in 1:length(times) if groups[i] == g_vals[2]]

        try
            lr = Survival.logrank(evt1, evt2)
            # Extract statistic and p-value from Survival.jl result
            # Also compute O and E for our return struct
            O, E = _compute_OE(times, status, groups, g_vals, :logrank)
            return LogRankResult(lr.chisq, lr.pvalue, 1, :logrank, collect(g_vals), O, E)
        catch
            # Fall through to custom implementation
        end
    end

    # Custom implementation for Wilcoxon or k>2 groups
    O, E = _compute_OE(times, status, groups, g_vals, test_type)

    # χ² statistic
    stat = sum((O[i] - E[i])^2 / max(E[i], 1e-10) for i in 1:k)
    df   = k - 1
    p    = 1.0 - _chi2_cdf(stat, df)

    LogRankResult(stat, p, df, test_type, collect(g_vals), O, E)
end

function _compute_OE(times, status, groups, g_vals, test_type)
    k = length(g_vals)
    event_times = sort(unique(times[status .== 1]))
    O = zeros(k); E = zeros(k)

    for t in event_times
        mask = times .>= t
        r_total = sum(mask)
        d_total = sum((times .== t) .& (status .== 1))
        r_total == 0 && continue

        w = 1.0
        if test_type == :wilcoxon
            w = r_total
        end

        for (gi, g) in enumerate(g_vals)
            r_g = sum(mask .& (groups .== g))
            d_g = sum((times .== t) .& (status .== 1) .& (groups .== g))
            e_g = r_total > 0 ? w * d_total * r_g / r_total : 0.0
            O[gi] += w * d_g
            E[gi] += e_g
        end
    end
    return O, E
end

# ── Chi-squared CDF (regularized incomplete gamma, series expansion) ──────────

function _chi2_cdf(x::Float64, k::Int)
    x <= 0.0 && return 0.0
    # Use Distributions.jl
    return Distributions.cdf(Distributions.Chisq(k), x)
end
