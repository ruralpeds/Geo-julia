# clustering.jl — DBSCAN, Knox test, spatial scan for point patterns
# Uses Clustering.jl for DBSCAN and Distances.jl for distance computation

# ── DBSCAN ────────────────────────────────────────────────────────────────────

"""
    DBSCANResult

DBSCAN clustering result.
"""
struct DBSCANResult
    labels    ::Vector{Int}   # 0 = noise, 1..k = cluster ID
    n_clusters::Int
    n_noise   ::Int
    core_pts  ::Vector{Int}
    cluster_sizes::Vector{Int}
end

"""
    dbscan(pts; ε, min_pts) -> DBSCANResult

DBSCAN (Ester et al. 1996) density-based spatial clustering.
Uses Clustering.jl `dbscan()` internally.
"""
function dbscan(pts::AbstractMatrix; ε::Float64=1.0, min_pts::Int=3)
    n = size(pts, 1)

    # Clustering.jl dbscan expects a distance matrix or data in columns
    D = Distances.pairwise(Distances.Euclidean(), pts, dims=1)
    result = _Clustering.dbscan(D, ε; min_neighbors=min_pts - 1, metric=nothing)

    # Convert Clustering.jl result to our format
    labels = zeros(Int, n)
    n_clusters = length(result)
    cluster_sizes = Int[]
    core_pts_all = Int[]

    for (k, cluster) in enumerate(result)
        for idx in cluster.core_indices
            labels[idx] = k
            push!(core_pts_all, idx)
        end
        for idx in cluster.boundary_indices
            labels[idx] = k
        end
        push!(cluster_sizes, cluster.size)
    end

    n_noise = sum(labels .== 0)

    DBSCANResult(labels, n_clusters, n_noise, sort(core_pts_all), cluster_sizes)
end

# ── Knox test for space-time clustering ───────────────────────────────────────

"""
    KnoxResult

Knox (1964) space-time clustering test.
"""
struct KnoxResult
    observed  ::Int      # count of space-time close pairs
    expected  ::Float64  # expected under independence
    p_value   ::Float64  # Monte Carlo p-value
    ratio     ::Float64  # observed / expected
    d_threshold::Float64
    t_threshold::Float64
end

"""
    knox_test(coords, times; d_thresh, t_thresh, n_perm, rng) -> KnoxResult

Knox test: count pairs (i,j) where d(xᵢ,xⱼ) ≤ d_thresh AND |tᵢ-tⱼ| ≤ t_thresh.
Under H₀ (no space-time interaction): times are randomly permuted.
Uses Distances.jl for spatial distance computation.
"""
function knox_test(coords::AbstractMatrix, times::AbstractVector;
                   d_thresh::Float64=1.0,
                   t_thresh::Float64=7.0,
                   n_perm::Int=199,
                   rng::AbstractRNG=Random.GLOBAL_RNG)
    n = length(times)
    @assert size(coords, 1) == n

    D = Distances.pairwise(Distances.Euclidean(), coords, dims=1)

    _count_pairs = function(t_perm)
        count  = 0
        for i in 1:n-1, j in i+1:n
            if D[i,j] <= d_thresh && abs(t_perm[i] - t_perm[j]) <= t_thresh
                count += 1
            end
        end
        count
    end

    obs_count = _count_pairs(times)

    # Permutation distribution
    perm_counts = [_count_pairs(times[randperm(rng, n)]) for _ in 1:n_perm]
    p_val = mean(perm_counts .>= obs_count)
    exp_  = mean(perm_counts)

    KnoxResult(obs_count, exp_, p_val, obs_count / max(exp_, 1e-10),
               d_thresh, t_thresh)
end

# ── Spatial scan for point patterns ──────────────────────────────────────────

"""
    ScanPointResult

Spatial scan cluster for point patterns (Bernoulli model).
"""
struct ScanPointResult
    centre_idx ::Int
    radius     ::Float64
    n_cases    ::Int
    n_controls ::Int
    n_total    ::Int
    llr        ::Float64
    p_value    ::Float64
    significant::Bool
