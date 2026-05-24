# vrp.jl — Vehicle Routing Problem via JuMP MIP formulation

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

Capacitated Vehicle Routing Problem solved via JuMP MIP formulation with
MTZ-style subtour elimination. Falls back to Clarke-Wright savings heuristic
for large instances (n > 25).

`customers` is n×2; `depot` is 1×2 (or length-2 vector).
`demands[i]` = load required by customer i; `capacity` = vehicle capacity.
"""
function vrp_cw(customers::AbstractMatrix,
                depot::AbstractVector;
                demands::AbstractVector=ones(size(customers,1)),
                capacity::Float64=Inf,
                max_routes::Int=size(customers,1),
                rng=Random.default_rng())
    n = size(customers, 1)

    # For large instances or infinite capacity, use Clarke-Wright heuristic
    if n > 25 || isinf(capacity)
        return _vrp_clarke_wright(customers, depot, demands, capacity, max_routes, rng)
    end

    # Distances: node 0 = depot, nodes 1..n = customers
    d_depot = [sqrt(sum((customers[i,:] .- depot).^2)) for i in 1:n]
    d_cust  = [sqrt(sum((customers[i,:] .- customers[j,:]).^2)) for i in 1:n, j in 1:n]

    # Minimum number of vehicles needed
    min_vehicles = isinf(capacity) ? 1 : Int(ceil(sum(demands) / capacity))
    K = min(max(min_vehicles, 1), max_routes, n)

    # ── JuMP MIP formulation ─────────────────────────────────────────────────
    # Nodes: 0 = depot, 1..n = customers
    # We model with n+1 nodes (depot = index n+1 internally for easier indexing)
    model = Model(HiGHS.Optimizer)
    set_silent(model)

    # x[i,j,k] = 1 if vehicle k travels from i to j
    # We use depot = 0 represented as separate depot-to/from constraints
    # Simpler: single-commodity flow with vehicle index

    # Binary arc variables: x[i,j] = 1 if any vehicle travels directly from i to j
    # Including depot as node 0 => nodes 0..n, but Julia is 1-based, so depot=n+1
    N = n + 1  # total nodes; depot = N
    @variable(model, x[1:N, 1:N], Bin)
    @variable(model, 1 <= u[1:n] <= n, Int)  # MTZ ordering variables for customers only

    # Build full distance matrix including depot
    DD = zeros(N, N)
    for i in 1:n, j in 1:n
        DD[i,j] = d_cust[i,j]
    end
    for i in 1:n
        DD[i,N] = d_depot[i]  # customer -> depot
        DD[N,i] = d_depot[i]  # depot -> customer
    end

    @objective(model, Min, sum(DD[i,j] * x[i,j] for i in 1:N, j in 1:N if i != j))

    # No self-loops
    @constraint(model, [i=1:N], x[i,i] == 0)

    # Each customer visited exactly once (one incoming, one outgoing arc)
    @constraint(model, [i=1:n], sum(x[i,j] for j in 1:N if j != i) == 1)
    @constraint(model, [j=1:n], sum(x[i,j] for i in 1:N if i != j) == 1)

    # Depot: exactly K vehicles leave and return
    @constraint(model, sum(x[N,j] for j in 1:n) == K)
    @constraint(model, sum(x[i,N] for i in 1:n) == K)

    # MTZ subtour elimination (between customers only; depot excluded)
    @constraint(model, [i=1:n, j=1:n; i != j], u[i] - u[j] + n * x[i,j] <= n - 1)

    # Capacity: for each route (each departure from depot), total demand <= capacity
    # We enforce this via cumulative load using MTZ-like constraints
    if !isinf(capacity)
        @variable(model, 0 <= load[1:n] <= capacity)
        for i in 1:n
            # If depot -> i, then load[i] = demands[i]
            @constraint(model, load[i] >= demands[i])
            for j in 1:n
                if i != j
                    # If x[i,j] = 1, load[j] >= load[i] + demands[j]
                    @constraint(model, load[j] >= load[i] + demands[j] - capacity * (1 - x[i,j]))
                end
            end
        end
    end

    optimize!(model)

    status = termination_status(model)
    if status in (OPTIMAL, LOCALLY_SOLVED, FEASIBLE_POINT)
        x_val = value.(x)
        # Extract routes from solution
        routes = _extract_vrp_routes(x_val, n, N)
        return _build_vrp_result(routes, customers, depot, demands, d_depot, d_cust, :jump_mip)
    end

    # Fallback to Clarke-Wright if MIP fails
    return _vrp_clarke_wright(customers, depot, demands, capacity, max_routes, rng)
end

"""Extract routes from the binary arc solution matrix."""
function _extract_vrp_routes(x_val, n, N)
    routes = Vector{Int}[]
    # Find all arcs leaving the depot (N)
    for j in 1:n
        if x_val[N,j] > 0.5
            # Trace route: depot -> j -> ... -> depot
            route = Int[j]
            cur = j
            safety = 0
            while safety < n + 2
                safety += 1
                next = findfirst(k -> k != cur && x_val[cur,k] > 0.5, 1:N)
                isnothing(next) && break
                next == N && break  # back to depot
                push!(route, next)
                cur = next
            end
            push!(routes, route)
        end
    end
    routes
end

"""Build VRPResult from extracted routes."""
function _build_vrp_result(routes, customers, depot, demands, d_depot, d_cust, method)
    n = size(customers, 1)
    route_dists = Float64[]
    route_loads = Float64[]
    for r in routes
        d = d_depot[r[1]]
        for k in 1:length(r)-1
            d += d_cust[r[k], r[k+1]]
        end
        d += d_depot[r[end]]
        push!(route_dists, d)
        push!(route_loads, sum(demands[c] for c in r))
    end
    VRPResult(routes, route_dists, sum(route_dists),
              length(routes), n, route_loads, method)
end

"""Clarke-Wright savings heuristic fallback for large instances."""
function _vrp_clarke_wright(customers, depot, demands, capacity, max_routes, rng)
    n = size(customers, 1)
    d_depot = [sqrt(sum((customers[i,:] .- depot).^2)) for i in 1:n]
    d_cust  = [sqrt(sum((customers[i,:] .- customers[j,:]).^2)) for i in 1:n, j in 1:n]

    # Savings: S[i,j] = d(depot,i) + d(depot,j) - d(i,j)
    savings = [(s=d_depot[i]+d_depot[j]-d_cust[i,j], i=i, j=j)
               for i in 1:n, j in 1:n if i < j]
    sort!(savings, by=x->x.s, rev=true)

    # Initial routes: one per customer
    routes = [[i] for i in 1:n]
    route_of = Dict(i => i-1 for i in 1:n)
    loads = copy(demands)

    for sv in savings
        ri = route_of[sv.i]; rj = route_of[sv.j]
        ri == rj && continue
        ri_route = routes[ri+1]; rj_route = routes[rj+1]

        candidates = [(ri_route, rj_route), (reverse(ri_route), rj_route),
                      (ri_route, reverse(rj_route)), (reverse(ri_route), reverse(rj_route))]
        for (r1, r2) in candidates
            if last(r1) == sv.i && first(r2) == sv.j
                if loads[ri+1] + loads[rj+1] <= capacity
                    new_route = vcat(r1, r2)
                    routes[ri+1] = new_route
                    loads[ri+1] += loads[rj+1]
                    for c in r2; route_of[c] = ri; end
                    routes[rj+1] = Int[]
                    loads[rj+1] = 0.0
                    break
                end
            end
        end
    end

    final_routes = filter(!isempty, routes)
    return _build_vrp_result(final_routes, customers, depot, demands, d_depot, d_cust, :clarke_wright)
end

"""
    vrp_route_distance(route, customers, depot) -> Float64

Total distance of a single route (depot -> stops -> depot).
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
