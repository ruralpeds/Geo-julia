"""
    SpatialRegression

Local and global spatial regression models for geographically structured data.
Chapter 49 — Open-Source Healthcare GIS Textbook in Julia.

Provides pure-Julia implementations of:
- GWR: Geographically Weighted Regression with Gaussian/bisquare kernels
- Spatial lag model: Y = ρWY + Xβ + ε (endogenous spatial lag)
- Spatial error model: Y = Xβ + u, u = λWu + ε (spatially correlated errors)
- Geographically Weighted Random Forest (GW-RF)
- Diagnostics: Moran's I on residuals, LM tests, Breusch-Pagan
"""
module SpatialRegression

using LinearAlgebra, Statistics, Random, DataFrames
import Distances
import Optim

include("gwr.jl")
include("spatial_lag.jl")
include("spatial_error.jl")
include("gwrf.jl")
include("diagnostics.jl")

export
    # GWR
    GWRModel, gwr_fit, gwr_predict,
    gwr_summary, bandwidth_aic,
    # Spatial lag
    SpatialLagModel, spatial_lag_fit,
    # Spatial error
    SpatialErrorModel, spatial_error_fit,
    # GW-RF
    GWRFModel, gwrf_fit, gwrf_predict,
    # Diagnostics
    moran_residuals, lm_lag_test, lm_error_test,
    spatial_breusch_pagan, SpatialDiagnostics, run_diagnostics

end # module
