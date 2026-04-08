# access_metrics.jl — Network-based healthcare access metrics
# Chapter 36.5

"""
    NetworkSummary

Summary statistics for a ReferralNetwork.
"""
struct NetworkSummary
    n_nodes             ::Int
    n_edges             ::Int
    density             ::Float64
    avg_clustering      ::Float64
    avg_path_length     ::Float64
    diameter            ::Float64
    hhi_in              ::Float64   # HHI of in-degree distribution
    hhi_out             ::Float64   # HHI of out-degree distribution
    n_communities       ::Int
    largest_community_sz::Int
    giant_component_frac::Float64
end

"""
    summarize(g) -> NetworkSummary
"""
function summarize(g::ReferralNetwork)
    n  = g.n
    m  = g.m
    den = g.directed ? m / max(n*(n-1), 1) : 2m / max(n*(n-1), 1)

    # Clustering coefficient (local, undirected approximation)
    A = g.adj + g.adj'
    avg_clust = _avg_clustering(A, n)

    apl  = average_path_length(g)
    diam = diameter(g)

    # HHI of degree distributions
    out_deg = vec(sum(g.adj; dims=2))
    in_deg  = vec(sum(g.adj; dims=1))
    hhi_o = herfindahl_index(out_deg)
    hhi_i = herfindahl_index(in_deg)

    # Community sizes
    comms = label_propagation(g)
    comm_sizes = values(StatsBase.countmap(comms))
    n_comm = length(comm_sizes)
    largest = maximum(comm_sizes)

    # Giant component (BFS from node 1)
    d1 = shortest_paths(g, 1)
    giant_frac = count(isfinite, d1) / n

    NetworkSummary(n, m, den, avg_clust, apl, diam, hhi_i, hhi_o,
                   n_comm, largest, giant_frac)
end

function _avg_clustering(A, n)
    total = 0.0
    for v in 1:n
        nbrs = A[v, :].nzind
        k    = length(nbrs)
        k < 2 && continue
        # Count edges among neighbours
        edges_among = 0
        for i in nbrs, j in nbrs
            i != j && A[i, j] > 0 && (edges_among += 1)
        end
        total += edges_among / (k * (k-1))
    end
    n == 0 ? 0.0 : total / n
end

function Base.show(io::IO, s::NetworkSummary)
    println(io, "NetworkSummary:")
    println(io, "  Nodes: $(s.n_nodes)  Edges: $(s.n_edges)  Density: $(round(s.density; digits=4))")
    println(io, "  Avg clustering: $(round(s.avg_clustering; digits=3))")
    println(io, "  Avg path length: $(round(s.avg_path_length; digits=2))  Diameter: $(s.diameter)")
    println(io, "  HHI in-degree: $(round(s.hhi_in; digits=3))  HHI out-degree: $(round(s.hhi_out; digits=3))")
    println(io, "  Communities: $(s.n_communities)  Largest: $(s.largest_community_sz)  Giant: $(round(s.giant_component_frac*100; digits=1))%")
end

"""
    network_access_score(g, county_nodes; centrality=:pagerank) -> Vector{Float64}

Compute a network-based access score for each county.
`county_nodes` maps county index → list of provider node IDs in that county.
Score = sum of centrality values for providers in county (normalised by county population).
"""
function network_access_score(g::ReferralNetwork,
                               county_nodes::Vector{Vector{Int}};
                               centrality::Symbol = :pagerank)
    cent = centrality == :pagerank   ? pagerank(g) :
           centrality == :betweenness? betweenness_centrality(g) :
           centrality == :eigenvector? eigenvector_centrality(g) :
           degree_centrality(g)

    [isempty(nodes) ? 0.0 : sum(cent[nodes]) for nodes in county_nodes]
end

"""
    isolation_index(g, community_labels, group_a, group_b) -> Float64

Exposure index (Bell 1954) adapted for provider networks:
  P(group_a member meets group_b member in a shared community)

In referral context: probability that a patient referred from group_a provider
ends up at a group_b provider.
"""
function isolation_index(g          ::ReferralNetwork,
                          group_a    ::Vector{Int},
                          group_b    ::Vector{Int})::Float64
    n_a = length(group_a)
    n_a == 0 && return 0.0

    total = 0.0
    for v in group_a
        out_row = g.adj[v, :]
        total_v = sum(out_row)
        total_v < 1e-12 && continue
        # Fraction of v's referrals going to group_b
        b_weight = sum(out_row[u] for u in group_b if u <= g.n; init=0.0)
        total   += b_weight / total_v
    end
    total / n_a
end

"""
    fragmentation_index(g) -> Float64

Network fragmentation: proportion of pairs with no connecting path.
F = 1 - Σ n_c(n_c-1) / [n(n-1)]  where n_c = component size.
F = 0 → fully connected; F = 1 → fully disconnected.
"""
function fragmentation_index(g::ReferralNetwork)::Float64
    n       = g.n
    n == 0  && return 0.0
    n == 1  && return 0.0
    visited = falses(n)
    comp_sizes = Int[]
    for start in 1:n
        visited[start] && continue
        # BFS
        queue = [start]; head = 1; sz = 0
        while head <= length(queue)
            v = queue[head]; head += 1
            visited[v] && continue
            visited[v] = true; sz += 1
            for u in union(g.adj[v,:].nzind, g.adj[:,v].nzind)
                !visited[u] && push!(queue, u)
            end
        end
        push!(comp_sizes, sz)
    end
    numer = sum(s * (s-1) for s in comp_sizes)
    1.0 - numer / (n * (n-1))
end
