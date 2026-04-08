# iv.jl — Instrumental Variables / 2SLS for healthcare access endogeneity
# Chapter 43.3
#
# Classic IV setup for healthcare access:
#   Outcome Y = healthcare utilisation / mortality
#   Endogenous regressor D = access score (endogenous: sicker people seek more care)
#   Instrument Z = geographic distance to nearest hospital
#     (affects access but not utilisation directly — exclusion restriction)
#
# 2SLS:
#   First stage:  D̂ = Π₀ + Π₁Z + Xγ
#   Second stage: Y  = β₀ + β₁D̂ + Xδ + ε
#   IV estimator: β₁ = Cov(Z, Y) / Cov(Z, D)

"""
    IVResult

Result of an IV / 2SLS regression.
"""
struct IVResult
    β_iv       ::Vector{Float64}  # 2SLS coefficients [intercept, D, X₁,...,Xₖ]
    se_iv      ::Vector{Float64}  # heteroskedasticity-robust SEs
    t_stats    ::Vector{Float64}
    p_values   ::Vector{Float64}
    first_stage_F::Float64        # first stage F-statistic (Staiger-Stock: F > 10 = strong)
    hausman_p  ::Float64          # Hausman endogeneity test p-value
    sargan_p   ::Float64          # Sargan overidentification test (NaN if just-identified)
    n          ::Int
    coef_names ::Vector{String}
end

"""
    iv_2sls(df; outcome_col, endog_col, instrument_cols, exog_cols) -> IVResult

Two-Stage Least Squares estimation.

# Arguments
- `outcome_col`    : dependent variable Y
- `endog_col`      : endogenous regressor D
- `instrument_cols`: instruments Z₁,...,Zₗ (l ≥ 1)
- `exog_cols`      : included exogenous controls X₁,...,Xₖ

# First stage: D = Π₀ + Z·π_Z + X·π_X + v
# Second stage: Y = β₀ + D̂·β_D + X·β_X + ε
#
# Inference: robust SEs from sandwich estimator Avar(β̂_IV) = (X̃'PZ X̃)⁻¹ (X̃'PZ Ω PZ X̃) (X̃'PZ X̃)⁻¹
# where X̃ = [1, D, X], PZ = Z(Z'Z)⁻¹Z' projects onto instrument space
"""
function iv_2sls(df             ::DataFrame;
                 outcome_col    ::Symbol,
                 endog_col      ::Symbol,
                 instrument_cols::Vector{Symbol},
                 exog_cols      ::Vector{Symbol} = Symbol[])

    n = nrow(df)
    y = Float64.(df[!, outcome_col])
    D = Float64.(df[!, endog_col])
    Z = hcat(ones(n), [Float64.(df[!, c]) for c in instrument_cols]...,
                      [Float64.(df[!, c]) for c in exog_cols]...)
    X = hcat(ones(n), D, [Float64.(df[!, c]) for c in exog_cols]...)
    n_z   = length(instrument_cols)
    n_x   = length(exog_cols)
    n_end = 1  # one endogenous variable

    # ── First stage ────────────────────────────────────────────────────────
    π_hat  = (Z'Z + 1e-10I) \ (Z'D)
    D_hat  = Z * π_hat
    v_hat  = D .- D_hat
    D_hat_x = hcat(ones(n), D_hat, [Float64.(df[!, c]) for c in exog_cols]...)

    # First stage F (Staiger-Stock weak instrument test)
    # F = (RSS_restricted - RSS_unrestricted) / n_z / (RSS_unrestricted / (n-k))
    k_fs = size(Z, 2)
    ê_fs = D .- D_hat
    σ²_fs = sum(ê_fs.^2) / (n - k_fs)
    # Restricted model: only exog vars
    Z_r   = hcat(ones(n), [Float64.(df[!, c]) for c in exog_cols]...)
    π_r   = (Z_r'Z_r + 1e-10I) \ (Z_r'D)
    ê_r   = D .- Z_r * π_r
    F_stat = (sum(ê_r.^2) - sum(ê_fs.^2)) / n_z / max(σ²_fs, 1e-12)

    # ── Second stage ───────────────────────────────────────────────────────
    β_2sls = (D_hat_x'D_hat_x + 1e-10I) \ (D_hat_x'y)
    ê_2sls = y .- X * β_2sls  # residuals from structural equation

    # Robust SE: sandwich with structural residuals
    meat   = D_hat_x' * diagm(ê_2sls.^2) * D_hat_x
    bread  = inv(D_hat_x'D_hat_x + 1e-10I)
    V_iv   = bread * meat * bread
    se_iv  = sqrt.(max.(diag(V_iv), 0.0))
    t_iv   = β_2sls ./ max.(se_iv, 1e-12)
    p_iv   = 2 .* ccdf.(Normal(), abs.(t_iv))

    # ── Hausman endogeneity test ────────────────────────────────────────────
    # Wu-Hausman: augment second stage with first-stage residuals v̂
    # If β_OLS ≈ β_IV: D is exogenous (H₀)
    X_haus   = hcat(X, v_hat)
    β_haus   = (X_haus'X_haus + 1e-10I) \ (X_haus'y)
    ê_haus   = y .- X_haus * β_haus
    σ²_h     = sum(ê_haus.^2) / max(n - size(X_haus,2), 1)
    V_haus   = σ²_h * inv(X_haus'X_haus + 1e-10I)
    t_haus   = β_haus[end] / max(sqrt(V_haus[end,end]), 1e-12)
    hausman_p = 2 * ccdf(Normal(), abs(t_haus))

    # ── Sargan overidentification test ─────────────────────────────────────
    # Only defined when n_z > n_end (overidentified)
    sargan_p = NaN
    if n_z > n_end
        Z_ex   = Z[:, 2:n_z+1]  # just the instruments
        ê_on_Z = Z_ex * (Z_ex'Z_ex \ (Z_ex'ê_2sls))
        J      = n * sum(ê_on_Z.^2) / sum(ê_2sls.^2)
        sargan_p = ccdf(Chisq(n_z - n_end), J)
    end

    coef_names = vcat(["intercept"], [String(endog_col)],
                      [String(c) for c in exog_cols])

    IVResult(β_2sls, se_iv, t_iv, p_iv, F_stat, hausman_p, sargan_p,
             n, coef_names)
end

"""
    first_stage_f(result) -> NamedTuple

Interpret first-stage F-statistic for instrument strength.
Rule of thumb: F < 10 → weak instruments (Staiger & Stock 1997).
"""
function first_stage_f(r::IVResult)
    strength = r.first_stage_F >= 10 ? "strong" :
               r.first_stage_F >= 5  ? "weak"   : "very weak"
    (F=r.first_stage_F, strength=strength, staiger_stock_threshold=10.0)
end

"""
    hausman_test(result) -> NamedTuple

Interpret Hausman endogeneity test result.
H₀: OLS is consistent (D is exogenous).
p < 0.05 → reject exogeneity, IV preferred.
"""
function hausman_test(r::IVResult)
    conclusion = r.hausman_p < 0.05 ? "reject_exogeneity" : "fail_to_reject"
    (p_value=r.hausman_p, conclusion=conclusion,
     recommendation=conclusion == "reject_exogeneity" ?
         "Use IV/2SLS; D is endogenous" : "OLS may be consistent")
end

using LinearAlgebra: diagm, diag, I
using Distributions: Normal, Chisq, ccdf
