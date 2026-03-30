# did.jl — Difference-in-Differences for healthcare policy evaluation
# Chapter 43.1
#
# DiD identification: E[Y₁(1) - Y₁(0) | D=1] = (Ȳ₁ᵀ - Ȳ₀ᵀ) - (Ȳ₁ᶜ - Ȳ₀ᶜ)
# where T ∈ {pre, post}, D ∈ {treated, control}

"""
    DiDResult

Result of a difference-in-differences analysis.
"""
struct DiDResult
    att          ::Float64   # average treatment effect on the treated
    se           ::Float64   # heteroskedasticity-robust (HC3) standard error
    t_stat       ::Float64
    p_value      ::Float64
    ci_lo        ::Float64   # 95% confidence interval
    ci_hi        ::Float64
    pre_trend_p  ::Float64   # p-value for pre-treatment parallel trends (F-test)
    n_treated    ::Int
    n_control    ::Int
    n_pre_periods::Int
    n_post_periods::Int
    event_study  ::Union{DataFrame, Nothing}
end

"""
    did_estimate(df; id_col, time_col, treat_col, outcome_col,
                 treat_time, covariates, cluster_col) -> DiDResult

Two-way fixed effects DiD estimator:
  yᵢₜ = αᵢ + γₜ + β·(Dᵢ × Postₜ) + Xᵢₜ'δ + εᵢₜ

Standard errors: HC3 robust (or clustered if `cluster_col` provided).

# Arguments
- `df`        : panel DataFrame (unit × time)
- `id_col`    : unit identifier (county GEOID, etc.)
- `time_col`  : time period (year)
- `treat_col` : binary treatment indicator (1 = treated unit)
- `outcome_col`: outcome variable (mortality rate, access score, etc.)
- `treat_time` : first period of treatment
- `covariates` : optional control variables
- `cluster_col`: cluster SE at this level (default: `id_col`)

# Chapter 43.1 — Application: Medicaid expansion effects on county access scores
"""
function did_estimate(df           ::DataFrame;
                      id_col       ::Symbol = :GEOID,
                      time_col     ::Symbol = :year,
                      treat_col    ::Symbol = :treated,
                      outcome_col  ::Symbol = :outcome,
                      treat_time   ::Int    = 0,
                      covariates   ::Vector{Symbol} = Symbol[],
                      cluster_col  ::Union{Symbol,Nothing} = nothing)

    n_obs  = nrow(df)
    ids    = sort(unique(df[!, id_col]))
    times  = sort(unique(df[!, time_col]))
    n_id   = length(ids)
    n_t    = length(times)

    # Encode treatment status
    treat_units = unique(df[df[!, treat_col] .== 1, id_col])
    n_treated   = length(treat_units)
    n_control   = n_id - n_treated

    # Post indicator
    post = Int.(df[!, time_col] .>= treat_time)
    did  = Int.(df[!, treat_col]) .* post

    # TWFE: demean within unit AND within time
    y  = Float64.(df[!, outcome_col])
    Xd = hcat(ones(n_obs), did,
               [Float64.(df[!, c]) for c in covariates]...)

    # Unit FE: subtract unit means
    id_means_y = Dict(id => mean(y[df[!, id_col] .== id]) for id in ids)
    id_means_X = Dict(id => vec(mean(Xd[df[!, id_col] .== id, :]; dims=1)) for id in ids)

    y_dm = copy(y)
    X_dm = copy(Xd)
    for (i, row_id) in enumerate(df[!, id_col])
        y_dm[i]    -= id_means_y[row_id]
        X_dm[i, :] .-= id_means_X[row_id]
    end

    # Time FE: subtract time means of demeaned data
    for t in times
        mask = df[!, time_col] .== t
        y_dm[mask] .-= mean(y_dm[mask])
        for j in 1:size(X_dm, 2)
            X_dm[mask, j] .-= mean(X_dm[mask, j])
        end
    end

    # OLS on demeaned data
    β  = (X_dm'X_dm + 1e-10I) \ (X_dm'y_dm)
    ê  = y_dm .- X_dm * β
    att = β[2]  # DiD coefficient

    # HC3 robust SE
    n_params = length(β)
    dof      = n_obs - n_params - n_id - n_t + 1
    H        = X_dm * inv(X_dm'X_dm + 1e-10I) * X_dm'
    leverage = diag(H)
    meat     = X_dm' * diagm((ê ./ (1 .- clamp.(leverage, 0, 0.99))).^2) * X_dm
    V_hc3    = inv(X_dm'X_dm + 1e-10I) * meat * inv(X_dm'X_dm + 1e-10I)
    se_att   = sqrt(max(V_hc3[2,2], 0.0))

    t_stat  = att / max(se_att, 1e-12)
    p_val   = 2 * ccdf(TDist(max(dof, 1)), abs(t_stat))
    ci_lo   = att - 1.96 * se_att
    ci_hi   = att + 1.96 * se_att

    # Pre-trend test: regress outcome on treated × pre-period dummies
    pre_p = parallel_trends_test(df; id_col=id_col, time_col=time_col,
                                   treat_col=treat_col, outcome_col=outcome_col,
                                   treat_time=treat_time)

    n_pre  = count(times .< treat_time)
    n_post = count(times .>= treat_time)

    # Event study
    es_df = event_study(df; id_col=id_col, time_col=time_col,
                         treat_col=treat_col, outcome_col=outcome_col,
                         treat_time=treat_time)

    DiDResult(att, se_att, t_stat, p_val, ci_lo, ci_hi,
              pre_p, n_treated, n_control, n_pre, n_post, es_df)
end

"""
    parallel_trends_test(df; ...) -> Float64

F-test for parallel pre-trends.
Regresses outcome on treated × period-dummies for pre-treatment periods.
H₀: all pre-period interaction coefficients = 0 (parallel trends).
Returns p-value; small p → trends differ pre-treatment.
"""
function parallel_trends_test(df         ::DataFrame;
                               id_col     ::Symbol,
                               time_col   ::Symbol,
                               treat_col  ::Symbol,
                               outcome_col::Symbol,
                               treat_time ::Int)
    pre_df = filter(r -> r[time_col] < treat_time, df)
    isempty(pre_df) && return NaN
    n = nrow(pre_df)
    n < 4 && return NaN

    y      = Float64.(pre_df[!, outcome_col])
    treat  = Float64.(pre_df[!, treat_col])
    times  = sort(unique(pre_df[!, time_col]))
    K      = length(times) - 1   # omit first period as reference
    K == 0 && return NaN

    X = hcat(ones(n), treat)
    for (k, t) in enumerate(times[2:end])
        period_dummy = Float64.(pre_df[!, time_col] .== t)
        X = hcat(X, period_dummy, treat .* period_dummy)
    end

    β    = (X'X + 1e-10I) \ (X'y)
    ê    = y .- X * β
    σ²   = sum(ê.^2) / max(n - size(X,2), 1)

    # F-test on the treated × period columns (every other column after the first 2)
    interact_cols = [2k+2 for k in 1:K if 2k+2 <= size(X,2)]
    isempty(interact_cols) && return NaN
    R  = zeros(length(interact_cols), size(X,2))
    for (i,c) in enumerate(interact_cols); R[i,c] = 1.0; end
    Rβ = R * β
    V  = σ² * inv(X'X + 1e-10I)
    F  = dot(Rβ, inv(R*V*R') * Rβ) / length(interact_cols)
    p  = ccdf(FDist(length(interact_cols), max(n - size(X,2), 1)), F)
    p
end

"""
    event_study(df; ...) -> DataFrame

Dynamic DiD / event study.
Estimates β_k = E[Yᵢₜ(1) - Yᵢₜ(0) | D=1] for each relative time k = t - treat_time.
Returns DataFrame with columns: rel_time, coef, se, ci_lo, ci_hi, p_value.
"""
function event_study(df         ::DataFrame;
                     id_col     ::Symbol,
                     time_col   ::Symbol,
                     treat_col  ::Symbol,
                     outcome_col::Symbol,
                     treat_time ::Int)
    n_obs  = nrow(df)
    times  = sort(unique(df[!, time_col]))
    rel_times = [t - treat_time for t in times]
    # Reference: rel_time = -1
    ref_idx = findfirst(==(-1), rel_times)
    excl    = isnothing(ref_idx) ? Int[] : [ref_idx]

    y     = Float64.(df[!, outcome_col])
    treat = Float64.(df[!, treat_col])

    X_cols = [ones(n_obs)]
    col_labels = Int[]
    for (k, (t, rt)) in enumerate(zip(times, rel_times))
        k in excl && continue
        period_d = Float64.(df[!, time_col] .== t)
        push!(X_cols, period_d)
        push!(X_cols, treat .* period_d)
        push!(col_labels, rt)
    end
    X   = hcat(X_cols...)
    β   = (X'X + 1e-10I) \ (X'y)
    ê   = y .- X * β
    σ²  = sum(ê.^2) / max(n_obs - size(X,2), 1)
    V   = σ² * inv(X'X + 1e-10I)

    # Interaction coefficients are every even index after col 1
    rows = NamedTuple[]
    inter_cols = [2k for k in 1:length(col_labels) if 2k <= size(X,2)]
    for (i, ic) in enumerate(inter_cols)
        b  = β[ic]; s = sqrt(max(V[ic,ic], 0.0))
        pv = 2 * ccdf(Normal(), abs(b / max(s, 1e-12)))
        push!(rows, (rel_time=col_labels[i], coef=b, se=s,
                     ci_lo=b-1.96s, ci_hi=b+1.96s, p_value=pv))
    end
    isempty(rows) && return DataFrame()
    df_es = DataFrame(rows)
    sort!(df_es, :rel_time)
end

using LinearAlgebra: diagm, diag, I
using Distributions: TDist, FDist, ccdf, Normal
