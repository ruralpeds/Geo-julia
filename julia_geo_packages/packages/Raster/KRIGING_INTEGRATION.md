# Kriging → Raster Integration (Phase C, Days 14)

## Overview

`kriging_grid.jl` provides seamless integration between geostatistical kriging (from `Geostatistics.jl`) and raster-based spatial grids. This enables prediction and uncertainty quantification across regular spatial grids for healthcare geospatial analysis.

**Status:** ✅ Implemented
**Part of:** HealthcareGeo Ecosystem Build (40-day roadmap)

## Architecture

```
Raster/
├── src/
│   ├── types.jl                 # RasterGrid data structure
│   ├── Raster.jl                # Main module
│   ├── io/
│   │   ├── load_save.jl         # GeoTIFF I/O
│   │   ├── worldpop.jl          # WorldPop loaders
│   │   └── ghsl.jl              # GHSL loaders
│   └── analysis/
│       ├── kriging_grid.jl      # Kriging on grids (Phase C — Agent 2)
│       ├── fusion.jl            # Population fusion (Phase D — Agent 3)
│       └── validation.jl        # Cross-validation
└── test/
    └── test_kriging_grid.jl     # Kriging integration tests
```

## Core Functions

### Grid Creation

#### `create_regular_grid(bounds::NamedTuple, resolution_m::Float64)::RasterGrid`

Create a uniform latitude/longitude grid from bounds and resolution.

**Arguments:**
- `bounds::NamedTuple` — Bounding box with fields `(x_min, x_max, y_min, y_max)` or `(lon_min, lon_max, lat_min, lat_max)`
- `resolution_m::Float64` — Grid resolution in meters

**Returns:**
- `RasterGrid` with x and y coordinates (empty values, all zeros)

**Conversion:**
- 1 degree ≈ 111 km = 111,000 m
- resolution_deg = resolution_m / 111_000.0

**Example:**
```julia
bounds = (x_min=-120.0, x_max=-119.0, y_min=38.0, y_max=39.0)
grid = create_regular_grid(bounds, 1000.0)  # 1 km resolution
```

### Kriging on Grids

#### `ordinary_kriging_grid(z, coords, grid, model; n_neighbors=15)::RasterGrid`

Perform ordinary kriging on a regular grid.

**Arguments:**
- `z::Vector` — Observed values at training points
- `coords::Tuple` — (x, y) training coordinates
- `grid::RasterGrid` — Target grid with coordinates
- `model::VariogramModel` — Fitted variogram model from Geostatistics
- `n_neighbors::Int` — Local kriging neighborhood (default: 15)

**Returns:**
- `RasterGrid` with predictions and variances in `metadata["variances"]`

**Theory:**
Ordinary kriging provides unbiased minimum variance linear predictions:
- ẑ(x₀) = Σ λᵢ z(xᵢ)  (linear combination of nearby observations)
- σ²_OK(x₀) = sill - Σ λᵢ γ(h₀ᵢ) - μ  (kriging variance)

**Example:**
```julia
using Geostatistics, Raster

# Training data
coords = ([0.0, 1.0, 2.0], [0.0, 0.0, 0.0])
z = [5.0, 6.5, 5.2]

# Fit variogram
vario = empirical_variogram(coords, z)
model = fit_variogram(vario; model_type=:exponential)

# Create grid and predict
bounds = (x_min=-0.5, x_max=2.5, y_min=-0.5, y_max=0.5)
grid = create_regular_grid(bounds, 50000.0)
result_grid = ordinary_kriging_grid(z, coords, grid, model; n_neighbors=3)

# Access results
predictions = result_grid.data  # Kriging predictions (y×x matrix)
variances = result_grid.metadata["variances"]  # Kriging variances
```

#### `universal_kriging_grid(z, coords, grid, model; drift_order=1, n_neighbors=15)::RasterGrid`

Perform universal kriging on a regular grid with polynomial drift.

**Arguments:**
- `z::Vector` — Observed values
- `coords::Tuple` — (x, y) training coordinates
- `grid::RasterGrid` — Target grid
- `model::VariogramModel` — Fitted variogram model
- `drift_order::Int` — Polynomial drift order (1 = linear, 2 = quadratic)
- `n_neighbors::Int` — Local kriging neighborhood

