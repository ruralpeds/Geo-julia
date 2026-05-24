# graph.jl — Healthcare graph primitives (backed by Graphs.jl)
# HealthGraph, degree centrality, betweenness, PageRank, BFS/Dijkstra

using Statistics, LinearAlgebra

# ── Graph struct ──────────────────────────────────────────────────────────────

"""
    HealthGraph

Weighted directed graph for healthcare facility networks.

Fields:
- `n`      : number of nodes
- `adj`    : adjacency list (node → [(neighbour, weight)])
- `labels` : node labels (facility names, etc.)
- `node_type` : node type vector (e.g. "hospital", "clinic", ...)
- `weights_matrix` : dense weight matrix (n×n), 0 = no edge
- `graph`  : underlying `SimpleDiGraph` from Graphs.jl
"""
struct HealthGraph
    n            ::Int
    adj          ::Vector{Vector{Tuple{Int,Float64}}}  # adj[i] = [(j, w), ...]
    labels       ::Vector{String}
    node_type    ::Vector{String}
    weight_matrix::Matrix{Float64}
    graph        ::SimpleDiGraph{Int}
end

"""
    build_graph(W; labels, node_type) -> HealthGraph

Construct a HealthGraph from a weight matrix W (n×n).
W[i,j] > 0 implies a directed edge i→j with that weight.
"""
function build_graph(W::AbstractMatrix;
                     labels   ::Vector{String}=["node$i" for i in 1:size(W,1)],
                     node_type::Vector{String}=fill("facility", size(W,1)))
    n   = size(W, 1)
    @assert size(W, 2) == n
    adj = [Vector{Tuple{Int,Float64}}() for _ in 1:n]
    g   = SimpleDiGraph(n)
    for i in 1:n, j in 1:n
        if W[i,j] > 0
            push!(adj[i], (j, Float64(W[i,j])))
            add_edge!(g, i, j)
        end
    end
    HealthGraph(n, adj, labels, node_type, Float64.(W), g)
end

# ── Degree centrality ─────────────────────────────────────────────────────────

"""
    degree_centrality(g; mode=:out) -> Vector{Float64}

Compute degree centrality for each node.
`mode ∈ {:in, :out, :total}`
"""
function degree_centrality(g::HealthGraph; mode::Symbol=:out)
    n = g.n
    d = if mode == :out
        Float64.(Graphs.outdegree(g.graph))
    elseif mode == :in
        Float64.(Graphs.indegree(g.graph))
    elseif mode == :total
        Float64.(Graphs.outdegree(g.graph)) .+ Float64.(Graphs.indegree(g.graph))
    else
        error("Unknown mode: $mode")
    end
    # Normalise by n-1
    n > 1 ? d ./ (n - 1) : d
end

"""
    strength_centrality(g; mode=:out) -> Vector{Float64}

Weighted degree (strength) centrality.
"""
function strength_centrality(g::HealthGraph; mode::Symbol=:out)
    n = g.n
    s = zeros(n)
    if mode == :out || mode == :total
        for i in 1:n, (_, w) in g.adj[i]; s[i] += w; end
    end
    if mode == :in || mode == :total
        for i in 1:n, (j, w) in g.adj[i]; s[j] += w; end
    end
    s
end

# ── BFS / Shortest paths ───────────────────────────────────────────────────────

"""
    bfs(g, source) -> (dist, parent)

BFS from `source` on the unweighted graph. dist[i] = Inf if unreachable.
"""
function bfs(g::HealthGraph, source::Int)
    dists = Graphs.gdistances(g.graph, source)
    parent = fill(0, g.n)
    # Reconstruct parent array via BFS tree
    tree = Graphs.bfs_tree(g.graph, source)
    for e in Graphs.edges(tree)
        parent[Graphs.dst(e)] = Graphs.src(e)
    end
    # Convert distances: -1 or typemax → Inf
    dist = Vector{Float64}(undef, g.n)
    for i in 1:g.n
        dist[i] = (dists[i] == typemax(Int)) ? Inf : Float64(dists[i])
    end
    dist, parent
end

"""
    dijkstra(g, source) -> (dist, parent)

Dijkstra's shortest-path from `source` using Graphs.jl.
Edge weights come from the stored weight matrix.
"""
function dijkstra(g::HealthGraph, source::Int)
    ds = Graphs.dijkstra_shortest_paths(g.graph, source, g.weight_matrix)
    dist   = Vector{Float64}(undef, g.n)
    parent = Vector{Int}(undef, g.n)
    for i in 1:g.n
        dist[i]   = ds.dists[i] == typemax(Float64) ? Inf : ds.dists[i]
        parent[i] = ds.parents[i]
    end
    dist, parent
end

# ── Betweenness centrality ────────────────────────────────────────────────────

"""
    betweenness_centrality(g; normalise=true) -> Vector{Float64}

Betweenness centrality via Graphs.jl (Brandes algorithm).
"""
function betweenness_centrality(g::HealthGraph; normalise::Bool=true)
    Graphs.betweenness_centrality(g.graph; normalize=normalise)
end

# ── PageRank ──────────────────────────────────────────────────────────────────

"""
    pagerank(g; d=0.85, max_iter=100, tol=1e-8) -> Vector{Float64}

PageRank via Graphs.jl. d = damping factor (Brin & Page 1998).
"""
function pagerank(g::HealthGraph; d::Float64=0.85,
                  max_iter::Int=100, tol::Float64=1e-8)
    Graphs.pagerank(g.graph, d, max_iter, tol)
end

# ── Clustering coefficient ────────────────────────────────────────────────────

"""
    clustering_coefficient(g) -> (local_cc, global_cc)

Local clustering coefficient for each node and global average.
"""
function clustering_coefficient(g::HealthGraph)
    cc = Graphs.local_clustering_coefficient(g.graph)
    cc, mean(cc)
end

# ── Connected components ──────────────────────────────────────────────────────

"""
    weakly_connected_components(g) -> Vector{Vector{Int}}

Weakly connected components (treating directed edges as undirected).
"""
function weakly_connected_components(g::HealthGraph)
    Graphs.weakly_connected_components(g.graph)
end
