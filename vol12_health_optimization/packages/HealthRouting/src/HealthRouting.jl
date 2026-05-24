module HealthRouting

using Statistics, LinearAlgebra, Random
using JuMP, HiGHS

include("tsp.jl")
include("vrp.jl")
include("emergency.jl")
include("report.jl")

export TSPResult, tsp_nn, tsp_two_opt, tsp_exact_mtz, tsp_total_distance
export VRPResult, vrp_cw, vrp_route_distance
export EmergencyResult, mexclp, dispatch_assignment, erlang_c
export RoutingReport, routing_report, print_routing_report

end
