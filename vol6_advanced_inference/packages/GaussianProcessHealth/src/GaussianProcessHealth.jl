"""
    GaussianProcessHealth

Gaussian Process regression for spatial healthcare access interpolation
with full uncertainty quantification.
Chapter 44 — Julia Healthcare GIS Textbook, Vol 6.

# Background
GP regression provides a principled Bayesian framework for spatial
interpolation. For healthcare access surfaces, the GP posterior gives
both a mean prediction AND credible intervals — crucial for policy:
"We are 95% confident that access in this county lies in [0.002, 0.008]."

# Exports
- `GPKernel`, `SquaredExponential`, `Matern32`, `Matern52`, `RationalQuadratic`
- `SphericalKernel`, `OrnsteinUhlenbeck` (for geographic distance kernels)
- `GPModel`, `gp_fit`, `gp_predict`, `gp_log_marginal_likelihood`
- `optimize_hyperparams!` (type-II ML via gradient-free optimisation)
- `spatial_gp_surface`, `uncertainty_map`
- `SparseGP`, `sparse_gp_fit` (inducing points for n > 500)
"""
module GaussianProcessHealth

using DataFrames, LinearAlgebra, Statistics, Random, Distributions
import KernelFunctions
import AbstractGPs
import Optim

export GPKernel, SquaredExponential, Matern32, Matern52, RationalQuadratic
export OrnsteinUhlenbeck, CompositeKernel
export GPModel, gp_fit, gp_predict, gp_log_marginal_likelihood
export optimize_hyperparams!, marginal_likelihood_surface
export spatial_gp_surface, uncertainty_map
export SparseGP, sparse_gp_fit, sparse_gp_predict

include("kernels.jl")
include("gp_regression.jl")
include("sparse_gp.jl")
include("spatial.jl")

end  # module GaussianProcessHealth
