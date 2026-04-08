# src/analysis/autocorrelation.jl
# Spatial autocorrelation statistics: Moran's I, Geary's C, LISA, Getis-Ord G*.

using Statistics, LinearAlgebra, Random

"""
    compute_morans_i(values, W; permutations=999)
        -> NamedTuple{(:I, :expected_I, :variance, :z_score, :p_value)}

Compute Global Moran's I with permutation-based inference.

`W` should be row-standardised (rows sum to 1).
The p-value is two-tailed from the permutation distribution.
"""
function compute_morans_i(values::Vector{Float64}, W::Matrix{Float64};
                           permutations::Int = 999)
    n = length(values)
    @assert size(W) == (n, n) "W must be n×n"

    # Ensure row-standardisation
    W_std = W ./ (sum(W; dims = 2) .+ 1e-12)

    x_bar       = mean(values)
    z           = values .- x_bar
    denominator = sum(z .^ 2)

    if denominator == 0.0
        exp_I = -1.0 / (n - 1)
        return (I = 0.0, expected_I = exp_I, variance = 0.0,
                z_score = 0.0, p_value = 1.0)
    end

    S0   = sum(W_std)
    Wz   = W_std * z
    I_obs = (n / S0) * dot(z, Wz) / denominator

    # Permutation test
    I_perm    = Vector{Float64}(undef, permutations)
    perm_vals = copy(values)
    for k in 1:permutations
        shuffle!(perm_vals)
        zp  = perm_vals .- mean(perm_vals)
        dp  = sum(zp .^ 2)
        I_perm[k] = dp > 0 ? (n / S0) * dot(zp, W_std * zp) / dp : 0.0
    end

    perm_mean = mean(I_perm)
    perm_std  = std(I_perm)
    z_score   = perm_std > 0 ? (I_obs - perm_mean) / perm_std : 0.0
    p_value   = mean(abs.(I_perm) .>= abs(I_obs))
    exp_I     = -1.0 / (n - 1)

    return (I = I_obs, expected_I = exp_I,
            variance = perm_std^2, z_score = z_score, p_value = p_value)
end

"""
    compute_geary_c(values, W; permutations=999)
        -> NamedTuple{(:C, :expected_C, :variance, :z_score, :p_value)}

Compute Geary's C statistic with permutation-based inference.
C = 1 → spatial randomness; C < 1 → positive clustering; C > 1 → dispersion.
"""
function compute_geary_c(values::Vector{Float64}, W::Matrix{Float64};
                          permutations::Int = 999)
    n = length(values)
    @assert size(W) == (n, n) "W must be n×n"

    W_std = W ./ (sum(W; dims = 2) .+ 1e-12)
    S0    = sum(W_std)
    x_bar = mean(values)
    denom = sum((values .- x_bar) .^ 2)

    function _geary(v)
        num = sum(W_std[i, j] * (v[i] - v[j])^2
                  for i in 1:n, j in 1:n)
        return (n - 1) * num / (2 * S0 * sum((v .- mean(v)) .^ 2))
    end

    C_obs = _geary(values)

    C_perm    = Vector{Float64}(undef, permutations)
    perm_vals = copy(values)
    for k in 1:permutations
        shuffle!(perm_vals)
        C_perm[k] = _geary(perm_vals)
    end

    perm_mean = mean(C_perm)
    perm_std  = std(C_perm)
    z_score   = perm_std > 0 ? (C_obs - perm_mean) / perm_std : 0.0
    p_value   = mean(abs.(C_perm .- 1.0) .>= abs(C_obs - 1.0))

    return (C = C_obs, expected_C = 1.0,
            variance = perm_std^2, z_score = z_score, p_value = p_value)
end

"""
    lisa_clusters(values, W; permutations=999, alpha=0.05) -> Vector{String}

Compute Local Indicators of Spatial Association (LISA) cluster categories.

Returns a `Vector{String}` with one label per observation:
- `"HH"` — high-high cluster (hot spot)
- `"LL"` — low-low cluster (cold spot)
- `"HL"` — high-low outlier
- `"LH"` — low-high outlier
- `"NS"` — not significant

`W` must be row-standardised.  `alpha` is the significance threshold.
"""
function lisa_clusters(values::Vector{Float64}, W::Matrix{Float64};
                        permutations::Int = 999,
                        alpha::Float64 = 0.05)::Vector{String}
    n     = length(values)
    x_bar = mean(values)
    z     = values .- x_bar
    s2    = sum(z .^ 2) / n

    Wz      = W * z
    I_local = s2 > 0 ? (z ./ s2) .* Wz : zeros(n)

    # Permutation test per location
    p_values  = ones(Float64, n)
    perm_z    = copy(z)
    for i in 1:n
        perm_I = Vector{Float64}(undef, permutations)
        for k in 1:permutations
            shuffle!(perm_z)
            perm_I[k] = s2 > 0 ? (z[i] / s2) * dot(W[i, :], perm_z) : 0.0
        end
        p_values[i] = mean(abs.(perm_I) .>= abs(I_local[i]))
        copy!(perm_z, z)  # restore
    end

    result = fill("NS", n)
    for i in 1:n
        p_values[i] < alpha || continue
        hi_val  = values[i] >= x_bar
        lag_hi  = dot(W[i, :], values) >= x_bar
        result[i] = if hi_val && lag_hi
            "HH"
        elseif !hi_val && !lag_hi
            "LL"
        elseif hi_val && !lag_hi
            "HL"
        else
            "LH"
        end
    end

    return result
end

"""
    getis_ord_g(values, W; permutations=999) -> Vector{Float64}

Compute Getis-Ord G* hotspot z-scores for each location.

Positive z-scores indicate statistically significant hot spots (clusters of
high values); negative z-scores indicate cold spots (clusters of low values).
`W` must be a binary (0/1) weights matrix including the self-weight diagonal
set to 1 (as required by the G* statistic).
"""
function getis_ord_g(values::Vector{Float64}, W::Matrix{Float64};
                      permutations::Int = 999)::Vector{Float64}
    n    = length(values)
    xbar = mean(values)
    s    = std(values; corrected = true)

    z_scores = Vector{Float64}(undef, n)

    for i in 1:n
        wi      = W[i, :]
        sum_wij = sum(wi)
        num     = dot(wi, values) - xbar * sum_wij
        denom_inner = (n * sum(wi .^ 2) - sum_wij^2) / (n - 1)
        denom   = s * sqrt(denom_inner)
        z_scores[i] = denom > 0 ? num / denom : 0.0
    end

    return z_scores
end
