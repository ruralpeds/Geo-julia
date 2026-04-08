# covering.jl — Set covering and Maximal Covering Location Problem (MCLP)

struct SetCoverResult
    open_facilities::Vector{Int}
    covered::Vector{Bool}
    n_facilities::Int
    n_covered::Int
    coverage_fraction::Float64
    demand_covered::Float64
    demand_total::Float64
end

struct MCLPResult
    open_facilities::Vector{Int}
    covered::Vector{Bool}
    p::Int
    demand_covered::Float64
    demand_total::Float64
    coverage_fraction::Float64
end

"""
    set_cover(demand_pts, cand_pts; coverage_radius, weights) -> SetCoverResult

Greedy set cover: find the minimum number of facilities such that every demand
point is within `coverage_radius` of at least one open facility.
"""
function set_cover(demand_pts::AbstractMatrix,
                   cand_pts::AbstractMatrix;
                   coverage_radius::Float64,
                   weights::AbstractVector=ones(size(demand_pts,1)))
    n, m  = size(demand_pts,1), size(cand_pts,1)
    # Coverage matrix A[i,j] = 1 if demand i is within radius of candidate j
    A = [sqrt(sum((demand_pts[i,:] .- cand_pts[j,:]).^2)) <= coverage_radius
         for i in 1:n, j in 1:m]

    covered   = falses(n)
    open_set  = Int[]
    remaining = collect(1:m)

    while !all(covered) && !isempty(remaining)
        # Pick facility covering most uncovered (weighted) demand
        best_j = 0; best_gain = -1.0
        for j in remaining
            gain = sum(weights[i] for i in 1:n if A[i,j] && !covered[i]; init=0.0)
            if gain > best_gain; best_gain = gain; best_j = j; end
        end
        best_j == 0 && break  # no progress possible
        push!(open_set, best_j)
        filter!(x -> x != best_j, remaining)
        for i in 1:n; A[i,best_j] && (covered[i] = true); end
    end

    w_cov = sum(weights[covered]); w_tot = sum(weights)
    SetCoverResult(sort(open_set), covered, length(open_set), sum(covered),
                   sum(covered)/n, w_cov, w_tot)
end

"""
    mclp(demand_pts, cand_pts, p; coverage_radius, weights) -> MCLPResult

Maximal Covering Location Problem (Church & ReVelle 1974):
place exactly `p` facilities to maximise total weighted demand covered within
`coverage_radius`. Uses greedy with perturbation.
"""
function mclp(demand_pts::AbstractMatrix,
              cand_pts::AbstractMatrix,
              p::Int;
              coverage_radius::Float64,
              weights::AbstractVector=ones(size(demand_pts,1)),
              n_restarts::Int=5,
              rng=Random.default_rng())
    n, m = size(demand_pts,1), size(cand_pts,1)
    p    = min(p, m)
    A    = [sqrt(sum((demand_pts[i,:] .- cand_pts[j,:]).^2)) <= coverage_radius
            for i in 1:n, j in 1:m]

    obj_fn = (os) -> begin
        cov = [any(A[i,j] for j in os) for i in 1:n]
        sum(weights[cov]), cov
    end

    best_set = Int[]; best_obj = -Inf

    for _ in 1:n_restarts
        # Random greedy initialisation
        open_set = Int[]
        covered  = falses(n)
        cands    = randperm(rng, m)
        for _ in 1:p
            best_j = 0; best_gain = -1.0
            for j in cands
                j in open_set && continue
                gain = sum(weights[i] for i in 1:n if A[i,j] && !covered[i]; init=0.0)
                if gain > best_gain; best_gain = gain; best_j = j; end
            end
            best_j == 0 && break
            push!(open_set, best_j)
            for i in 1:n; A[i,best_j] && (covered[i] = true); end
        end

        # 1-opt improvement
        changed = true
        while changed
            changed = false
            cur_obj, _ = obj_fn(open_set)
            for j_out in open_set
                for j_in in setdiff(1:m, open_set)
                    ns = copy(open_set); replace!(ns, j_out => j_in)
                    nobj, _ = obj_fn(ns)
                    if nobj > cur_obj + 1e-9
                        open_set = ns; cur_obj = nobj; changed = true; break
                    end
                end
                changed && break
            end
        end

        cur_obj, _ = obj_fn(open_set)
        if cur_obj > best_obj; best_obj = cur_obj; best_set = copy(open_set); end
    end

    best_obj, best_cov = obj_fn(best_set)
    w_tot = sum(weights)
    MCLPResult(sort(best_set), best_cov, p, best_obj, w_tot, best_obj/w_tot)
end
