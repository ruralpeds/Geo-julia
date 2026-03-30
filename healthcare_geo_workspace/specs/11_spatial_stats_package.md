# CLAUDE CODE SPECIFICATION: SpatialStats.jl Bootstrap
# File: specs/11_spatial_stats_package.md
# Vol 2 Chapter 14.3

## Task
Initialize a new Julia package called SpatialStats.jl that will become
the Julia equivalent of PySAL's esda and spreg modules.
This is a greenfield package creation, not a modification of existing code.

## Step 1: Generate Package Scaffold
```
julia -e 'import Pkg; Pkg.generate("SpatialStats")'
```

## Step 2: Project.toml Dependencies
Add: SparseArrays (stdlib), LinearAlgebra (stdlib), Statistics (stdlib),
DataFrames, GeoInterface, GeoDataFrames, Distributions, Optim, Turing,
NearestNeighbors, BenchmarkTools, Test

## Step 3: Implement SpatialWeights type
Create src/weights/spatial_weights.jl.
Implement the SpatialWeights struct with fields:
  W::SparseMatrixCSC{Float64,Int}, n::Int, style::Symbol,
  transform::Symbol, island_count::Int, mean_neighbors::Float64
Implement queen_weights() constructor using GeoInterface.intersects().
Implement knn_weights() constructor using NearestNeighbors.jl.
Implement normalize!() to row-standardize the sparse weights matrix.
Test with 50 synthetic polygons; verify row sums == 1.0.

## Step 4: Implement Moran's I
Create src/autocorrelation/morans.jl.
Implement moran() returning a MoranResult struct.
Support both :analytical and :permutation inference methods.
Permutation method must use shuffle!() in-place to avoid allocation.
Target: 10,000 permutations on n=3,000 in < 10 seconds on M-series Mac.

## Step 5: Implement LISA
Create src/autocorrelation/lisa.jl.
Implement lisa() returning a LISAResult struct.
Permutation test must be location-specific (conditional randomisation at each i).
Cluster classification: HH (z_i > 0, lag_i > 0), LL (<0, <0),
HL (>0, <0), LH (<0, >0), NS (not significant).
Add a plot_lisa() function using GeoMakie to render LISA cluster map.

## Step 6: Implement Spatial Regression
Create src/regression/spatial_lag.jl (SLM via ML, Ord 1975 eigenvalue approach)
Create src/regression/spatial_error.jl (SEM via ML)
Create src/regression/spatial_durbin.jl (SDM by augmenting X with WX)
Create src/regression/ols_diagnostics.jl (OLS + LM-lag, LM-error tests)
All regression functions return a SpatialRegResult struct.

## Step 7: Tests
Write test cases for:
- Perfect clustering input → Moran's I ≈ 1.0 (p < 0.05)
- Checkerboard pattern → Moran's I < 0
- Random permutation of values → |I| < 0.2 (stochastic)
- LISA HH correctly identified on synthetic clustered data
- queen_weights returns row sums == 1.0 for a 5×5 grid
- SLM: ρ̂ in (-1, 1) and AIC finite
- SEM: λ̂ in (-1, 1) and AIC finite

## Step 8: Documentation
Write Documenter.jl docstrings for all exported functions.
Create a tutorial notebook demonstrating SpatialStats.jl on
North Dakota county CVD mortality data using AHRF + Census TIGER.
