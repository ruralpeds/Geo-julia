# Raster.jl

Raster data I/O and gridded population management for healthcare geospatial analysis.

**Phase B (Days 13-14):** Core Types & I/O ✓
**Phase C (Days 15+):** Kriging Integration (planned)
**Phase D (Days 16+):** Population Fusion & Validation (planned)

## Features

### Phase B: Core Types & I/O

#### RasterGrid{T} Data Structure
- **RasterGrid{T}** — Type-generic gridded raster dataset
  - `data::Matrix{T}` — Gridded values in (y, x) order
  - `x_coords`, `y_coords` — Geographic coordinates
  - `crs::String` — Coordinate reference system (e.g., "EPSG:4326")
  - `bounds::NamedTuple` — (west, east, south, north) bounds
  - `resolution_m::Float64` — Resolution in meters
  - `metadata::Dict{String, Any}` — Provenance tracking

#### I/O Operations
- **save_raster()** — Save raster to GeoTIFF with geospatial metadata
- **load_raster()** — Load raster from GeoTIFF with full metadata restoration

#### Data Loaders
- **load_worldpop()** — High-resolution gridded population density
  - Supports Nigeria, Kenya, Uganda, Tanzania, Ethiopia, Ghana, Senegal, Mali
  - Resolutions: 100m, 250m, 1km
  - Years: 2020 (mock data generation for testing)
  - Returns RasterGrid{Float32} with metadata tracking

- **load_ghsl()** — Global Human Settlement Layer
  - Layers: "built-up" (binary), "settlement" (0-1), "population"
  - Years: 2015, 2020
  - 100m resolution (finer than WorldPop)
  - Returns RasterGrid with uncertainty estimates

#### Metadata Management
- **get_metadata()** — Safe metadata access with defaults
- **update_metadata!()** — Update metadata entries
- Standardized fields: source, year, uncertainty, units, processing_date

#### Spatial Operations
- **clip_raster()** — Clip raster to geographic bounds
- **buffer_bounds()** — Create buffer zones around bounds
- **center_coordinates()** — Get (x, y) coordinates
- **pixel_coordinates()** — Get coordinates of specific cells

### Phase D: Population Fusion & Validation (future)

- **fuse_population_sources()** — Bayesian fusion of multiple sources
- **estimate_source_weights()** — Correlation-based weight estimation
- **inter_source_agreement()** — Spatial disagreement metrics
- **fusion_quality_report()** — Quality assessment with confidence scores

## Installation

```julia
using Pkg
Pkg.add(path="/path/to/Raster")
```

## Quick Start

### Load Population Data

```julia
using Raster

# Load WorldPop population density
pop = load_worldpop("Nigeria", 2020)
println("Grid size: $(size(pop))")
println("Source: $(pop.metadata["source"])")
println("Data range: $(extrema(pop.data))")
```

### Load Settlement Data

```julia
# Load GHSL built-up areas
buildup = load_ghsl("Nigeria"; year=2020, layer="built-up")

# Load settlement probabilities
settlement = load_ghsl("Nigeria"; year=2020, layer="settlement")
```

### Different Resolutions

```julia
# WorldPop at multiple resolutions
pop_1km = load_worldpop("Nigeria", 2020; resolution="1km")
pop_250m = load_worldpop("Nigeria", 2020; resolution="250m")

println("1km cells: $(size(pop_1km))")
println("250m cells: $(size(pop_250m))")
```

### Save and Load

```julia
# Save to GeoTIFF
save_raster(pop, "outputs/nigeria_pop_2020.tif")

# Load from file
loaded = load_raster("outputs/nigeria_pop_2020.tif")
```

### Create Custom Rasters

```julia
# Create from scratch
data = rand(Float32, 100, 100)
x = collect(range(-10.0, -8.0, length=100))
y = collect(range(5.0, 8.0, length=100))

metadata = Dict(
    "source" => "custom_model",
    "year" => 2021,
    "uncertainty" => 0.20
)

raster = RasterGrid(data, x, y;
    resolution_m=250.0,
    metadata=metadata)
```

### Access Metadata

```julia
# Get with defaults
source = get_metadata(raster, "source", "Unknown")

# Update metadata
update_metadata!(raster, "processing_date", "2024-04-09")
```

## Mathematical Background

### Bayesian Fusion

Fuses n population sources using weighted averaging:

```
fused(x,y) = Σ w_s * source_s(x,y) / Σ w_s
```

where weights are estimated from spatial correlation and source stability.

### Uncertainty Quantification

Combined uncertainty combines measurement error and inter-source disagreement:

```
var(fused) = √(Σ w_s² * σ²_s(local)) + var(sources across cell)
           = measurement uncertainty + disagreement variance
```

### Source Weighting

Sources receive higher weights when:
- **Stable**: Low coefficient of variation (CV = σ/μ)
- **Correlated**: High pairwise correlation with other sources

Weights are inverse-CV weighted and normalized to sum to 1.0.

### Quality Metrics

**Confidence**: 1/(1+CV) measures agreement strength
- CV = coefficient of variation across sources
- Confidence ∈ [0, 1]: 1 = perfect agreement, 0 = high disagreement

## Data Structures

### RasterGrid{T}

```julia
struct RasterGrid{T<:Real}
    data::Matrix{T}              # Gridded values (ny × nx)
    x_coords::Vector{Float64}    # X coordinates (longitude)
    y_coords::Vector{Float64}    # Y coordinates (latitude)
    crs::String                  # Coordinate reference system
    bounds::NamedTuple           # (west, east, south, north)
    resolution_m::Float64        # Resolution in meters
    metadata::Dict{String,Any}   # Provenance & uncertainty
end
```

## Integration with Other Packages

### Geostatistics.jl
- Fused rasters can be input to kriging for spatial interpolation
- Uncertainty surfaces inform kriging variance estimation

### HealthcareGeo.jl
- Fused population grids enable 2SFCA accessibility analysis
- Confidence metrics inform healthcare planning decisions

### RuralData.jl
- Raster grids support rural healthcare infrastructure mapping
- Population fusion improves provider density analysis

## Testing

```julia
using Pkg
Pkg.test("Raster")
```

Comprehensive test suite covers:
- Grid alignment and coordinate compatibility
- Weight estimation and fusion accuracy
- Uncertainty quantification
- Cross-validation metrics
- Quality assessment metrics
- Edge cases (NaN handling, single source, etc.)

## References

- Cressie, N. (1991). *Statistics for spatial data*. Wiley.
- Bayesian hierarchical models for combining multiple surveys
- Multi-source population data integration techniques

## Authors

Timothy Hartzog

## License

MIT License (subject to institutional policies)
