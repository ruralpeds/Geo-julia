"""
    Geostatistics

Kriging, variography, and spatial prediction for healthcare geospatial analysis.

## Features
- Empirical and fitted variogram (semivariogram) curves
- Ordinary Kriging (OK) — unbiased linear spatial prediction
- Universal Kriging (UK) — kriging with polynomial drift
- Co-kriging — multivariate prediction using auxiliary variables
- Block kriging — upscaling point predictions to area aggregates
- Cross-validation and diagnostic plots
- Uncertainty quantification via kriging variance

## Usage

```julia
using Geostatistics

# Load training data
x_train = [0 0; 1 1; 2 0; 3 1]  # Coordinates
z_train = [10.5, 12.3, 11.0, 13.2]  # Values (e.g., provider density)

# Fit variogram
coords = (x_train[:, 1], x_train[:, 2])
vario = empirical_variogram(coords, z_train; lags=10, maxlag=3.0)
model = fit_variogram(vario)

# Predict at new locations
x_pred = [0.5 0.5; 1.5 1.5]
pred_coords = (x_pred[:, 1], x_pred[:, 2])
result = ordinary_kriging(z_train, coords, pred_coords, model)

println("Predictions: \$(result.predictions)")
println("Uncertainties: \$(sqrt.(result.variances))")
```

## References
- Matheron, G. (1963). Principles of geostatistics. *Economic Geology*, 58(8).
- Chilès, J. & Delfiner, P. (2012). *Geostatistics: Modeling spatial uncertainty*. Wiley.
- Cressie, N. (1991). *Statistics for spatial data*. Wiley.
"""

module Geostatistics

using LinearAlgebra
using Statistics
using StatsBase
using Distributions
using SpecialFunctions
using Distances
using NearestNeighbors
using Random

# Data structures
include("types.jl")

# Variography
include("variography/empirical.jl")
include("variography/fitting.jl")
include("variography/models.jl")

# Kriging
include("kriging/ordinary.jl")
include("kriging/batch.jl")  # Batch kriging optimization (Phase 2)
include("kriging/vectorized_distances.jl")  # Vectorized distance computation (Phase 2)
include("kriging/universal.jl")
include("kriging/cokriging.jl")
include("kriging/block.jl")
include("kriging/validation.jl")
include("kriging/utils.jl")

# Exports
export
    # Data structures
    VariogramModel, KrigingResult,
    # Empirical variogram
    empirical_variogram, semivariogram, variogram_cloud,
    # Model fitting
    fit_variogram, fit_variogram_wls, fit_variogram_ml,
    # Variogram models
    Nugget, Spherical, Exponential, Matérn, Gaussian,
    # Kriging
    ordinary_kriging, ordinary_kriging_batch, kriging_variance, kriging_weights,
    universal_kriging,
    cokriging,
    block_kriging,
    # Vectorized distance computation (Phase 2 optimization)
    pairwise_distances_vectorized, pairwise_distances_haversine_vectorized,
    distance_matrix_from_coords, nearest_k_indices_vectorized, distance_subset_vectorized,
    # Validation & diagnostics
    cross_validate, leave_one_out, block_cross_validate,
    rmse, mae, smape

end
