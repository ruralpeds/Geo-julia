# autocorrelation/morans.jl — Global Moran's I and Geary's C

using Statistics
using Random

"""
    MoranResult

Result of a global spatial autocorrelation test.

# Fields
- `I`           : observed statistic (Moran's I or Geary's C)
- `expected_I`  : expected value under null hypothesis
- `variance`    : variance under null
- `z_score`     : standardised score
- `p_value`     : two-tailed (or one-tailed) p-value
- `alternative` : `:two_tailed`, `:greater`, or `:less`
- `method`      : `:permutation` or `:analytical`
- `n_permutations` : number of permutations (0 if analytical)
"""
struct MoranResult
    I              :: Float64
    expected_I     :: Float64
    variance       :: Float64
    z_score        :: Float64
    p_value        :: Float64
    alternative    :: Symbol
    method         :: Symbol
    n_permutations :: Int
end

function Base.show(io::IO, r::MoranResult)
    name = r.expected_I ≈ -1/(r.I == 0 ? 1 : 1) ? "Geary's C" : "Moran's I"
    println(io, "$(name) = $(round(r.I; digits=4))")
    println(io, "  E[I] = $(round(r.expected_I; digits=4))")
    println(io, "  z    = $(round(r.z_score; digits=4))")
    println(io, "  p    = $(round(r.p_value; digits=4)) ($(r.alternative), $(r.method))")
end

# ────────────────────────────────────────────────────────────────────────────

"""
    moran(y, w; method=:permutation, permutations=999, alternative=:two_tailed) -> MoranResult

Compute global Moran's I spatial autocorrelation.

# Methods
- `:permutation` (default): simulates null distribution by shuffling y
- `:analytical` : Cliff & Ord (1981) randomisation assumption

# Arguments
- `y`            : numeric vector of length n
- `w`            : `SpatialWeights`
- `permutations` : number of permutations (ignored for analytical)
- `alternative`  : `:two_tailed`, `:greater`, `:less`
"""
function moran(y::AbstractVector{<:Real},
               w::AbstractSpatialWeights;
               method       :: Symbol = :permutation,
               permutations :: Int    = 999,
               alternative  :: Symbol = :two_tailed)::MoranResult

    n = length(y)
    n == w.n || error("length(y)=$(n) ≠ w.n=$(w.n)")

    z = Float64.(y) .- mean(y)
    S0 = sum(w.W)
    Wz = w.W * z
    I_obs = (n / S0) * dot(z, Wz) / dot(z, z)

    if method == :analytical
        _moran_analytical(I_obs, z, w, n, S0, alternative)
    else
        _moran_permutation(I_obs, z, w, n, S0, permutations, alternative)
    end
end

