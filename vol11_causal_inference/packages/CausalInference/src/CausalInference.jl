module CausalInference

using Statistics, LinearAlgebra, Random

include("propensity.jl")
include("ipw.jl")
include("matching.jl")
include("report.jl")

export PropensityModel, ps_fit, ps_predict, ps_trim, ps_overlap
export IPWResult, ipw_ate, aipw_ate, overlap_ate
export MatchResult, nn_match, att_matched, balance_table
export CausalReport, causal_report, print_causal_report

end
