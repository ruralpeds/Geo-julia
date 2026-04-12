"""
    GeoSpatialEngine

A best-in-class geospatial analysis engine for ingesting, processing, and analyzing
geographic data from government and open-source sources.

# Main Components
- **CoreEngine**: Central analysis engine
- **DataIngestion**: Universal data ingestion framework
- **DataSources**: Integrations with gov and open-source geo/weather APIs
- **Analysis**: Spatial analysis, statistics, and modeling
- **Visualization**: Map rendering and data visualization
- **FeatureExtraction**: Extract meaningful features from geospatial data
- **Workflow**: Orchestrate complex analysis workflows

# Usage
```julia
using GeoSpatialEngine

# Initialize engine
engine = GeoSpatialAnalysisEngine()

# Ingest data from multiple sources
data = ingest_data(engine, "NOAA"; region="US", data_type="weather")

# Perform analysis
result = analyze(engine, data)

# Export results
export_result(engine, result, format="GeoJSON")
```
"""
module GeoSpatialEngine

using GeoInterface, Shapefile, NetCDF, Raster, Proj, GeoStats, GeoDataFrames
using DataFrames, Tables, CSV, JSON, JSON3, Arrow, Parquet
using Plots, Images, Statistics, LinearAlgebra, SparseArrays
using HTTP, Dates, TimeZones, TimeSeries
using MLJ, Flux, SQLite, Distributed, SharedArrays
using Logging, LoggingExtras
using DocStringExtensions

# Export main API
export GeoSpatialAnalysisEngine,
       ingest_data,
       analyze,
       export_result,
       create_analysis_pipeline,
       register_data_source,
       get_data_source,
       list_available_sources,
       validate_geospatial_data,
       cache_data,
       batch_analyze

# Core components
include("core/engine.jl")
include("core/types.jl")

# Data ingestion
include("ingestion/ingestion.jl")
include("ingestion/validators.jl")
include("ingestion/caching.jl")

# Data sources
include("sources/sources_registry.jl")
include("sources/noaa.jl")
include("sources/usgs.jl")
include("sources/openstreetmap.jl")
include("sources/copernicus.jl")
include("sources/generic.jl")

# Analysis modules
include("analysis/spatial_analysis.jl")
include("analysis/statistics.jl")
include("analysis/modeling.jl")

# Feature extraction
include("features/feature_extraction.jl")
include("features/preprocessing.jl")

# Visualization
include("visualization/maps.jl")
include("visualization/plots.jl")

# Workflow orchestration
include("workflow/workflow.jl")
include("workflow/pipeline.jl")

# Utilities
include("utils/logging.jl")
include("utils/helpers.jl")
include("utils/configuration.jl")

# Initialize default configuration
const DEFAULT_CONFIG = GeoEngineConfig()

"""
    get_version()

Return the version of GeoSpatialEngine.
"""
function get_version()
    return "1.0.0"
end

end # module
