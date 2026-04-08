"""
    ConformalHealth

Distribution-free uncertainty quantification for healthcare predictions.
Chapter 50 — Open-Source Healthcare GIS Textbook in Julia.

Provides pure-Julia implementations of:
- Split conformal prediction (Papadopoulos 2002; Vovk 2005)
- Jackknife+ and CV+ conformal intervals (Barber et al. 2021)
- Conformalized Quantile Regression — CQR (Romano, Patterson & Candès 2019)
- Adaptive Prediction Sets — RAPS (Angelopoulos et al. 2021)
- Probability calibration: temperature scaling, isotonic regression

All methods provide finite-sample marginal coverage guarantees:
  P(y_{n+1} ∈ C(x_{n+1})) ≥ 1 - α
"""
module ConformalHealth

using Statistics, LinearAlgebra, Random, DataFrames

include("split_conformal.jl")
include("jackknife.jl")
include("cqr.jl")
include("classification.jl")
include("calibration.jl")

export
    # Split conformal
    ConformalRegressor, conformal_fit, conformal_predict,
    conformal_coverage, ConformalResult,
    # Jackknife+
    JackknifeResult, jackknife_plus,
    # CQR
    CQRModel, cqr_fit, cqr_predict,
    # Classification
    AdaptivePredictionSet, aps_fit, aps_predict,
    conformal_classify,
    # Calibration
    temperature_scaling, isotonic_calibrate,
    CalibrationResult, calibration_error,
    reliability_diagram

end # module
