# CLAUDE CODE SPECIFICATION: Spatial Analysis Engine
# File: specs/03_spatial_analysis.md

## Task
Implement the complete spatial analysis engine in src/analysis/.

## Files to Create

### src/analysis/weights.jl
Implement spatial weights matrix construction:

- build_queen_weights(geoms): Queen contiguity weights from polygon geometries.
  Use GeoInterface.intersects() for adjacency testing.
  Return row-standardized Matrix{Float64}.

- build_knn_weights(coords, k=5): K-nearest neighbor weights.
  coords is n×2 matrix of lat/lon centroids.
  Use haversine distance. Return row-standardized matrix.

- build_distance_band_weights(coords; bandwidth_km=50.0):
  Binary distance band weights. All pairs within bandwidth_km get weight 1.
  Return row-standardized matrix.

- build_inverse_distance_weights(coords; power=1.0):
  Weights proportional to 1/d^power. Return row-standardized matrix.

### src/analysis/autocorrelation.jl
Implement spatial autocorrelation statistics:

- compute_morans_i(values, W; permutations=999):
  Returns NamedTuple (I, expected_I, variance, z_score, p_value)

- compute_geary_c(values, W; permutations=999):
  Geary's C statistic. C=1 is spatial randomness, C<1 is clustering.

- lisa_clusters(values, W; permutations=999, alpha=0.05):
  Returns Vector{String} with HH/LL/HL/LH/NS for each location.

- getis_ord_g(values, W; permutations=999):
  Getis-Ord G* hotspot analysis. Returns z-scores.

### src/analysis/accessibility.jl
Implement healthcare accessibility measures:

- two_step_fca(providers, pop_locs, catchment_km):
  Standard 2SFCA. Euclidean distance.

- e2sfca(providers, pop_locs, catchment_km; decay=:gaussian, sigma_km=15.0):
  Enhanced 2SFCA with distance decay.
  Supported decay functions: :gaussian, :linear, :inverse, :kernel

- network_2sfca(providers, pop_locs, travel_time_matrix, catchment_min):
  2SFCA using pre-computed network travel time matrix (from OSRM).

- gravity_accessibility(providers, pop_locs; beta=2.0):
  Gravity model accessibility index: A_i = Σ_j S_j / d_ij^beta

### src/analysis/regression.jl
Implement spatial regression methods:

- spatial_lag_model(y, X, W): Spatial autoregressive model.
  Returns NamedTuple (coefs, rho, log_likelihood, AIC)

- spatial_error_model(y, X, W): Spatial error model.
  Returns NamedTuple (coefs, lambda, log_likelihood, AIC)

- gwr(y, X, coords; bandwidth_km=50.0, kernel=:bisquare):
  Geographically weighted regression.
  Returns DataFrame with local coefficients and local R².

## Testing Requirements
For each function, add tests in test/runtests.jl:
- Test with synthetic data where true answers are known
- Test edge cases (all same values, single unit, disconnected graph)
- Benchmark with @btime for n=3000 counties target performance < 5 seconds
