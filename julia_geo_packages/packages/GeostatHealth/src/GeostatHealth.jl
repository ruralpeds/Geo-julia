"""
    GeostatHealth

Pure-Julia geostatistics for healthcare spatial interpolation.

Exports: empirical_variogram, cloud_variogram, fit_variogram,
VariogramModel, variogram_value, covariance_value, variogram_summary,
variogram_plot_text, EmpiricalVariogram, CloudVariogram;
simple_kriging, sk_predict, ordinary_kriging, ok_predict,
ok_predict_local, kriging_grid, universal_kriging, uk_predict,
kriging_loo_cv;
sgs_simulate, sgs_uncertainty;
geostat_report, GeostatReport, print_geostat_report;
RasterGrid, create_grid, BoundingBox, points_in_bbox, zonal_statistics,
UncertaintySurface, uncertainty_surface,
synthetic_worldpop_grid, synthetic_ghsl_grid
"""
module GeostatHealth

using Statistics, LinearAlgebra, Random

include("variogram.jl")
include("kriging.jl")
include("simulation.jl")
include("report.jl")
include("raster.jl")

export
    # Variogram
    empirical_variogram, EmpiricalVariogram,
    cloud_variogram, CloudVariogram,
    fit_variogram, VariogramModel, variogram_value, covariance_value,
    variogram_summary, variogram_plot_text,
    # Kriging
    simple_kriging, SimpleKrigingResult, sk_predict,
    ordinary_kriging, OrdinaryKrigingResult, ok_predict, ok_predict_local,
    kriging_grid,
    universal_kriging, UniversalKrigingResult, uk_predict,
    kriging_loo_cv,
    # Simulation
    sgs_simulate, sgs_uncertainty,
    # Report
    geostat_report, GeostatReport, print_geostat_report,
    # Raster
    RasterGrid, create_grid,
    BoundingBox, points_in_bbox, zonal_statistics,
    UncertaintySurface, uncertainty_surface,
    synthetic_worldpop_grid, synthetic_ghsl_grid

end
