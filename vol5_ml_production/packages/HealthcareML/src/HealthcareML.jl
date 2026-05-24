"""
    HealthcareML

Machine learning for healthcare access analysis.
Chapter 35 — Julia Healthcare GIS Textbook, Vol 5.

# Exports
- `AccessModel`, `fit!`, `predict`, `predict_proba`
- `DecisionTreeAccess`, `RandomForestAccess`, `GradientBoostAccess`
- `cross_validate`, `tune_hyperparameters`
- `shap_values`, `permutation_importance`, `partial_dependence`
- `AccessFeatures`, `build_features`
- `HealthcareMLReport`, `generate_report`
"""
module HealthcareML

using DataFrames, Statistics, LinearAlgebra, Random, StatsBase, Distributions, Tables
import DecisionTree

export AccessModel, fit!, predict, predict_proba
export DecisionTreeAccess, RandomForestAccess, GradientBoostAccess, RidgeAccess
export cross_validate, tune_hyperparameters
export shap_values, permutation_importance, partial_dependence
export AccessFeatures, build_features
export HealthcareMLReport, generate_report
export ModelComparison, compare_models
export calibration_curve, brier_score

include("features.jl")
include("trees.jl")
include("ensemble.jl")
include("explainability.jl")
include("validation.jl")
include("report.jl")

end  # module HealthcareML
