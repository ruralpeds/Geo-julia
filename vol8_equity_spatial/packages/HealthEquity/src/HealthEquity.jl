"""
    HealthEquity

Algorithmic fairness and health equity analytics for healthcare data.
Chapter 48 — Open-Source Healthcare GIS Textbook in Julia.

Provides pure-Julia implementations of:
- Fairness metrics: demographic parity, equalized odds, calibration by group
- Inequality indices: Theil, Gini, concentration index, dissimilarity
- Disparity decomposition: Oaxaca-Blinder, between/within Theil
- Bias mitigation: post-processing threshold optimisation, Platt calibration by group
- Reporting: EquityReport with disparity waterfall data
"""
module HealthEquity

using Statistics, LinearAlgebra, DataFrames, Random, Distributions

include("metrics.jl")
include("disparities.jl")
include("fairness.jl")
include("report.jl")

export
    # Fairness metrics
    demographic_parity, equalized_odds, calibration_gap,
    FairnessAudit, fairness_audit,
    # Inequality indices
    gini_coefficient, theil_index, concentration_index,
    dissimilarity_index, isolation_exposure,
    # Disparity decomposition
    oaxaca_blinder, theil_decompose,
    OaxacaResult, TheilDecomposition,
    # Bias mitigation
    threshold_sweep, equalise_tpr, equalise_fpr,
    platt_calibrate_by_group, apply_group_thresholds,
    # Report
    EquityReport, equity_report

end # module
