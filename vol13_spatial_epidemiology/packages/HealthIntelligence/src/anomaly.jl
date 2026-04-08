# anomaly.jl — Anomaly detection for health event streams

using Statistics, LinearAlgebra, Random

# ─── Local Outlier Factor (simplified) ───────────────────────────────────────

struct LOFResult
    lof_scores::Vector{Float64}    # LOF > 1 → potential outlier
    outliers::Vector{Bool}         # LOF > threshold
    outlier_idx::Vector{Int}
    k::Int                         # neighbourhood size
    threshold::Float64
    n::Int
end

"""
    lof(X; k, threshold) -> LOFResult

Simplified Local Outlier Factor (Breunig et al. 2000).

For each point, compare its local density to the average density of its
k nearest neighbours. LOF ≈ 1 means normal; LOF >> 1 means outlier.

Uses Euclidean distances on the feature matrix `X` (n × d).
"""
function lof(X::AbstractMatrix;
              k::Int=5,
              threshold::Float64=2.0)
    n, d = size(X)
    k    = min(k, n-1)

    # Distance matrix
    D = [sqrt(sum((X[i,:] .- X[j,:]).^2)) for i in 1:n, j in 1:n]

    # k-nearest neighbours and k-distances
    knn_idx = [sortperm(D[i,:])[2:k+1] for i in 1:n]
    k_dist  = [D[i, knn_idx[i][end]] for i in 1:n]

    # Reachability distance: rd(p,o) = max(k-dist(o), d(p,o))
    reach_dist(p, o) = max(k_dist[o], D[p,o])

    # Local reachability density
    lrd = [k / max(sum(reach_dist(i,j) for j in knn_idx[i]), 1e-12) for i in 1:n]

    # LOF
    scores = [mean(lrd[knn_idx[i]]) / max(lrd[i], 1e-12) for i in 1:n]
    outliers    = scores .> threshold
    outlier_idx = findall(outliers)
    LOFResult(scores, outliers, outlier_idx, k, threshold, n)
end

# ─── Isolation Forest (randomised approximation) ─────────────────────────────

struct IForestResult
    anomaly_scores::Vector{Float64}   # in [0,1]; > 0.5 → anomalous
    outliers::Vector{Bool}
    outlier_idx::Vector{Int}
    n_trees::Int
    subsample::Int
    threshold::Float64
    n::Int
end

"""
    isolation_forest(X; n_trees, subsample, threshold, rng) -> IForestResult

Randomised Isolation Forest (Liu et al. 2008).

Builds `n_trees` random isolation trees on subsamples of `X`.
Anomaly score = 2^(-E[path_length]/c(n)) where c(n) = average BST path length.

Anomalies are isolated (short path) → score near 1.
Normal points require many splits → score near 0.
"""
function isolation_forest(X::AbstractMatrix;
                            n_trees::Int=100,
                            subsample::Int=min(256, size(X,1)),
                            threshold::Float64=0.55,
                            rng=Random.default_rng())
    n, d = size(X)
    path_sums = zeros(n)

    for _ in 1:n_trees
        idx     = rand(rng, 1:n, subsample)
        X_sub   = X[idx, :]
        # Build isolation tree on subsample, then evaluate all n points
        paths   = _isolation_paths(X_sub, X, rng)
        path_sums .+= paths
    end

    avg_paths = path_sums ./ n_trees
    cn        = _c_factor(subsample)
    scores    = 2.0 .^ (.-avg_paths ./ cn)
    outliers      = scores .> threshold
    outlier_idx   = findall(outliers)
    IForestResult(scores, outliers, outlier_idx, n_trees, subsample, threshold, n)
end

# c(n) = average path length for a BST built on n samples
_c_factor(n::Int) = n <= 1 ? 1.0 : 2.0 * (log(n-1) + 0.5772156649) - 2(n-1)/n

function _isolation_paths(X_sub::AbstractMatrix, X_eval::AbstractMatrix, rng)
    n_sub, d = size(X_sub)
    n_eval   = size(X_eval, 1)
    max_depth = ceil(Int, log2(max(n_sub, 2)))

    # Build tree as list of (feature, split_value, left_range, right_range) splits
    function build(indices::Vector{Int}, depth::Int)
        (length(indices) <= 1 || depth >= max_depth) && return depth
        feat  = rand(rng, 1:d)
        col   = X_sub[indices, feat]
        lo, hi = minimum(col), maximum(col)
        lo == hi && return depth
        split = lo + rand(rng) * (hi - lo)
        left  = indices[col .<= split]
        right = indices[col .> split]
        max(build(left, depth+1), build(right, depth+1))
    end

    # Simplified: compute path length for each eval point by random descent
    paths = zeros(n_eval)
    for e in 1:n_eval
        indices = collect(1:n_sub)
        depth   = 0
        for _ in 1:max_depth
            length(indices) <= 1 && break
            feat  = rand(rng, 1:d)
            col   = X_sub[indices, feat]
            lo, hi = minimum(col), maximum(col)
            lo == hi && (depth += 1; break)
            split = lo + rand(rng) * (hi - lo)
            left  = indices[col .<= split]
            right = indices[col .> split]
            x_val = X_eval[e, feat]
            indices = x_val <= split ? left : right
            depth  += 1
        end
        paths[e] = depth + _c_factor(length(indices))
    end
    paths
end

# ─── CUSUM-based health event anomaly ─────────────────────────────────────────

"""
    health_event_anomaly(events, baseline; threshold_sd) -> NamedTuple

Detect anomalous health events (e.g., ER visits, 911 calls) relative to a
historical baseline using a simple z-score approach.

Returns z-scores, flags, and first anomaly time if detected.
"""
function health_event_anomaly(events::AbstractVector{<:Real},
                               baseline::AbstractVector{<:Real};
                               threshold_sd::Float64=3.0)
    μ = mean(baseline)
    σ = max(std(baseline; corrected=true), 1e-12)
    z = (Float64.(events) .- μ) ./ σ
    flags = z .> threshold_sd
    first = findfirst(flags)
    (z_scores=z, flags=flags, first_anomaly=first,
     n_anomalous=sum(flags), threshold_sd=threshold_sd)
end
