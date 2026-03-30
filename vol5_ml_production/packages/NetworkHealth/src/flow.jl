# flow.jl — Network flow analysis for referral patterns
# Chapter 36.4

"""
    max_flow_bfs(g, source, sink) -> Float64

Ford-Fulkerson algorithm with BFS augmenting paths (Edmonds-Karp).
Computes maximum patient flow between source provider and sink (hospital).
O(VE²)
"""
function max_flow_bfs(g::ReferralNetwork, source::Int, sink::Int)::Float64
    n        = g.n
    capacity = Matrix(g.adj)  # mutable capacity matrix
    flow_val = 0.0

    while true
        # BFS to find augmenting path
        parent = fill(-1, n)
        parent[source] = source
        queue = [source]
        head  = 1
        while head <= length(queue) && parent[sink] == -1
            v = queue[head]; head += 1
            for u in 1:n
                capacity[v, u] > 1e-12 && parent[u] == -1 || continue
                parent[u] = v
                push!(queue, u)
            end
        end
        parent[sink] == -1 && break   # no augmenting path

        # Find bottleneck
        path_flow = Inf
        v = sink
        while v != source
            u = parent[v]
            path_flow = min(path_flow, capacity[u, v])
            v = u
        end

        # Update capacities
        v = sink
        while v != source
            u = parent[v]
            capacity[u, v] -= path_flow
            capacity[v, u] += path_flow
            v = u
        end
        flow_val += path_flow
    end
    flow_val
end

"""
    referral_concentration(g) -> Vector{Float64}

For each provider, compute the referral concentration (Herfindahl-like):
  C_v = Σ_j (w_{vj} / k_out_v)²

C = 1 → all referrals go to one provider (monopoly)
C = 1/k → perfectly distributed
"""
function referral_concentration(g::ReferralNetwork)
    n  = g.n
    dc = zeros(n)
    for v in 1:n
        row    = g.adj[v, :]
        total  = sum(row)
        total < 1e-12 && continue
        fracs  = nonzeros(row) ./ total
        dc[v]  = sum(fracs.^2)
    end
    dc
end

"""
    herfindahl_index(market_shares::Vector{Float64}) -> Float64

Herfindahl-Hirschman Index (HHI) of market concentration.
HHI = Σ s_i²  (shares as fractions, not percentages)

HHI < 0.15  → competitive market
0.15–0.25   → moderately concentrated
HHI > 0.25  → highly concentrated
"""
function herfindahl_index(market_shares::AbstractVector{<:Real})::Float64
    shares = market_shares ./ max(sum(market_shares), 1e-12)
    sum(shares.^2)
end

"""
    shortest_paths(g, source) -> Vector{Float64}

BFS/Dijkstra shortest path distances from `source` to all nodes.
Returns Inf for unreachable nodes.
"""
function shortest_paths(g::ReferralNetwork, source::Int)::Vector{Float64}
    dist, _, _ = _bfs_single_source(g, source)
    dist
end

"""
    diameter(g) -> Float64

Graph diameter: maximum finite shortest-path distance.
"""
function diameter(g::ReferralNetwork)::Float64
    diam = 0.0
    for v in 1:g.n
        d = shortest_paths(g, v)
        finite_d = filter(isfinite, d)
        isempty(finite_d) && continue
        diam = max(diam, maximum(finite_d))
    end
    diam
end

"""
    average_path_length(g) -> Float64

Mean shortest-path length over all reachable pairs.
"""
function average_path_length(g::ReferralNetwork)::Float64
    total = 0.0
    count = 0
    for v in 1:g.n
        d = shortest_paths(g, v)
        for d_val in d
            isfinite(d_val) && d_val > 0 || continue
            total += d_val
            count += 1
        end
    end
    count == 0 ? Inf : total / count
end
