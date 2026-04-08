"""
    NetworkHealth

Pure-Julia healthcare network analysis and epidemic modelling.

# Exports
Graph: `build_graph`, `HealthGraph`, `degree_centrality`, `strength_centrality`,
       `betweenness_centrality`, `pagerank`, `clustering_coefficient`,
       `bfs`, `dijkstra`, `weakly_connected_components`

Epidemic: `sir_model`, `SIRResult`, `seir_model`, `SEIRResult`,
          `seird_model`, `SEIRDResult`, `estimate_r0`, `network_sir`

Facility: `patient_flow_analysis`, `PatientFlowResult`,
          `catchment_area`, `CatchmentResult`,
          `referral_centrality`, `network_vulnerability`

Report: `network_report`, `NetworkReport`, `print_network_report`
"""
module NetworkHealth

using Statistics, LinearAlgebra, Random

include("graph.jl")
include("epidemic.jl")
include("facility_network.jl")
include("report.jl")

export
    # Graph
    build_graph, HealthGraph,
    degree_centrality, strength_centrality,
    betweenness_centrality, pagerank,
    clustering_coefficient, bfs, dijkstra,
    weakly_connected_components,
    # Epidemic
    sir_model, SIRResult,
    seir_model, SEIRResult,
    seird_model, SEIRDResult,
    estimate_r0, network_sir,
    # Facility
    patient_flow_analysis, PatientFlowResult,
    catchment_area, CatchmentResult,
    referral_centrality, network_vulnerability,
    # Report
    network_report, NetworkReport, print_network_report

end  # module
