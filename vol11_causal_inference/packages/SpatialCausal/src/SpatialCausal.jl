module SpatialCausal

using Statistics, LinearAlgebra, Random
using GLM, Distributions, NearestNeighbors, DataFrames

include("spatial_did.jl")
include("conley.jl")
include("geo_iv.jl")
include("report.jl")

export SpatialDIDResult, spatial_did, spillover_decomposition
export ConleyResult, conley_se, conley_summary
export GeoIVResult, geo_iv_2sls, iv_summary, weak_instrument_test
export SpatialCausalReport, spatial_causal_report, print_spatial_causal_report

end
