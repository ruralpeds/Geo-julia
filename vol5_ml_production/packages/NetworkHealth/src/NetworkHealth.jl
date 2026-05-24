"""
    NetworkHealth

Provider referral network analysis for healthcare access.
Chapter 36 — Julia Healthcare GIS Textbook, Vol 5.

Models the healthcare provider referral ecosystem as a directed weighted graph:
  - Nodes: providers (hospitals, PCPs, specialists)
  - Edges: referral flows (weighted by volume)

# Exports

**Graph construction**
- `ReferralNetwork`, `from_dataframe`, `from_adjmatrix`

**Centrality**
- `degree_centrality`, `betweenness_centrality`, `closeness_centrality`
- `eigenvector_centrality`, `pagerank`

**Community detection**
- `louvain_communities`, `girvan_newman`, `label_propagation`

**Flow analysis**
- `max_flow`, `referral_concentration`, `herfindahl_index`

**Access metrics**
- `network_access_score`, `isolation_index`, `fragmentation_index`
"""
module NetworkHealth

using DataFrames, LinearAlgebra, SparseArrays, Statistics, StatsBase, Random
import Graphs
import SimpleWeightedGraphs

export ReferralNetwork, from_dataframe, from_adjmatrix, nv, ne, neighbors, degree
export degree_centrality, betweenness_centrality, closeness_centrality
export eigenvector_centrality, pagerank
export louvain_communities, label_propagation
export max_flow_bfs, referral_concentration, herfindahl_index
export network_access_score, isolation_index, fragmentation_index
export shortest_paths, diameter, average_path_length
export NetworkSummary, summarize

include("graph.jl")
include("centrality.jl")
include("community.jl")
include("flow.jl")
include("access_metrics.jl")

end  # module NetworkHealth
