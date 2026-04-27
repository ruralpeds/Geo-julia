"""
    Raster

Raster data I/O and management for healthcare geospatial analysis.

Provides gridded raster data structures (RasterGrid) and loading functions for:
- WorldPop: High-resolution gridded population data
- GHSL: Global Human Settlement Layer (built-up areas, settlements)
- GeoTIFF: Native geospatial raster format support

## Features
- Generic RasterGrid{T} data structure with spatial metadata
- Load/save raster data in GeoTIFF format
- WorldPop population density loaders with local caching
- GHSL built-up area and settlement detection
- Comprehensive data provenance tracking via metadata
- GIS-compatible bounds and coordinate reference systems

## Usage

```julia
using Raster

# Load WorldPop population data for a country
pop_raster = load_worldpop("Nigeria"; year=2020, resolution="250m")
println("Population shape: \$(size(pop_raster))")
println("Source: \$(pop_raster.metadata[\"source\"])")

# Load GHSL built-up area data
settlement = load_ghsl("Nigeria"; year=2020)

# Save to GeoTIFF
save_raster(pop_raster, "nigeria_pop_2020.tif")

# Load from GeoTIFF
loaded = load_raster("nigeria_pop_2020.tif")
```

## Architecture

Phase B (Days 13-14): Core Types & I/O
- `types.jl` — RasterGrid{T} core data structure with metadata tracking
- `io/load_save.jl` — GeoTIFF I/O
- `io/worldpop.jl` — WorldPop population grids with caching
- `io/ghsl.jl` — GHSL settlement layers

Phase C (Days 15+): Kriging Integration & Fusion
- `analysis/kriging_grid.jl` — Kriging on raster grids (Agent 2)
- `analysis/fusion.jl` and `analysis/validation.jl` — Multi-source fusion (Agent 3)
"""

module Raster

using LinearAlgebra
using Statistics
using Dates
using Geostatistics

# Core data structures
include("types.jl")

# I/O modules
include("io/load_save.jl")
include("io/worldpop.jl")
include("io/ghsl.jl")

# Kriging integration (Phase C — Agent 2)
include("analysis/kriging_grid.jl")

# Spatial indexing optimization (Phase IV-V — Days 56-57)
include("analysis/kdtree_2sfca.jl")

# Population fusion (Phase D — Agent 3)
include("analysis/fusion.jl")
include("analysis/validation.jl")

# Exports
export
    # Data structures
    RasterGrid,
    # Constructors & utilities
    center_coordinates, pixel_coordinates, get_metadata, update_metadata!,
    # I/O
    save_raster, load_raster,
    # WorldPop
    load_worldpop, cache_worldpop,
    # GHSL
    load_ghsl, clip_raster, buffer_bounds,
    # Grid operations (Phase C)
    align_raster_grids,
    create_regular_grid,
    ordinary_kriging_grid,
    universal_kriging_grid,
    block_kriging_grid,
    cokriging_grid,
    extract_raster_values,
    reshape_predictions,
    create_uncertainty_surface,
    # Spatial indexing (Phase IV-V — optimization)
    kdtree_2sfca,
    # Population fusion (Phase D)
    fuse_population_sources,
    estimate_source_weights,
    raster_cross_validate,
    inter_source_agreement,
    fusion_quality_report

end
