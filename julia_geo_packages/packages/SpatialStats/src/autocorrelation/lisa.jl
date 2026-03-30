# autocorrelation/lisa.jl — Local Indicators of Spatial Association (LISA)

using Statistics
using Random

"""
    LISAResult

Result of LISA (Anselin 1995) local spatial autocorrelation.

# Fields
- `I_local`      : vector of local Moran statistics
- `p_values`     : pseudo p-values from conditional randomisation
- `cluster_type` : `Vector{Symbol}` — `:HH`, `:LL`, `:HL`, `:LH`, `:NS`
- `significance` : alpha level used for cluster classification
- `n`            : number of observations
"""
struct LISAResult
    I_local      :: Vector{Float64}
    p_values     :: Vector{Float64}
    cluster_type :: Vector{Symbol}
    significance :: Float64
    n            :: Int
end

function Base.show(io::IO, r::LISAResult)
    counts = Dict(t => count(==(t), r.cluster_type) for t in [:HH,:LL,:HL,:LH,:NS])
    println(io, "LISAResult(n=$(r.n), α=$(r.significance))")
    for t in [:HH,:LL,:HL,:LH,:NS]
        println(io, "  $(t): $(counts[t])")
    end
end

# ────────────────────────────────────────────────────────────────────────────

"""
    lisa(y, w; permutations=999, alpha=0.05) -> LISAResult

Compute LISA statistics (Anselin 1995) with conditional randomisation.

For each observation i:
1. Compute local Moran I_i = z_i * (W_i ⋅ z) where z = standardised y
2. Generate null distribution by permuting all j≠i repeatedly
3. Classify into HH/LL/HL/LH/NS based on quadrant and significance

# Arguments
- `y`            : numeric vector, length n
- `w`            : `SpatialWeights`
- `permutations` : conditional permutations per observation (default 999)
- `alpha`        : significance level for cluster classification (default 0.05)
"""
function lisa(y::AbstractVector{<:Real},
              w::AbstractSpatialWeights;
              permutations :: Int    = 999,
              alpha        :: Float64 = 0.05)::LISAResult

    n = length(y)
    n == w.n || error("length(y)=$(n) ≠ w.n=$(w.n)")

    z = (Float64.(y) .- mean(y)) ./ std(y; corrected=true)
    W = w.W

    # Observed local I
    Wz      = W * z
    I_local = z .* Wz

    # Conditional permutation p-values
    p_values = Vector{Float64}(undef, n)
    z_others = copy(z)

    for i in 1:n
        I_i = I_local[i]
        # Indices of neighbours of i
        row_nz = nzrange(W, i)   # note: SparseMatrixCSC is column-major; use rowvals
        # For CSC, row access: get row i of W = column i of W'
        # Use: findnz on the i-th row via transpose trick
        wi_row = W[i, :]  # sparse row vector

        # Extract non-zero column indices for row i
        nb_indices = SparseArrays.findnz(wi_row)[1]
        n_nb = length(nb_indices)

        if n_nb == 0
            p_values[i] = 1.0
            continue
        end

        # Pool of non-i values for permutation
        pool = deleteat!(collect(1:n), i)

        count_extreme = 0
        for _ in 1:permutations
            perm_idx = sample(pool, n_nb; replace=false)
            lag_i = sum(wi_row[nb_indices[k]] * z[perm_idx[k]] for k in 1:n_nb)
            I_perm = z[i] * lag_i
            if abs(I_perm) >= abs(I_i)
                count_extreme += 1
            end
        end
        p_values[i] = (count_extreme + 1) / (permutations + 1)
    end

    # Classify clusters
    cluster_type = Vector{Symbol}(undef, n)
    Wz_mean = mean(z)
    for i in 1:n
        if p_values[i] > alpha
            cluster_type[i] = :NS
        elseif z[i] > 0 && Wz[i] > 0
            cluster_type[i] = :HH
        elseif z[i] < 0 && Wz[i] < 0
            cluster_type[i] = :LL
        elseif z[i] > 0 && Wz[i] < 0
            cluster_type[i] = :HL
        else
            cluster_type[i] = :LH
        end
    end

    LISAResult(I_local, p_values, cluster_type, alpha, n)
end

# moran_local is an alias
const moran_local = lisa

# ────────────────────────────────────────────────────────────────────────────
# Helper: StatsBase sample without loading the full module at top level

function sample(pool::Vector{Int}, k::Int; replace::Bool)
    replace && return pool[rand(1:length(pool), k)]
    n = length(pool)
    idx = copy(pool)
    result = Vector{Int}(undef, k)
    for i in 1:k
        j = rand(i:n)
        idx[i], idx[j] = idx[j], idx[i]
        result[i] = idx[i]
    end
    result
end
