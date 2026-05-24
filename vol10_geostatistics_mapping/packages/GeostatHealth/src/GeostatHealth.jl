"""
    GeostatHealth

Geostatistics for healthcare spatial interpolation, powered by GeoStats.jl.

Exports: empirical_variogram, fit_variogram, VariogramModel, variogram_value,
covariance_value, variogram_summary, EmpiricalVariogram;
simple_kriging, sk_predict, ordinary_kriging, ok_predict,
universal_kriging, uk_predict, kriging_loo_cv;
sgs_simulate, sgs_uncertainty;
geostat_report, GeostatReport, print_geostat_report
"""
module GeostatHealth

using Statistics, LinearAlgebra, Random
using GeoStats
using Meshes
using GeoTables
using Variography
using GeoStatsModels

include("variogram.jl")
include("kriging.jl")
include("simulation.jl")
include("report.jl")

export
    # Variogram
    empirical_variogram, EmpiricalVariogram,
    fit_variogram, VariogramModel, variogram_value, covariance_value,
    variogram_summary,
    # Kriging
    simple_kriging, SimpleKrigingResult, sk_predict,
    ordinary_kriging, OrdinaryKrigingResult, ok_predict,
    universal_kriging, UniversalKrigingResult, uk_predict,
    kriging_loo_cv,
    # Simulation
    sgs_simulate, sgs_uncertainty,
    # Report
    geostat_report, GeostatReport, print_geostat_report

end
