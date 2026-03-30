# autocorrelation/getis.jl — Getis-Ord G and G* statistics

using Statistics
using Random

"""
    GetisOrdResult

Result of Getis-Ord local G or G* statistic.

# Fields
- `z_scores`  : standardised z-scores for each observation
- `p_values`  : two-tailed pseudo p-values
- `star`      : true if G* (includes self-weight), false if G
- `n`         : number of observations
"""
struct GetisOrdResult
    z_scores :: Vector{Float64}
    p_values :: Vector{Float64}
    star     :: Bool
    n        :: Int
end

function Base.show(io::IO, r::GetisOrdResult)
    name = r.star ? "G*" : "G"
    sig = count(<(0.05), r.p_values)
    println(io, "GetisOrdResult $(name)(n=$(r.n))")
    println(io, "  significant (p<0.05): $(sig)")
    println(io, "  hot spots (z>1.96):   $(count(>(1.96), r.z_scores))")
    println(io, "  cold spots (z<-1.96): $(count(<(-1.96), r.z_scores))")
end

# ────────────────────────────────────────────────────────────────────────────

"""
    getis_ord(y, w; star=true, permutations=999) -> GetisOrdResult

Compute Getis-Ord local G (or G*) hot-spot statistics.

G* includes self-weight (diagonal = 1). G excludes self.
Returns z-scores: positive = spatial clustering of high values (hot spot),
negative = clustering of low values (cold spot).

# Arguments
- `y`            : numeric vector, length n
- `w`            : `SpatialWeights`
- `star`         : if true (default), compute G* (include self)
- `permutations` : permutations for pseudo p-values
"""
function getis_ord(y::AbstractVector{<:Real},
                   w::AbstractSpatialWeights;
                   star         :: Bool = true,
                   permutations :: Int  = 999)::GetisOrdResult

    n = length(y)
    n == w.n || error("length(y)=$(n) ≠ w.n=$(w.n)")
    x = Float64.(y)

    W_use = if star
        # Add self-weight (diagonal = 1) to a copy
        W_star = copy(w.W)
        for i in 1:n
            W_star[i, i] = 1.0
        end
        dropzeros!(W_star)
        W_star
    else
        w.W
    end

    x_bar  = mean(x)
    s      = std(x; corrected=false)

    z_scores = Vector{Float64}(undef, n)
    p_values = Vector{Float64}(undef, n)

    for i in 1:n
        wi = W_use[i, :]
        wi_vals = nonzeros(wi)
        wi_idx  = SparseArrays.findnz(wi)[1]
        n_i = length(wi_vals)
        W_i_sum = sum(wi_vals)

        num = dot(wi_vals, x[wi_idx]) - x_bar * W_i_sum
        denom_factor = star ? n : n - 1
        denom = s * sqrt((n * sum(wi_vals .^ 2) - W_i_sum^2) / (denom_factor - (star ? 0 : 0)))

        # Simplified: use permutation approach for p-values
        # z-score from formula
        z_scores[i] = abs(denom) < 1e-15 ? 0.0 : num / denom
    end

    # Permutation p-values
    x_perm = copy(x)
    perm_z = Matrix{Float64}(undef, n, permutations)

    for p in 1:permutations
        shuffle!(x_perm)
        x_bar_p = mean(x_perm)
        s_p     = std(x_perm; corrected=false)
        for i in 1:n
            wi = W_use[i, :]
            wi_vals = nonzeros(wi)
            wi_idx  = SparseArrays.findnz(wi)[1]
            W_i_sum = sum(wi_vals)
            num_p   = dot(wi_vals, x_perm[wi_idx]) - x_bar_p * W_i_sum
            denom_p = s_p * sqrt(max((n * sum(wi_vals .^ 2) - W_i_sum^2) / (n - (star ? 0 : 1)), 1e-15))
            perm_z[i, p] = abs(denom_p) < 1e-15 ? 0.0 : num_p / denom_p
        end
    end

    for i in 1:n
        extreme = count(>=(abs(z_scores[i])), abs.(perm_z[i, :]))
        p_values[i] = (extreme + 1) / (permutations + 1)
    end

    GetisOrdResult(z_scores, p_values, star, n)
end

"""Alias for `getis_ord`."""
const g_local = getis_ord
