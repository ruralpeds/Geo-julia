"""
    HealthIntelligence

Population health analytics for the Geo-Julia healthcare textbook.

Methods:
- **Composite risk score** — weighted z-score aggregation across health domains
- **Health Needs Index** — access + deprivation + disease burden composite
- **Risk-adjusted outcomes** — SMR with Byar CIs, high/low outlier flagging
- **LOF anomaly detection** — Local Outlier Factor (Breunig et al. 2000)
- **Isolation Forest** — randomised path-length anomaly scoring (Liu et al. 2008)
- **Health event anomaly** — z-score based stream monitoring
- **k-Means segmentation** — Lloyd's algorithm with k-means++ and silhouette
- **Predictive risk** — regularised logistic regression, Brier, C-statistic
"""
module HealthIntelligence

using Statistics, LinearAlgebra, Random
using StatsBase: zscore, quantile as sb_quantile
using Distributions: Poisson, quantile as dist_quantile, confint

include("risk_scoring.jl")
include("anomaly.jl")
include("population.jl")
include("report.jl")

export
    # Risk scoring
    RiskScoreResult, composite_risk_score,
    HealthNeedsIndex, health_needs_index,
    risk_adjusted_outcomes,
    # Anomaly detection
    LOFResult, lof,
    IForestResult, isolation_forest,
    health_event_anomaly,
    # Population analytics
    KMeansResult, kmeans,
    PredictiveRiskResult, predictive_risk,
    # Report
    print_intelligence_report

end # module
