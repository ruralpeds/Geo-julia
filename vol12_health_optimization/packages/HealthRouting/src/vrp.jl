# vrp.jl — Vehicle Routing Problem via Clarke-Wright savings algorithm

struct VRPResult
    routes::Vector{Vector{Int}}     # each route: depot=0 omitted; client nodes
    route_distances::Vector{Float64}
    total_distance::Float64
    n_vehicles::Int
    n_customers::Int
    capacity_used::Vector{Float64}
    method::Symbol
end

"""
    vrp_cw(customers, depot; demands, capacity, max_routes, rng) -> VRPResult

Clarke-Wright savings algorithm for the Capacitated VRP.
`customers` is n×2; `depot` is 1×2 (or length-2 vector).
`demands[i]` = load required by customer i; `capacity` = vehicle capacity.
"""
function vrp_cw(customers::AbstractMatrix,
                depot::AbstractVector;
                demands::AbstractVector=ones(size(customers,1)),
                capacity::Float64=Inf,
                max_routes::Int=size(customers,1),
                rng=Random.default_rng())
    n   = size(customers, 1)
    # Distances: d[0] = depot, d[1..n] = customers; using 1-based
    d_depot  = [sqrt(sum((customers[i,:] .- depot).^2)) for i in 1:n]
    d_cust   = [sqrt(sum((customers[i,:] .- customers[j,:]).^2)) for i in 1:n, j in 1:n]

    # Savings: S[i,j] = d(depot,i) + d(depot,j) - d(i,j)
    savings = [(s=d_depot[i]+d_depot[j]-d_cust[i,j], i=i, j=j)
               for i in 1:n, j in 1:n if i < j]
    sort!(savings, by=x->x.s, rev=true)

    # Initial routes: one per customer
    routes = [[i] for i in 1:n]
    route_of = Dict(i => i-1 for i in 1:n)  # customer i → route index (0-based)
    loads  = copy(demands)

    # Merge routes greedily by savings
    for sv in savings
        ri = route_of[sv.i]; rj = route_of[sv.j]
        ri == rj && continue
        # Check: i is last in its route, j is first in its route (or vice versa)
        ri_route = routes[ri+1]; rj_route = routes[rj+1]
        merged = false

        candidates = [(ri_route, rj_route), (reverse(ri_route), rj_route),
                      (ri_route, reverse(rj_route)), (reverse(ri_route), reverse(rj_route))]
        for (r1, r2) in candidates
            if last(r1) == sv.i && first(r2) == sv.j
                if loads[ri+1] + loads[rj+1] <= capacity
                    new_route = vcat(r1, r2)
                    routes[ri+1] = new_route
                    loads[ri+1] += loads[rj+1]
                    # Reassign all customers in r2 to ri
                    for c in r2; route_of[c] = ri; end
                    routes[rj+1] = Int[]
                    loads[rj+1]  = 0.0
                    merged = true; break
                end
            end
        end
    end

    # Clean up empty routes
    final_routes = filter(!isempty, routes)
    final_loads  = Float64[]
    for r in final_routes
        push!(final_loads, sum(demands[c] for c in r))
    end

    # Compute route distances (depot → customers → depot)
    route_dists = Float64[]
    for r in final_routes
        d = d_depot[r[1]]
        for k in 1:length(r)-1; d += d_cust[r[k], r[k+1]]; end
        d += d_depot[r[end]]
        push!(route_dists, d)
    end

    VRPResult(final_routes, route_dists, sum(route_dists),
              length(final_routes), n, final_loads, :clarke_wright)
end

"""
    vrp_route_distance(route, customers, depot) -> Float64

Total distance of a single route (depot → stops → depot).
"""
function vrp_route_distance(route::Vector{Int},
                             customers::AbstractMatrix,
                             depot::AbstractVector)
    isempty(route) && return 0.0
    d  = sqrt(sum((customers[route[1],:] .- depot).^2))
    for k in 1:length(route)-1
        d += sqrt(sum((customers[route[k],:] .- customers[route[k+1],:]).^2))
    end
    d += sqrt(sum((customers[route[end],:] .- depot).^2))
    d
end
