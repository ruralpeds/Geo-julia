# capacitated.jl — Capacitated Facility Location + Voronoi catchments

struct CapFLPResult
    open_facilities::Vector{Int}
    assignment::Vector{Int}       # demand i → facility index
    objective::Float64
    capacity_used::Vector{Float64}
    capacity_slack::Vector{Float64}
    feasible::Bool
end

"""
    cap_flp(demand_pts, cand_pts, p; weights, capacities, max_iter, rng) -> CapFLPResult

Capacitated p-median: minimise total weighted distance subject to capacity
constraints at each open facility. Uses a greedy-then-exchange heuristic.

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

    # Greedy initialisation: same as p-median but honour capacities
    open_set  = Int[]
    cost_vec  = fill(Inf, n)
    remaining = collect(1:m)
    for _ in 1:p
        best_j = 0; best_gain = -Inf
        for j in remaining
            new_cost = min.(cost_vec, D[:,j])
            gain     = sum(weights .* (cost_vec .- new_cost))
            if gain > best_gain; best_gain = gain; best_j = j; end
        end
        best_j == 0 && break
        push!(open_set, best_j)
        filter!(x -> x != best_j, remaining)
        cost_vec = min.(cost_vec, D[:,best_j])
    end

    # Capacity-feasible assignment via greedy nearest-feasible
    assign_fn = (os) -> begin
        load  = zeros(length(os))
        asgn  = zeros(Int, n)
        order = sortperm(minimum(D[i, os] for i in 1:n) for i in 1:n)  # nearest first
        for idx in order
            i = idx
            sorted_f = sortperm(D[i, os])
            for k in sorted_f
                if load[k] + weights[i] <= capacities[os[k]] + 1e-9
                    asgn[i] = k; load[k] += weights[i]; break
                end
            end
            asgn[i] == 0 && (asgn[i] = sorted_f[1]; load[sorted_f[1]] += weights[i])
        end
        obj = sum(weights[i] * D[i, os[asgn[i]]] for i in 1:n)
        obj, asgn, load
    end

    obj, asgn, load = assign_fn(open_set)
    slack = [capacities[open_set[k]] - load[k] for k in 1:length(open_set)]

    # 2-opt swap improvement
    for _ in 1:max_iter
        improved = false
        for j_out in shuffle(rng, copy(open_set))
            for j_in in shuffle(rng, collect(setdiff(1:m, open_set)))
                ns = copy(open_set); replace!(ns, j_out => j_in)
                new_obj, new_asgn, new_load = assign_fn(ns)
                if new_obj < obj - 1e-9
                    open_set = ns; obj = new_obj; asgn = new_asgn; load = new_load
                    improved = true; break
                end
            end
            improved && break
        end
        !improved && break
    end

    feasible = all(load[k] <= capacities[open_set[k]] + 1e-6 for k in 1:length(open_set))
    slack    = [capacities[open_set[k]] - load[k] for k in 1:length(open_set)]

    # Convert local assignment (1..p) to global facility index
    global_asgn = open_set[asgn]
    CapFLPResult(sort(open_set), global_asgn, obj, load, slack, feasible)
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
    mdist = [mean(D[i,asgn[i]] for i in 1:n if asgn[i]==j; init=0.0) for j in 1:m]
    (assignment=asgn, catchment_pop=pop, mean_dist=mdist,
     total_pop=sum(weights), n_facilities=m)
end
