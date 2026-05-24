# tsp.jl — Travelling Salesman Problem heuristics + optional exact MTZ via JuMP

struct TSPResult
    tour::Vector{Int}           # ordered sequence of node indices
    distance::Float64           # total tour length
    method::Symbol              # :nearest_neighbor, :two_opt, :mtz_exact
    n_nodes::Int
    improvement::Float64        # distance improvement from post-processing
end

"""
    tsp_nn(pts; start, rng) -> TSPResult

Nearest-neighbour heuristic for the TSP. Starts at `start` node and
greedily visits the nearest unvisited city.
"""
function tsp_nn(pts::AbstractMatrix;
                start::Int=1,
                rng=Random.default_rng())
    n   = size(pts, 1)
    D   = [sqrt(sum((pts[i,:] .- pts[j,:]).^2)) for i in 1:n, j in 1:n]
    visited = falses(n)
    tour    = [start]
    visited[start] = true

    for _ in 2:n
        cur  = last(tour)
        best = 0; best_d = Inf
        for j in 1:n
            !visited[j] && D[cur,j] < best_d && (best_d = D[cur,j]; best = j)
        end
        push!(tour, best); visited[best] = true
    end
    push!(tour, start)  # return to start

    dist = sum(D[tour[k], tour[k+1]] for k in 1:n)
    TSPResult(tour[1:end-1], dist, :nearest_neighbor, n, 0.0)
end

"""
    tsp_two_opt(pts; init_tour, max_iter, rng) -> TSPResult

2-opt improvement for the TSP. Reverses segments of the tour to reduce distance.
"""
function tsp_two_opt(pts::AbstractMatrix;
                     init_tour::Union{Vector{Int},Nothing}=nothing,
                     max_iter::Int=1000,
                     rng=Random.default_rng())
    n    = size(pts, 1)
    D    = [sqrt(sum((pts[i,:] .- pts[j,:]).^2)) for i in 1:n, j in 1:n]
    tour = isnothing(init_tour) ? tsp_nn(pts; rng=rng).tour : copy(init_tour)

    dist_fn = (t) -> sum(D[t[k], t[mod1(k+1,n)]] for k in 1:n)
    d0   = dist_fn(tour)
    best = copy(tour); best_d = d0

    for _ in 1:max_iter
        improved = false
        for i in 1:n-1, j in i+2:n
            # Skip if wrapping around and i=1
            (i == 1 && j == n) && continue
            new_tour = copy(best)
            reverse!(new_tour, i+1, j)
            nd = dist_fn(new_tour)
            if nd < best_d - 1e-9
                best = new_tour; best_d = nd; improved = true
            end
        end
        !improved && break
    end

    TSPResult(best, best_d, :two_opt, n, d0 - best_d)
end

"""
    tsp_exact_mtz(pts) -> TSPResult

Exact TSP via Miller-Tucker-Zemlin (MTZ) formulation using JuMP + HiGHS.
Recommended for small instances (n <= 20).
"""
function tsp_exact_mtz(pts::AbstractMatrix)
    n = size(pts, 1)
    D = [sqrt(sum((pts[i,:] .- pts[j,:]).^2)) for i in 1:n, j in 1:n]

    model = Model(HiGHS.Optimizer)
    set_silent(model)

    @variable(model, x[1:n, 1:n], Bin)        # x[i,j] = 1 if edge i->j in tour
    @variable(model, 2 <= u[2:n] <= n, Int)    # MTZ subtour elimination variables

    @objective(model, Min, sum(D[i,j] * x[i,j] for i in 1:n, j in 1:n if i != j))

    # Each node has exactly one incoming and one outgoing edge
    @constraint(model, [i=1:n], sum(x[i,j] for j in 1:n if j != i) == 1)
    @constraint(model, [j=1:n], sum(x[i,j] for i in 1:n if i != j) == 1)

    # No self-loops
    @constraint(model, [i=1:n], x[i,i] == 0)

    # MTZ subtour elimination
    @constraint(model, [i=2:n, j=2:n; i != j], u[i] - u[j] + n * x[i,j] <= n - 1)

    optimize!(model)

    # Extract tour
    x_val = value.(x)
    tour = [1]
    cur = 1
    for _ in 2:n
        next = findfirst(j -> j != cur && x_val[cur,j] > 0.5, 1:n)
        push!(tour, next)
        cur = next
    end

    dist = sum(D[tour[k], tour[mod1(k+1,n)]] for k in 1:n)
    TSPResult(tour, dist, :mtz_exact, n, 0.0)
end

"""
    tsp_total_distance(result) -> Float64
"""
tsp_total_distance(r::TSPResult) = r.distance
