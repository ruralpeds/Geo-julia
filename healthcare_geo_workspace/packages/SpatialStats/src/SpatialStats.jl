"""
    SpatialStats

A Julia package providing spatial statistics and spatial econometrics methods
comparable to Python's PySAL (esda + spreg) and R's spdep + spatialreg.

Covers spatial weights construction, global and local autocorrelation
statistics, maximum-likelihood spatial regression models, and BYM Bayesian
disease mapping — all using native Julia with no Python/R dependency.
"""
module SpatialStats

using SparseArrays, LinearAlgebra, Statistics, Random
using DataFrames, GeoInterface
using NearestNeighbors
using Distributions
using Optim

include("weights/spatial_weights.jl")
include("autocorrelation/morans.jl")
include("autocorrelation/lisa.jl")
include("autocorrelation/getis.jl")
include("regression/ols_diagnostics.jl")
include("regression/spatial_lag.jl")
include("regression/spatial_error.jl")
include("regression/spatial_durbin.jl")

export
    # Types
    SpatialWeights,
    MoranResult,
    LISAResult,
    SpatialRegResult,

    # Weights constructors
    queen_weights,
    rook_weights,
    knn_weights,
    distance_weights,
    normalize!,

    # Global autocorrelation
    moran,
    geary,
    getis_ord,

    # Local autocorrelation
    lisa,
    g_local,

    # Spatial regression
    lm_spatial,
    slm,
    sem,
    sdm,

    # Utilities
    haversine_km,
    lm_tests

end  # module SpatialStats
