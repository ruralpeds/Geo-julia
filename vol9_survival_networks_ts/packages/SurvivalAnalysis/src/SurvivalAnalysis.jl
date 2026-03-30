"""
    SurvivalAnalysis

Pure-Julia survival analysis for healthcare data.

# Exports
- Kaplan-Meier (`kaplan_meier`, `KMResult`, `km_predict`)
- Nelson-Aalen (`nelson_aalen`, `NAResult`)
- Log-rank / Wilcoxon tests (`logrank_test`, `LogRankResult`)
- Cox PH (`cox_fit`, `CoxModel`, `cox_predict`, `cox_summary`)
- Parametric AFT (`parametric_fit`, `ParametricModel`, `parametric_predict`, `parametric_survival`)
- Competing risks (`cumulative_incidence`, `CIFResult`, `cif_at`, `fine_gray_fit`)
- Reports (`survival_report`, `SurvivalReport`, `print_survival_report`)
"""
module SurvivalAnalysis

using Statistics, LinearAlgebra, Random

include("estimators.jl")
include("cox.jl")
include("parametric.jl")
include("competing.jl")
include("report.jl")

export
    # Estimators
    kaplan_meier, KMResult, km_predict,
    nelson_aalen, NAResult,
    logrank_test, LogRankResult,
    # Cox
    cox_fit, CoxModel, cox_predict, cox_summary,
    # Parametric
    parametric_fit, ParametricModel, parametric_predict, parametric_survival,
    # Competing risks
    cumulative_incidence, CIFResult, cif_at, cif_summary,
    fine_gray_fit, FineGrayModel, fg_predict_cif,
    # Report
    survival_report, SurvivalReport, print_survival_report

end  # module
