# matching.jl — Nearest-neighbour propensity score matching using NearestNeighbors.jl

struct MatchResult
    matched_pairs::Vector{Tuple{Int,Int}}  # (treated_idx, control_idx)
    att::Float64
    se::Float64
    ci_lower::Float64
    ci_upper::Float64
    n_matched::Int
    n_treated::Int
    n_control::Int
    smd_before::Vector{Float64}   # std mean diff per covariate before matching
    smd_after::Vector{Float64}    # std mean diff per covariate after matching
    caliper::Float64
end

"""
    nn_match(D, y, ps, X; k, caliper, replace, rng) -> MatchResult

Greedy 1:k nearest-neighbour propensity score matching using NearestNeighbors.jl KDTree.
- `caliper`: maximum allowed |PSi - PSj| (default 0.2*SD(PS))
- `replace=false`: without replacement (each control used once)
"""
function nn_match(D::AbstractVector, y::AbstractVector,
                  ps::AbstractVector, X::AbstractMatrix;
                  k::Int=1, caliper::Union{Float64,Nothing}=nothing,
                  replace::Bool=false,
                  n_boot::Int=200, rng=Random.default_rng())
    n = length(y)
    treat_idx   = findall(==(1), D)
    control_idx = findall(==(0), D)
    n_t = length(treat_idx); n_c = length(control_idx)
    cal = isnothing(caliper) ? 0.2 * std(ps) : caliper

    # Build a KDTree on control propensity scores (1D -> reshape to 1xN matrix)
    ps_ctrl = reshape(Float64.(ps[control_idx]), 1, n_c)
    tree = KDTree(ps_ctrl)

    # Sort treated by PS (improves greedy quality slightly)
    order   = sortperm(ps[treat_idx])
    sorted_t = treat_idx[order]

    used_ctrl = Set{Int}()
    pairs     = Tuple{Int,Int}[]

    # Query enough neighbors to handle replacement filtering
    k_query = replace ? k : min(n_c, k + 50)

    for ti in sorted_t
        ps_ti = Float64.(reshape([ps[ti]], 1, 1))
        idxs, dists = knn(tree, ps_ti, k_query)
        nn_idxs = idxs[1]   # indices into control_idx
        nn_dists = dists[1]  # distances

        matched = 0
        for (ci_pos, d) in zip(nn_idxs, nn_dists)
            ci = control_idx[ci_pos]
            if d > cal; continue; end
            if !replace && ci in used_ctrl; continue; end
            push!(pairs, (ti, ci))
            push!(used_ctrl, ci)
            matched += 1
            if matched >= k; break; end
        end
    end

    # ATT = mean(y_treated - y_matched_control)
    if isempty(pairs)
        return MatchResult(pairs, NaN, NaN, NaN, NaN, 0, n_t, n_c,
                           Float64[], Float64[], cal)
    end

    diffs = [y[ti] - mean([y[ci] for (_, ci) in filter(p -> p[1]==ti, pairs)])
             for ti in unique(first.(pairs))]
    att   = mean(diffs)

    # Bootstrap SE (resample treated units with their matches)
    boot_pairs = collect(pairs)
    treated_unique = unique(first.(boot_pairs))
    se_boot = Vector{Float64}(undef, n_boot)
    for b in 1:n_boot
        boot_t = rand(rng, treated_unique, length(treated_unique))
        d = [y[ti] - mean([y[ci] for (_, ci) in filter(p->p[1]==ti, boot_pairs)])
             for ti in boot_t]
        se_boot[b] = mean(d)
    end
    se = std(se_boot)

    # Balance: SMD before and after matching
    p = size(X, 2)
    smd_before = _smd(X[D .== 1,:], X[D .== 0,:])
    match_t_idx = unique(first.(pairs))
    match_c_idx = unique(last.(pairs))
    smd_after   = _smd(X[match_t_idx,:], X[match_c_idx,:])

    MatchResult(pairs, att, se, att-1.96se, att+1.96se,
                length(pairs), n_t, n_c, smd_before, smd_after, cal)
end

function _smd(X1::AbstractMatrix, X0::AbstractMatrix)
    p = size(X1, 2)
    [abs(mean(X1[:,j]) - mean(X0[:,j])) /
     sqrt((var(X1[:,j]) + var(X0[:,j])) / 2 + 1e-10)
     for j in 1:p]
end

"""
    att_matched(match_result) -> (att, se)

Extract ATT and SE from a MatchResult.
"""
att_matched(mr::MatchResult) = (mr.att, mr.se)

"""
    balance_table(mr, feature_names) -> Vector{NamedTuple}

Formatted balance table: covariate, SMD before, SMD after.
"""
function balance_table(mr::MatchResult, feature_names::Vector{String})
    p = length(mr.smd_before)
    [( covariate = get(feature_names, j, "x$j"),
       smd_before = mr.smd_before[j],
       smd_after  = mr.smd_after[j],
       improved   = mr.smd_after[j] < mr.smd_before[j] )
     for j in 1:p]
end