function _moran_analytical(I_obs, z, w, n, S0, alternative)
    E_I = -1.0 / (n - 1)

    # Cliff-Ord (1981) randomisation variance
    S1 = 0.5 * sum((w.W + w.W') .^ 2)
    S2 = sum((vec(sum(w.W; dims=2)) + vec(sum(w.W; dims=1))) .^ 2)
    S3 = (n * sum(z .^ 4)) / (sum(z .^ 2)^2)
    S4 = (S3 - 1.0) * (n^2 - 3n + 3) * S1 - n * (n-1) * S1/4 + n * (n-1) * S2/4 # simplified term
    # Use the simpler randomisation formula (Anselin 1988, eq. 2.6)
    n2 = Float64(n^2)
    Var_I = ((n2 * S1 - n * S2 + 3 * S0^2) / ((n^2 - 1) * S0^2)) - E_I^2

    z_score = (I_obs - E_I) / sqrt(max(Var_I, 1e-15))
    p = _z_to_p(z_score, alternative)

    MoranResult(I_obs, E_I, Var_I, z_score, p, alternative, :analytical, 0)
end

function _moran_permutation(I_obs, z, w, n, S0, permutations, alternative)
    E_I = -1.0 / (n - 1)

    perm_I = Vector{Float64}(undef, permutations)
    z_perm = copy(z)
    denom  = dot(z, z)
    for p in 1:permutations
        shuffle!(z_perm)
        Wz_p = w.W * z_perm
        perm_I[p] = (n / S0) * dot(z_perm, Wz_p) / denom
    end

    Var_I   = var(perm_I; corrected=true)
    z_score = (I_obs - mean(perm_I)) / sqrt(max(Var_I, 1e-15))
    p = _perm_p(I_obs, perm_I, alternative)

    MoranResult(I_obs, E_I, Var_I, z_score, p, alternative, :permutation, permutations)
end

# ────────────────────────────────────────────────────────────────────────────

"""
    geary(y, w; method=:permutation, permutations=999, alternative=:two_tailed) -> MoranResult

Compute global Geary's C statistic. Returns a `MoranResult` with `I` = Geary's C.
C ≈ 1 → no autocorrelation, C < 1 → positive, C > 1 → negative autocorrelation.
"""
function geary(y::AbstractVector{<:Real},
               w::AbstractSpatialWeights;
               method       :: Symbol = :permutation,
               permutations :: Int    = 999,
               alternative  :: Symbol = :two_tailed)::MoranResult

    n = length(y)
    z = Float64.(y)
    S0 = sum(w.W)
    SS  = sum((z .- mean(z)).^2)

    # Geary's C = ((n-1) / (2*S0)) * sum_ij w_ij (z_i - z_j)^2 / SS
    rows, cols, vals = findnz(w.W)
    cross = sum(vals[k] * (z[rows[k]] - z[cols[k]])^2 for k in eachindex(vals))
    C_obs = ((n - 1) / (2 * S0)) * cross / SS

    E_C = 1.0

    if method == :permutation
        perm_C = Vector{Float64}(undef, permutations)
        z_p = copy(z)
        for p in 1:permutations
            shuffle!(z_p)
            cross_p = sum(vals[k] * (z_p[rows[k]] - z_p[cols[k]])^2 for k in eachindex(vals))
            SS_p = sum((z_p .- mean(z_p)).^2)
            perm_C[p] = ((n - 1) / (2 * S0)) * cross_p / max(SS_p, 1e-15)
        end
        Var_C   = var(perm_C; corrected=true)
        z_score = (C_obs - mean(perm_C)) / sqrt(max(Var_C, 1e-15))
        p       = _perm_p(C_obs, perm_C, alternative)
        return MoranResult(C_obs, E_C, Var_C, z_score, p, alternative, :permutation, permutations)
    else
        # Analytical variance (Cliff-Ord, simplified)
        Var_C = 1.0 / (2.0 * n)  # rough approximation
        z_score = (C_obs - E_C) / sqrt(Var_C)
        p = _z_to_p(z_score, alternative)
        return MoranResult(C_obs, E_C, Var_C, z_score, p, alternative, :analytical, 0)
    end
end

# ────────────────────────────────────────────────────────────────────────────
# Helpers
# ────────────────────────────────────────────────────────────────────────────

function _perm_p(obs, perms, alternative)
    n = length(perms) + 1
    if alternative == :greater
        return (count(>=(obs), perms) + 1) / n
    elseif alternative == :less
        return (count(<=(obs), perms) + 1) / n
    else  # two_tailed
        extreme = count(>=(abs(obs - mean(perms))), abs.(perms .- mean(perms)))
        return (extreme + 1) / n
    end
end

function _z_to_p(z, alternative)
    # Normal CDF approximation (Abramowitz & Stegun 26.2.17)
    t = 1.0 / (1.0 + 0.2316419 * abs(z))
    d = 0.3989423 * exp(-0.5 * z^2)
    p = d * t * @evalpoly(t, 1.330274429, -1.821255978, 1.781477937, -0.356563782, 0.319381530)
    p = max(p, 0.0)
    if alternative == :greater
        return z >= 0 ? p : 1.0 - p
    elseif alternative == :less
        return z <= 0 ? p : 1.0 - p
    else
        return 2.0 * min(p, 1.0 - p)
    end
end
