"""
    CausalHealth

Causal inference methods for healthcare policy evaluation.
Chapter 43 — Julia Healthcare GIS Textbook, Vol 6.

Implements the core econometric toolkit for evaluating healthcare policies:
  - Difference-in-Differences (DiD) with parallel trends testing
  - Synthetic Control Method (Abadie, Diamond & Hainmueller 2010)
  - Instrumental Variables / 2SLS (for endogenous access measures)
  - Regression Discontinuity Design (sharp + fuzzy RD)
  - Event Study plots for dynamic treatment effects

All methods include standard errors (HC3 / Newey-West), effect size estimates,
and pre-trend falsification tests.
"""
module CausalHealth

using DataFrames, Statistics, LinearAlgebra, Random, StatsBase, Distributions

export DiDResult, did_estimate, parallel_trends_test, event_study
export SyntheticControlResult, synthetic_control, synth_weights
export IVResult, iv_2sls, first_stage_f, hausman_test
export RDResult, rd_estimate, rd_bandwidth, rdd_plot_data
export CausalReport, causal_summary

include("did.jl")
include("synthetic_control.jl")
include("iv.jl")
include("rdd.jl")
include("report.jl")

end  # module CausalHealth
