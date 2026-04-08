# src/autocorrelation/morans.jl
# Global Moran's I with analytical and permutation inference.

using Statistics, LinearAlgebra, Random, Distributions

# ──────────────────────────────────────────────────────────────────────────────
# Result type
# ──────────────────────────────────────────────────────────────────────────────

"""
    MoranResult

Container for a Global Moran's I test result.

Fields:
- `I`           — observed statistic
- `expected_I`  — expected value under null (= -1/(n-1))
- `variance`    — variance (analytical or permutation-based)
- `z_score`     — (I - E[I]) / √Var[I]
- `p_value`     — two-tailed p-value
- `alternative` — `:two_tailed`, `:greater`, or `:less`
- `method`      — `:permutation` or `:analytical`
"""
struct MoranResult
    I::Float64
    expected_I::Float64
    variance::Float64
    z_score::Float64
    p_value::Float64
    alternative::Symbol
    method::Symbol
end

function Base.show(io::IO, r::MoranResult)
    println(io, "Moran's I Test")
    println(io, "  I       = $(round(r.I; digits=4))")
    println(io, "  E[I]    = $(round(r.expected_I; digits=4))")
    println(io, "  z-score = $(round(r.z_score; digits=3))")
    print(io,   "  p-value = $(round(r.p_value; digits=4))  [$(r.method)]")
end

# ──────────────────────────────────────────────────────────────────────────────
# Analytical variance (assumption: normality or randomisation)
# ──────────────────────────────────────────────────────────────────────────────

function _moran_analytical_variance(n::Int, W::AbstractMatrix{Float64})
    S0 = sum(W)
    S1 = 0.5 * sum((W[i,j] + W[j,i])^2 for i in 1:n, j in 1:n)
    S2 = sum((sum(W[i,:]) + sum(W[:,i]))^2 for i in 1:n)

    # Under the randomisation assumption (Cliff & Ord 1981)
    E_I  = -1.0 / (n - 1)
    E_I2 = (n^2 * S1 - n * S2 + 3 * S0^2) / ((n^2 - 1) * S0^2)
    max(E_I2 - E_I^2, 1e-15)
end

# ──────────────────────────────────────────────────────────────────────────────
# Core computation
# ──────────────────────────────────────────────────────────────────────────────

function _moran_statistic(values::Vector{Float64},
                           W::AbstractMatrix{Float64})::Float64
    n    = length(values)
    S0   = sum(W)
    xbar = mean(values)
    z    = values .- xbar
    denom = sum(z .^ 2)
    denom == 0.0 && return 0.0
    (n / S0) * dot(z, W * z) / denom
end

# ──────────────────────────────────────────────────────────────────────────────
# Public API
# ──────────────────────────────────────────────────────────────────────────────

"""
    moran(y, w::SpatialWeights;
          method=:permutation, permutations=999,
          alternative=:two_tailed) -> MoranResult

Compute Global Moran's I.

**Methods:**
- `:permutation` — empirical p-value from random permutations (recommended for
  non-normal data, which is typical in health outcomes)
- `:analytical`  — normal-approximation p-value using the randomisation formula
  of Cliff & Ord (1981); faster for large *n*

`alternative` controls the tail for the p-value:
- `:two_tailed` (default), `:greater` (test for positive AC), `:less`
"""
function moran(y::Vector{Float64}, w::SpatialWeights;
               method::Symbol       = :permutation,
               permutations::Int    = 999,
               alternative::Symbol  = :two_tailed)::MoranResult
    n    = length(y)
    W    = Matrix{Float64}(w.W)   # dense for simplicity; sparse path optional
    I_obs = _moran_statistic(y, W)
    E_I   = -1.0 / (n - 1)

    if method == :analytical
        var_I   = _moran_analytical_variance(n, W)
        z_score = (I_obs - E_I) / sqrt(var_I)
        p_value = if alternative == :two_tailed
            2 * (1 - cdf(Normal(), abs(z_score)))
        elseif alternative == :greater
            1 - cdf(Normal(), z_score)
        else
            cdf(Normal(), z_score)
        end
        return MoranResult(I_obs, E_I, var_I, z_score, p_value, alternative, :analytical)

    else  # permutation
        I_perm    = Vector{Float64}(undef, permutations)
        perm_vals = copy(y)
        for k in 1:permutations
            shuffle!(perm_vals)
            I_perm[k] = _moran_statistic(perm_vals, W)
        end
        perm_mean = mean(I_perm)
        perm_std  = std(I_perm)
        z_score   = perm_std > 0 ? (I_obs - perm_mean) / perm_std : 0.0
        p_value   = if alternative == :two_tailed
            mean(abs.(I_perm) .>= abs(I_obs))
        elseif alternative == :greater
            mean(I_perm .>= I_obs)
        else
            mean(I_perm .<= I_obs)
        end
        var_I = perm_std^2
        return MoranResult(I_obs, E_I, var_I, z_score, p_value, alternative, :permutation)
    end
end

"""
    geary(y, w::SpatialWeights; method=:permutation, permutations=999) -> MoranResult

Compute Geary's C statistic.  C = 1 → randomness; C < 1 → clustering; C > 1 → dispersion.
Returns a `MoranResult` with `I` set to the C statistic and `expected_I = 1.0`.
"""
function geary(y::Vector{Float64}, w::SpatialWeights;
               method::Symbol    = :permutation,
               permutations::Int = 999)::MoranResult
    n     = length(y)
    W     = Matrix{Float64}(w.W)
    S0    = sum(W)
    xbar  = mean(y)

    function _c(v)
        num = sum(W[i,j] * (v[i] - v[j])^2 for i in 1:n, j in 1:n)
        (n - 1) * num / (2 * S0 * sum((v .- mean(v)) .^ 2))
    end

    C_obs = _c(y)

    if method == :permutation
        C_perm    = Vector{Float64}(undef, permutations)
        perm_vals = copy(y)
        for k in 1:permutations
            shuffle!(perm_vals)
            C_perm[k] = _c(perm_vals)
        end
        perm_std = std(C_perm)
        z_score  = perm_std > 0 ? (C_obs - 1.0) / perm_std : 0.0
        p_value  = mean(abs.(C_perm .- 1.0) .>= abs(C_obs - 1.0))
        return MoranResult(C_obs, 1.0, perm_std^2, z_score, p_value,
                           :two_tailed, :permutation)
    else
        # Analytical variance (approximation)
        var_C = (2 * S0^2 * (2*S0^2 + n*S0 - n^2)) /
                (S0^2 * (n + 1) * (n - 1)^2)
        var_C = max(var_C, 1e-15)
        z_score = (C_obs - 1.0) / sqrt(var_C)
        p_value = 2 * (1 - cdf(Normal(), abs(z_score)))
        return MoranResult(C_obs, 1.0, var_C, z_score, p_value,
                           :two_tailed, :analytical)
    end
end
