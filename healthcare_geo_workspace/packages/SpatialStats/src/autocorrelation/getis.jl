# src/autocorrelation/getis.jl
# Getis-Ord G* hotspot analysis.

using Statistics, LinearAlgebra, Random, Distributions

"""
    getis_ord(y, w::SpatialWeights; star=true, permutations=999)
        -> NamedTuple{(:z_scores, :p_values)}

Compute Getis-Ord G* (star=true, default) or G (star=false) hotspot statistics.

**G*** includes the focal unit *i* itself in its calculation (self-weight = 1),
which is the standard for hotspot analysis.  **G** excludes the focal unit.

Returns z-scores (positive = hot spot, negative = cold spot) and two-tailed
permutation p-values for each spatial unit.
"""
function getis_ord(y::Vector{Float64}, w::SpatialWeights;
                   star::Bool        = true,
                   permutations::Int = 999)
    n    = length(y)
    W    = Matrix{Float64}(w.W)

    # G*: add self-weight (diagonal = 1), then re-standardise
    if star
        W_g = W + I(n)
        # Normalise each row by its sum (G* uses raw counts scaled by sum)
    else
        W_g = copy(W)
    end

    xbar = mean(y)
    s    = std(y; corrected = true)

    z_scores = Vector{Float64}(undef, n)
    for i in 1:n
        wi     = W_g[i, :]
        S_wi   = sum(wi)
        S_wi2  = sum(wi .^ 2)
        num    = dot(wi, y) - xbar * S_wi
        denom  = s > 0 ? s * sqrt((n * S_wi2 - S_wi^2) / (n - 1)) : 0.0
        z_scores[i] = denom > 0 ? num / denom : 0.0
    end

    # Permutation p-values
    p_values  = ones(Float64, n)
    perm_z    = Matrix{Float64}(undef, n, permutations)
    perm_vals = copy(y)
    for k in 1:permutations
        shuffle!(perm_vals)
        xbar_p = mean(perm_vals)
        s_p    = std(perm_vals; corrected = true)
        for i in 1:n
            wi     = W_g[i, :]
            S_wi   = sum(wi)
            S_wi2  = sum(wi .^ 2)
            num    = dot(wi, perm_vals) - xbar_p * S_wi
            denom  = s_p > 0 ? s_p * sqrt((n * S_wi2 - S_wi^2) / (n - 1)) : 0.0
            perm_z[i, k] = denom > 0 ? num / denom : 0.0
        end
    end

    for i in 1:n
        p_values[i] = mean(abs.(perm_z[i, :]) .>= abs(z_scores[i]))
    end

    return (z_scores = z_scores, p_values = p_values)
end

"""
    g_local(y, w::SpatialWeights; permutations=999) -> NamedTuple

Alias for `getis_ord(y, w; star=true, permutations=permutations)`.
"""
g_local(y, w; permutations=999) = getis_ord(y, w; star=true, permutations=permutations)
