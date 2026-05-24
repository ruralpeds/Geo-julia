# pmedian.jl — p-median facility location via JuMP IP formulation

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
to their nearest open facility. Uses JuMP integer programming formulation with
HiGHS solver.

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

    # ── JuMP IP formulation ──────────────────────────────────────────────────
    model = Model(HiGHS.Optimizer)
    set_silent(model)

    @variable(model, x[1:n, 1:m], Bin)   # x[i,j] = 1 if demand i assigned to facility j
    @variable(model, y[1:m], Bin)          # y[j] = 1 if facility j is open

    @objective(model, Min, sum(weights[i] * D[i,j] * x[i,j] for i in 1:n, j in 1:m))

    # Each demand point assigned to exactly one facility
    @constraint(model, [i=1:n], sum(x[i,j] for j in 1:m) == 1)

    # Open exactly p facilities
    @constraint(model, sum(y) == p)

    # Can only assign to open facilities
    @constraint(model, [i=1:n, j=1:m], x[i,j] <= y[j])

    optimize!(model)

    # Extract solution
    y_val = value.(y)
    x_val = value.(x)
    open_set = sort([j for j in 1:m if y_val[j] > 0.5])
    asgn = [argmax([x_val[i,j] for j in open_set]) for i in 1:n]
    obj = objective_value(model)

    PMedianResult(open_set, asgn, obj, 1, [obj], n, p)
end

# Convenience: candidates = demand points
p_median(pts::AbstractMatrix, p::Int; kw...) = p_median(pts, pts, p; kw...)

"""
    p_median_obj(result) -> Float64

Return the optimised objective value.
"""
p_median_obj(r::PMedianResult) = r.objective
