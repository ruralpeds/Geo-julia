module PolicyEval

using Statistics, LinearAlgebra, Random
using GLM, Distributions, StatsBase, DataFrames, Optim

include("did.jl")
include("synth_control.jl")
include("rdd.jl")
include("report.jl")

export DIDResult, did_2x2, staggered_did, event_study, parallel_trends_test
export SynthResult, synth_control, synth_gaps, synth_placebo
export RDDResult, rdd_fit, rdd_summary, mccrary_test
export PolicyReport, policy_report, print_policy_report

end