end

"""
    spatial_scan_points(cases, controls; max_frac, n_sim, alpha, rng) -> ScanPointResult

Bernoulli spatial scan statistic for case-control point data.
Uses Distances.jl for pairwise distance computation.
"""
function spatial_scan_points(cases::AbstractMatrix, controls::AbstractMatrix;
                              max_frac::Float64=0.5,
                              n_sim::Int=99,
                              alpha::Float64=0.05,
                              rng::AbstractRNG=Random.GLOBAL_RNG)
    all_pts = vcat(cases, controls)
    n_all   = size(all_pts, 1)
    n_cases = size(cases, 1)
    n_ctrl  = size(controls, 1)
    labels  = vcat(ones(Bool, n_cases), zeros(Bool, n_ctrl))
    p_global = n_cases / n_all

    D = Distances.pairwise(Distances.Euclidean(), all_pts, dims=1)

    best_llr = 0.0; best_res = nothing
    for ctr in 1:n_all
        ord = sortperm(D[ctr,:])
        n_in = 0; c_in = 0
        for k in 1:n_all
            j = ord[k]
            n_in += 1; c_in += labels[j]
            c_in > max_frac * n_cases && break
            c_out = n_cases - c_in; n_out = n_all - n_in
            n_out <= 0 && break
            p_in  = c_in  / n_in
            p_out = c_out / max(n_out, 1)
            p_in <= p_global && continue
            llr = _bern_llr(c_in, n_in, c_out, n_out, n_cases, n_all)
            if llr > best_llr
                best_llr = llr
                best_res = (ctr=ctr, radius=D[ctr,j], c_in=c_in, n_in=n_in,
                             c_out=c_out, n_out=n_out)
            end
        end
    end

    isnothing(best_res) && return ScanPointResult(1, 0.0, 0, 0, n_all, 0.0, 1.0, false)

    # Monte Carlo
    mc_llrs = zeros(n_sim)
    for s in 1:n_sim
        lbl_perm = labels[randperm(rng, n_all)]
        best_s   = 0.0
        for ctr in 1:n_all
            ord = sortperm(D[ctr,:])
            n_in = 0; c_in = 0
            for k in 1:n_all
                j = ord[k]
                n_in += 1; c_in += lbl_perm[j]
                c_in > max_frac * n_cases && break
                c_out = sum(lbl_perm) - c_in; n_out = n_all - n_in
                n_out <= 0 && break
                c_in/n_in <= sum(lbl_perm)/n_all && continue
                llr_s = _bern_llr(c_in, n_in, c_out, max(n_out,1), sum(lbl_perm), n_all)
                llr_s > best_s && (best_s = llr_s)
            end
        end
        mc_llrs[s] = best_s
    end
    p_val = mean(mc_llrs .>= best_llr)

    ScanPointResult(best_res.ctr, best_res.radius, best_res.c_in, best_res.n_in - best_res.c_in,
                    n_all, best_llr, p_val, p_val < alpha)
end

function _bern_llr(c_in, n_in, c_out, n_out, n_cases, n_all)
    eps = 1e-10
    p_in  = c_in  / max(n_in,  eps)
    p_out = c_out / max(n_out, eps)
    p_tot = n_cases / max(n_all, eps)
    t1 = c_in  > 0 ? c_in  * log(p_in  / max(p_tot, eps)) : 0.0
    t2 = (n_in-c_in) > 0 ? (n_in-c_in)*log((1-p_in)/(max(1-p_tot,eps))) : 0.0
    t3 = c_out > 0 ? c_out * log(p_out / max(p_tot, eps)) : 0.0
    t4 = (n_out-c_out) > 0 ? (n_out-c_out)*log((1-p_out)/(max(1-p_tot,eps))) : 0.0
    t1 + t2 + t3 + t4
end