**Returns:**
- `RasterGrid` with drift-adjusted predictions and drift_order in metadata

**Theory:**
Universal kriging removes spatial trends (drift) before kriging the residuals:
- Z(x) = m(x) + R(x)  (trend + residual)
- UK predicts both trend and residual component

**Use Cases:**
- Provider density increases with population density (linear trend in x)
- Disease risk changes across geographic gradient
- Healthcare access improves systematically toward urban centers

#### `block_kriging_grid(z, coords, blocks, grid, model; block_size=1.0, n_neighbors=15)::RasterGrid`

Perform block kriging on grid for area-level predictions.

**Arguments:**
- `z::Vector` — Observed values
- `coords::Tuple` — (x, y) training coordinates
- `blocks::Vector` — Block membership vector (can be empty)
- `grid::RasterGrid` — Target grid
- `model::VariogramModel` — Fitted variogram model
- `block_size::Float64` — Block size (width of square blocks)
- `n_neighbors::Int` — Local kriging neighborhood

**Returns:**
- `RasterGrid` with block-averaged predictions (lower variance than point kriging)

**Theory:**
Block kriging predicts the average value over a spatial block:
- σ²_BK(B) < σ²_OK(x₀)  (averaging reduces variance)
- Particularly useful for county-level or district-level predictions

**Use Cases:**
- Average provider density per county
- Region-level population estimates
- Healthcare access at administrative boundaries

#### `cokriging_grid(z_primary, z_auxiliary, coords, grid, model_p, model_cross; model_aux=model_p, n_neighbors=15)::RasterGrid`

Perform co-kriging on grid using auxiliary variable.

**Arguments:**
- `z_primary::Vector` — Primary variable (sparse, expensive)
- `z_auxiliary::Vector` — Auxiliary variable (abundant, cheap)
- `coords::Tuple` — (x, y) training coordinates
- `grid::RasterGrid` — Target grid
- `model_p::VariogramModel` — Primary variable variogram
- `model_cross::VariogramModel` — Cross-variogram
- `model_aux::VariogramModel` — Auxiliary variable model
- `n_neighbors::Int` — Local kriging neighborhood

**Returns:**
- `RasterGrid` with co-kriging predictions and auxiliary predictions in metadata

**Theory:**
Co-kriging leverages correlation with auxiliary variable:
- ẑ(x₀) = Σ λᵢ z_primary(xᵢ) + Σ μⱼ z_aux(xⱼ)
- Reduces prediction variance by incorporating auxiliary information

**Healthcare Example:**
```julia
# Primary: provider density (sparse, expensive to measure)
z_primary = [5.0, 6.5, 5.2]

# Auxiliary: population (abundant, from census)
z_auxiliary = [10000, 12000, 9500]

# Co-kriging improves provider predictions using population correlation
result_grid = cokriging_grid(z_primary, z_auxiliary, coords, grid,
                              model_p, model_cross; model_aux=model_aux,
                              n_neighbors=15)
```

### Utility Functions

#### `extract_raster_values(raster::RasterGrid, coords::Tuple)::Vector`

Sample raster values at arbitrary coordinates using nearest-neighbor interpolation.

**Arguments:**
- `raster::RasterGrid` — Source raster grid
- `coords::Tuple` — (x, y) coordinates to sample

**Returns:**
- `Vector` of interpolated values at coordinates

**Example:**
```julia
sample_coords = ([0.5, 1.5], [0.2, 0.3])
values = extract_raster_values(result_grid, sample_coords)
```

#### `reshape_predictions(predictions::Vector, grid::RasterGrid)::Matrix`

Reshape kriging predictions from linear to y×x matrix form.

**Arguments:**
- `predictions::Vector` — Linear array of predictions (n_x * n_y points)
- `grid::RasterGrid` — Grid with coordinate dimensions

**Returns:**
- `Matrix` in y×x ordering (n_y × n_x)

**Note:** Raster convention uses y-axis as rows, x-axis as columns. This function handles the coordinate ordering automatically.

