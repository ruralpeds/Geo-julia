# panel.jl — Panel data utilities for county × year health analysis
# Chapter 37.5

"""
    panel_summary(df, id_col, time_col, value_col) -> DataFrame

Summarise a panel dataset by unit (county):
  - mean, std, min, max over time
  - trend coefficient (OLS slope)
  - first-order autocorrelation
"""
function panel_summary(df       ::DataFrame,
                       id_col   ::Symbol,
                       time_col ::Symbol,
                       value_col::Symbol)::DataFrame
    ids  = unique(df[!, id_col])
    rows = map(ids) do id
        sub   = filter(r -> r[id_col] == id, df)
        y     = Float64.(sub[!, value_col])
        n     = length(y)
        t_idx = collect(1.0:n)
        trend = n >= 2 ? _ols_slope(t_idx, y) : NaN
        ac1   = n >= 3 ? cor(y[1:end-1], y[2:end]) : NaN
        (id=id, n=n, mean=mean(y), std=std(y; corrected=true),
         min=minimum(y), max=maximum(y), trend=trend, ac1=ac1)
    end
    DataFrame(rows)
end

function _ols_slope(x, y)
    n  = length(x)
    x̄  = mean(x); ȳ = mean(y)
    sx  = sum((x .- x̄).^2)
    sx < 1e-12 && return 0.0
    sum((x .- x̄) .* (y .- ȳ)) / sx
end

"""
    panel_detrend(df, id_col, time_col, value_col) -> DataFrame

Within-unit linear detrending (remove county-specific trends).
Adds column `<value_col>_detrended` to a copy of df.
"""
function panel_detrend(df       ::DataFrame,
                       id_col   ::Symbol,
                       time_col ::Symbol,
                       value_col::Symbol)::DataFrame
    out = copy(df)
    out[!, Symbol(String(value_col) * "_detrended")] = zeros(nrow(df))
    for id in unique(df[!, id_col])
        mask = df[!, id_col] .== id
        y    = Float64.(df[mask, value_col])
        n    = length(y); t_idx = collect(1.0:n)
        if n >= 2
            slope  = _ols_slope(t_idx, y)
            interc = mean(y) - slope * mean(t_idx)
            fitted = @. interc + slope * t_idx
            out[mask, Symbol(String(value_col) * "_detrended")] .= y .- fitted
        else
            out[mask, Symbol(String(value_col) * "_detrended")] .= y
        end
    end
    out
end

"""
    panel_fe(df, id_col, time_col, value_col, covariate_cols) -> NamedTuple

Two-way fixed effects panel regression (within estimator).
Removes unit FE (county means) and time FE (year means).

Returns: β (covariate coefficients), se, t_stats, within_R²
"""
function panel_fe(df            ::DataFrame,
                  id_col        ::Symbol,
                  time_col      ::Symbol,
                  value_col     ::Symbol,
                  covariate_cols::Vector{Symbol})::NamedTuple
    n_obs = nrow(df)
    ids   = df[!, id_col]
    times = df[!, time_col]
    y     = Float64.(df[!, value_col])

    # Unit demeaning
    uid = unique(ids)
    for id in uid
        mask = ids .== id
        y[mask] .-= mean(y[mask])
    end

    # Build demeaned X
    X_raw = hcat([Float64.(df[!, c]) for c in covariate_cols]...)
    X_dm  = copy(X_raw)
    for id in uid
        mask = ids .== id
        for j in 1:size(X_dm, 2)
            X_dm[mask, j] .-= mean(X_dm[mask, j])
        end
    end

    # OLS on demeaned data
    β_hat  = (X_dm'X_dm + 1e-9I) \ (X_dm'y)
    resid  = y .- X_dm * β_hat
    σ²     = sum(resid.^2) / max(n_obs - length(β_hat) - length(uid), 1)
    Vβ     = σ² * pinv(X_dm'X_dm)
    se     = sqrt.(max.(diag(Vβ), 0.0))
    t_stat = β_hat ./ max.(se, 1e-12)

    ss_res = sum(resid.^2)
    ss_tot = sum(y.^2)  # already demeaned
    r2     = 1.0 - ss_res / max(ss_tot, 1e-12)

    (β=β_hat, se=se, t_stat=t_stat, within_R2=r2,
     covariate_names=[String(c) for c in covariate_cols])
end

using LinearAlgebra: I, pinv, diag
