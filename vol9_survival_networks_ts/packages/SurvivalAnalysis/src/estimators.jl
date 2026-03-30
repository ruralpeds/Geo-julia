# estimators.jl — Kaplan-Meier, Nelson-Aalen, log-rank and Wilcoxon tests

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

    # Collect unique event times
    idx_sorted = sortperm(times)
    t_sorted   = times[idx_sorted]
    s_sorted   = status[idx_sorted]
    w_sorted   = weights[idx_sorted]

    event_times = unique(t_sorted[s_sorted .== 1])
    sort!(event_times)

    # Build KM table
    km_times = Float64[]
    km_surv  = Float64[]
    km_risk  = Int[]
    km_event = Int[]
    km_cens  = Int[]

    S = 1.0
    t_idx = 1  # current position in sorted arrays

    for t in event_times
        # Count risk set, events, censored at this time
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
"""
function nelson_aalen(times::AbstractVector, status::AbstractVector{<:Integer})
    n = length(times)
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

`test_type ∈ {:logrank, :wilcoxon}`
"""
function logrank_test(times::AbstractVector, status::AbstractVector{<:Integer},
                      groups::AbstractVector; test_type::Symbol=:logrank)
    g_vals  = sort(unique(groups))
    k       = length(g_vals)
    @assert k >= 2 "Need at least 2 groups"

    event_times = sort(unique(times[status .== 1]))
    O = zeros(k); E = zeros(k)

    for t in event_times
        mask = times .>= t
        r_total = sum(mask)
        d_total = sum((times .== t) .& (status .== 1))
        r_total == 0 && continue

        # KM weight for Wilcoxon
        w = 1.0
        if test_type == :wilcoxon
            w = r_total   # Peto-Peto weight ≈ n_risk
        end

        for (gi, g) in enumerate(g_vals)
            r_g = sum(mask .& (groups .== g))
            d_g = sum((times .== t) .& (status .== 1) .& (groups .== g))
            e_g = r_total > 0 ? w * d_total * r_g / r_total : 0.0
            O[gi] += w * d_g
            E[gi] += e_g
        end
    end

    # χ² statistic (using k-1 contrast)
    # For 2 groups: (O1-E1)²/E1 + (O2-E2)²/E2
    stat = sum((O[i] - E[i])^2 / max(E[i], 1e-10) for i in 1:k)
    df   = k - 1
    p    = 1.0 - _chi2_cdf(stat, df)

    LogRankResult(stat, p, df, test_type, collect(g_vals), O, E)
end

# ── Chi-squared CDF (regularized incomplete gamma, series expansion) ──────────

function _chi2_cdf(x::Float64, k::Int)
    x <= 0.0 && return 0.0
    _regularized_gamma_lower(k / 2.0, x / 2.0)
end

function _regularized_gamma_lower(a::Float64, x::Float64)
    x == 0.0 && return 0.0
    # Series expansion: P(a,x) = e^{-x} x^a / Γ(a) Σ x^n/Γ(a+n+1)
    term = 1.0 / a
    s = term
    for n in 1:200
        term *= x / (a + n)
        s += term
        abs(term) < 1e-12 * abs(s) && break
    end
    s * exp(-x + a * log(x) - _log_gamma(a))
end

function _log_gamma(x::Float64)
    # Lanczos approximation
    if x < 0.5
        return log(π) - log(abs(sin(π*x))) - _log_gamma(1.0 - x)
    end
    x -= 1.0
    g = 7
    c = [0.99999999999980993, 676.5203681218851, -1259.1392167224028,
         771.32342877765313, -176.61502916214059, 12.507343278686905,
         -0.13857109526572012, 9.9843695780195716e-6, 1.5056327351493116e-7]
    t = x + g + 0.5
    sum_c = c[1]
    for i in 2:9
        sum_c += c[i] / (x + i - 1)
    end
    0.5*log(2π) + (x+0.5)*log(t) - t + log(sum_c)
end