#### `create_uncertainty_surface(variances::Vector, grid::RasterGrid)::RasterGrid`

Generate confidence interval surface from kriging variances.

**Arguments:**
- `variances::Vector` — Kriging variances from predictions
- `grid::RasterGrid` — Target grid

**Returns:**
- `RasterGrid` with 95% confidence interval width (±1.96σ)

**Theory:**
```
Standard Error = σ = √(variance)
95% CI = [ẑ - 1.96σ, ẑ + 1.96σ]
CI Width = 2 × 1.96σ ≈ 3.92σ
```

## Metadata Tracking

All kriging grid results store parameters in `metadata` for reproducibility:

```julia
grid.metadata["kriging_method"]   # "ordinary", "universal", "block", "cokriging"
grid.metadata["n_neighbors"]      # Local neighborhood size
grid.metadata["model_type"]       # Variogram model (e.g., "exponential")
grid.metadata["variances"]        # Kriging variances (matrix)
grid.metadata["created_at"]       # ISO8601 timestamp

# Method-specific
grid.metadata["drift_order"]      # For universal kriging
grid.metadata["block_size"]       # For block kriging
grid.metadata["aux_predictions"]  # For co-kriging
```

## Integration with Geostatistics.jl

kriging_grid.jl acts as a bridge between point-level kriging predictions and raster-based spatial grids:

1. **Input:** Fitted `VariogramModel` from `Geostatistics.jl`
2. **Process:** Grid-level kriging via Geostatistics functions
3. **Output:** RasterGrid with full uncertainty quantification

```julia
using Geostatistics, Raster

# Geostatistics: Fit variogram
coords = ...  # Training coordinates
z = ...       # Training values
vario = empirical_variogram(coords, z)
model = fit_variogram(vario)

# Raster: Apply to regular grid
grid = create_regular_grid(bounds, 1000.0)
result = ordinary_kriging_grid(z, coords, grid, model)
```

## Coordinate System

- **Input:** Geographic coordinates (longitude, latitude) in decimal degrees
- **Grid:** Regular lat/lon grid with uniform spacing
- **Resolution:** Meters → degrees conversion (1 degree ≈ 111 km)
- **Order:** (x, y) = (longitude, latitude) for coordinates; (y, x) = (rows, cols) for matrices

## Performance Notes

For a typical healthcare analysis:
- **Grid size:** 100×100 cells (10,000 predictions)
- **Training data:** 50-100 observations
- **Kriging time:** < 10 seconds with n_neighbors=15
- **Memory:** ≈5-10 MB per grid

## Error Handling

All functions validate inputs:
- Coordinate dimensions must match
- Grid bounds must be consistent
- Variogram models must be fitted
- Training data must have > 2 observations

## References

- Matheron, G. (1963). Principles of geostatistics. *Economic Geology*, 58(8).
- Chilès, J. & Delfiner, P. (2012). *Geostatistics: Modeling spatial uncertainty*. Wiley.
- Cressie, N. (1991). *Statistics for spatial data*. Wiley.

## Testing

Comprehensive tests in `test/test_kriging_grid.jl` cover:
- ✓ Grid creation (bounds, resolution, coordinates)
- ✓ Ordinary kriging (shape, variance properties)
- ✓ Universal kriging (drift capture)
- ✓ Block kriging (variance reduction)
- ✓ Co-kriging (auxiliary variable integration)
- ✓ Uncertainty surfaces (confidence intervals)
- ✓ Integration tests (spatial patterns)
- ✓ Metadata consistency

## Status

**Phase C: Kriging → Raster Integration** ✅

- [x] Grid creation (regular lat/lon)
- [x] Ordinary kriging on grid
- [x] Universal kriging with drift
- [x] Block kriging for area aggregation
- [x] Co-kriging with auxiliary variables
- [x] Uncertainty quantification
- [x] Value extraction and resampling
- [x] Metadata tracking
- [x] Unit tests

**Next:** Phase D — Population Fusion & Validation (Agent 3)

---

*Part of the HealthcareGeo Ecosystem*
*40-day build to production: [BUILD_ROADMAP.md](../../BUILD_ROADMAP.md)*
