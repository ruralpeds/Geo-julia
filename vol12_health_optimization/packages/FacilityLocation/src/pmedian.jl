# pmedian.jl — p-median facility location (Hakimi 1964)

# ── Input validation helpers (inline; no external package dep required) ────────
_check_2d(m, name) = size(m, 2) == 2 && size(m, 1) > 0 ||
    error("$(name) must be an n×2 coordinate matrix (got $(size(m)))")
_check_pos(x, name) = x > 0 ||
    error("$(name) must be strictly positive (got $(x))")

struct PMedianResult
    open_facilities::Vector{Int}    # indices of open facilities
    assignment::Vector{Int}         # assignment[i] = facility index for demand i
    objective::Float64              # total weighted distance
    iterations::Int
    improvement_history::Vector{Float64}
    n_demand::Int
    p::Int
end

"""
    p_median(demand_pts, cand_pts, p; weights, max_iter, rng) -> PMedianResult

Solve the p-median problem: minimise total weighted distance from demand points
to their nearest open facility. Uses greedy initialisation followed by 2-opt
facility swap improvement.

`demand_pts` is n×2; `cand_pts` is m×2 (candidate facility sites).
If `cand_pts` is omitted, candidates = demand points (unrestricted p-median).
"""
function p_median(demand_pts::AbstractMatrix,
                  cand_pts::AbstractMatrix,
                  p::Int;
                  weights::AbstractVector=ones(size(demand_pts,1)),
                  max_iter::Int=500,
                  rng=Random.default_rng())
    # ── Validate inputs ──────────────────────────────────────────────────────
    _check_2d(demand_pts, "demand_pts")
    _check_2d(cand_pts,   "cand_pts")
    _check_pos(p, "p")
    _check_pos(max_iter, "max_iter")
    length(weights) == size(demand_pts, 1) ||
        error("weights length ($(length(weights))) ≠ number of demand points ($(size(demand_pts,1)))")
    any(weights .< 0) && error("all weights must be non-negative")
    !all(isfinite, demand_pts) && error("demand_pts contains NaN or Inf")
    !all(isfinite, cand_pts)   && error("cand_pts contains NaN or Inf")

    n, m = size(demand_pts,1), size(cand_pts,1)
    p    = min(p, m)

    # Distance matrix D[i,j] = dist(demand i, candidate j)
    D = [sqrt(sum((demand_pts[i,:] .- cand_pts[j,:]).^2)) for i in 1:n, j in 1:m]

    # Greedy initialisation: pick p candidates minimising total weighted distance
    open_set  = Int[]
    remaining = collect(1:m)
    cost_vec  = fill(Inf, n)     # cost_vec[i] = min dist from i to any open facility

    for _ in 1:p
        best_j = 0; best_gain = -Inf
        for j in remaining
            new_cost = min.(cost_vec, D[:,j])
            gain     = sum(weights .* (cost_vec .- new_cost))
            if gain > best_gain; best_gain = gain; best_j = j; end
        end
        push!(open_set, best_j)
        filter!(x -> x != best_j, remaining)
        cost_vec = min.(cost_vec, D[:,best_j])
    end

    # Compute objective and assignment
    obj_fn = (os) -> begin
        asgn = [argmin(D[i, os]) for i in 1:n]
        obj  = sum(weights[i] * D[i, os[asgn[i]]] for i in 1:n)
        obj, asgn
    end

    obj, asgn = obj_fn(open_set)
    history   = [obj]
    iters     = 0

    # 2-opt swap improvement
    for iter in 1:max_iter
        iters = iter
        improved = false
        for j_open in shuffle(rng, copy(open_set))
            for j_close in shuffle(rng, collect(setdiff(1:m, open_set)))
                new_set = copy(open_set)
                replace!(new_set, j_open => j_close)
                new_obj, _ = obj_fn(new_set)
                if new_obj < obj - 1e-9
                    open_set = new_set; obj = new_obj; _, asgn = obj_fn(open_set)
                    improved = true; push!(history, obj); break
                end
            end
            improved && break
        end
        !improved && break
    end

    PMedianResult(sort(open_set), asgn, obj, iters, history, n, p)
end

# Convenience: candidates = demand points
p_median(pts::AbstractMatrix, p::Int; kw...) = p_median(pts, pts, p; kw...)

"""
    p_median_obj(result) -> Float64

Return the optimised objective value.
"""
p_median_obj(r::PMedianResult) = r.objective
