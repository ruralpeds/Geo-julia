"""
    GeoJulia

Unified entry point for the Geo-Julia healthcare geospatial analytics platform.
Provides access to all 26 domain packages across 14 volumes through a single module.

# Volume Index
- **Vol 5**: Machine Learning (`HealthcareML`, `NetworkHealth`, `TemporalHealth`)
- **Vol 6**: Advanced Inference (`CausalHealth`, `GaussianProcessHealth`)
- **Vol 7**: Deep Learning & Bayesian (`DeepHealth`, `BayesianHealth`)
- **Vol 8**: Equity & Spatial (`SpatialRegression`, `HealthEquity`, `ConformalHealth`)
- **Vol 9**: Survival & Time Series (`SurvivalAnalysis`, `EpidemicNetworks`, `TimeSeriesHealth`)
- **Vol 10**: Geostatistics (`GeostatHealth`, `SpatialPointPatterns`, `DiseaseMapping`)
- **Vol 11**: Causal Inference (`CausalInference`, `PolicyEval`, `SpatialCausal`)
- **Vol 12**: Optimization (`FacilityLocation`, `HealthRouting`, `ResourceAllocation`)
- **Vol 13**: Epidemiology (`InfectiousDisease`, `SurveillanceSystems`, `HealthIntelligence`)

# Quick Start
```julia
using GeoJulia

# Disease surveillance pipeline
result = sir(1_000_000, 10, 0.3, 0.1; t_end=200.0)
alerts = cusum(result.I; k=1.0, h=5.0)

# Spatial analysis
vario = empirical_variogram(coords, values)
vm = fit_variogram(vario; model=:spherical)
predictions = ok_predict(ordinary_kriging(values, coords, vm), new_coords)

# Causal policy evaluation
ps_model = ps_fit(treatment, covariates)
effect = aipw_ate(treatment, outcome, ps_predict(ps_model, covariates), covariates)

# Facility optimization
facilities = p_median(demand_pts, candidate_pts, 5; weights=population)
```
"""
module GeoJulia

# ============================================================
# Vol 5: ML Production
# ============================================================
module ML
    using Reexport
    include("vol5_imports.jl")
end

# ============================================================
# Vol 6: Advanced Inference
# ============================================================
module Inference
    using Reexport
    include("vol6_imports.jl")
end

# ============================================================
# Vol 7: Deep Learning & Bayesian
# ============================================================
module DeepBayes
    using Reexport
    include("vol7_imports.jl")
end

# ============================================================
# Vol 8: Equity & Spatial Analysis
# ============================================================
module Equity
    using Reexport
    include("vol8_imports.jl")
end

# ============================================================
# Vol 9: Survival, Networks, Time Series
# ============================================================
module SurvivalTS
    using Reexport
    include("vol9_imports.jl")
end

# ============================================================
# Vol 10: Geostatistics & Mapping
# ============================================================
module Geostat
    using Reexport
    include("vol10_imports.jl")
end

# ============================================================
# Vol 11: Causal Inference & Policy
# ============================================================
module Causal
    using Reexport
    include("vol11_imports.jl")
end

# ============================================================
# Vol 12: Health Optimization
# ============================================================
module Optimization
    using Reexport
    include("vol12_imports.jl")
end

# ============================================================
# Vol 13: Spatial Epidemiology
# ============================================================
module Epidemiology
    using Reexport
    include("vol13_imports.jl")
end

# ============================================================
# Top-level convenience re-exports (most commonly used)
# ============================================================

# Epidemic modeling
using .Epidemiology: sir, seir, sir_stochastic, SIRResult, SEIRResult,
    spatial_sir, r0_from_growth, r0_from_params, herd_immunity_threshold,
    cusum, ewma, farrington, temporal_scan, sensitivity_specificity,
    composite_risk_score, health_needs_index, lof, isolation_forest

# Geostatistics
using .Geostat: empirical_variogram, fit_variogram, variogram_value,
    simple_kriging, ordinary_kriging, universal_kriging,
    sk_predict, ok_predict, uk_predict, kriging_loo_cv,
    sgs_simulate, smr, bym_fit, eb_smooth, spatial_scan,
    kde2d, ripley_k, dbscan

# Survival & Time Series
using .SurvivalTS: kaplan_meier, cox_fit, cox_predict, logrank_test,
    parametric_fit, arima_fit, auto_arima, kalman_filter, dlm_fit,
    build_graph, sir_model, seir_model, pagerank, dijkstra

# Causal Inference
using .Causal: ps_fit, ps_predict, ipw_ate, aipw_ate, nn_match,
    did_2x2, event_study, rdd_fit, synth_control,
    spatial_did, conley_se, geo_iv_2sls

# Optimization
using .Optimization: p_median, set_cover, mclp, cap_flp,
    tsp_nn, tsp_two_opt, vrp_cw, mexclp,
    bip_branch_bound, value_iteration, policy_iteration

# ML & Deep Learning
using .ML: fit!, predict, predict_proba, cross_validate, shap_values
using .DeepBayes: build_mlp, train!, sample_chains, vi_fit

# Spatial & Equity
using .Equity: gwr_fit, spatial_lag_fit, spatial_error_fit,
    fairness_audit, gini_coefficient, conformal_fit, conformal_predict

# Gaussian Processes
using .Inference: gp_fit, gp_predict, optimize_hyperparams!

# Re-export all
export sir, seir, sir_stochastic, SIRResult, SEIRResult,
    spatial_sir, r0_from_growth, r0_from_params, herd_immunity_threshold,
    cusum, ewma, farrington, temporal_scan, sensitivity_specificity,
    composite_risk_score, health_needs_index, lof, isolation_forest,
    empirical_variogram, fit_variogram, variogram_value,
    simple_kriging, ordinary_kriging, universal_kriging,
    sk_predict, ok_predict, uk_predict, kriging_loo_cv,
    sgs_simulate, smr, bym_fit, eb_smooth, spatial_scan,
    kde2d, ripley_k, dbscan,
    kaplan_meier, cox_fit, cox_predict, logrank_test,
    parametric_fit, arima_fit, auto_arima, kalman_filter, dlm_fit,
    build_graph, sir_model, seir_model, pagerank, dijkstra,
    ps_fit, ps_predict, ipw_ate, aipw_ate, nn_match,
    did_2x2, event_study, rdd_fit, synth_control,
    spatial_did, conley_se, geo_iv_2sls,
    p_median, set_cover, mclp, cap_flp,
    tsp_nn, tsp_two_opt, vrp_cw, mexclp,
    bip_branch_bound, value_iteration, policy_iteration,
    fit!, predict, predict_proba, cross_validate, shap_values,
    build_mlp, train!, sample_chains, vi_fit,
    gwr_fit, spatial_lag_fit, spatial_error_fit,
    fairness_audit, gini_coefficient, conformal_fit, conformal_predict,
    gp_fit, gp_predict, optimize_hyperparams!

end # module GeoJulia
