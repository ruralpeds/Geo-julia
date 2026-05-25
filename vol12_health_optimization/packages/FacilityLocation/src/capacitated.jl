# capacitated.jl — Capacitated Facility Location via JuMP + Voronoi catchments

struct CapFLPResult
    open_facilities::Vector{Int}
    assignment::Vector{Int}       # demand i -> facility index (global)
    objective::Float64
    capacity_used::Vector{Float64}
    capacity_slack::Vector{Float64}
    feasible::Bool
end

"""
    cap_flp(demand_pts, cand_pts, p; weights, capacities, max_iter, rng) -> CapFLPResult

Capacitated p-median via JuMP IP: minimise total weighted distance subject to
capacity constraints at each open facility.

`capacities`: length-m vector; total weight each candidate can serve.
"""
function cap_flp(demand_pts::AbstractMatrix,
                 cand_pts::AbstractMatrix,
                 p::Int;
                 weights::AbstractVector=ones(size(demand_pts,1)),
                 capacities::AbstractVector=fill(Inf, size(cand_pts,1)),
                 max_iter::Int=300,
                 rng=Random.default_rng())
    n, m = size(demand_pts,1), size(cand_pts,1)
    p    = min(p, m)
    D    = [sqrt(sum((demand_pts[i,:] .- cand_pts[j,:]).^2)) for i in 1:n, j in 1:m]

    # Cap infinite capacities at total demand to keep the model bounded
    total_demand = sum(weights)
    caps = [isinf(capacities[j]) ? total_demand : capacities[j] for j in 1:m]

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

    # Capacity constraints
    @constraint(model, [j=1:m], sum(weights[i] * x[i,j] for i in 1:n) <= caps[j] * y[j])

    optimize!(model)

    status = termination_status(model)

    if status in (OPTIMAL, LOCALLY_SOLVED, FEASIBLE_POINT)
        y_val = value.(y)
        x_val = value.(x)
        open_set = sort([j for j in 1:m if y_val[j] > 0.5])
        # Build assignment: for each demand point, which open facility
        global_asgn = [open_set[argmax([x_val[i,j] for j in open_set])] for i in 1:n]
        # Local assignment index (1..p) for compatibility
        asgn_local = [findfirst(==(global_asgn[i]), open_set) for i in 1:n]
        obj = objective_value(model)
        load = [sum(weights[i] for i in 1:n if global_asgn[i] == j; init=0.0) for j in open_set]
        slack = [caps[open_set[k]] - load[k] for k in 1:length(open_set)]
        feasible = all(load[k] <= caps[open_set[k]] + 1e-6 for k in 1:length(open_set))
        CapFLPResult(open_set, global_asgn, obj, load, slack, feasible)
    else
        # Fallback: return infeasible result
        CapFLPResult(Int[], zeros(Int, n), Inf, Float64[], Float64[], false)
    end
end

"""
    catchment_voronoi(demand_pts, facility_pts; weights) -> NamedTuple

Compute Voronoi catchment areas: assign each demand point to its nearest facility.
Returns assignment, catchment populations, and service pressure.
"""
function catchment_voronoi(demand_pts::AbstractMatrix,
                           facility_pts::AbstractMatrix;
                           weights::AbstractVector=ones(size(demand_pts,1)))
    n, m  = size(demand_pts,1), size(facility_pts,1)
    D     = [sqrt(sum((demand_pts[i,:] .- facility_pts[j,:]).^2)) for i in 1:n, j in 1:m]
    asgn  = [argmin(D[i,:]) for i in 1:n]
    pop   = [sum(weights[asgn .== j]) for j in 1:m]
    # Simple Gini coefficient for population distribution
    gini = if sum(pop) > 0
        p_sorted = sort(pop)
        n_p = length(p_sorted)
        sum((2i - n_p - 1) * p_sorted[i] for i in 1:n_p) / (n_p * sum(p_sorted))
    else
        0.0
    end
    mdist = [let d_vals = [D[i,asgn[i]] for i in 1:n if asgn[i]==j]
                isempty(d_vals) ? 0.0 : mean(d_vals)
             end for j in 1:m]
    (assignment=asgn, catchment_pop=pop, mean_dist=mdist,
     total_pop=sum(weights), n_facilities=m, gini=gini)
end
