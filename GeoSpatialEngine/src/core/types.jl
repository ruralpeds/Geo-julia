"""
Types and data structures for the GeoSpatialEngine.
"""

# ============================================================================
# Core Data Types
# ============================================================================

"""
    GeoSpatialData

Container for geospatial data with metadata.

# Fields
- `data::DataFrame`: The actual geospatial data
- `metadata::Dict`: Metadata about the data (source, date, bounds, etc.)
- `geometry::Vector`: Geometry information (points, polygons, etc.)
- `crs::String`: Coordinate Reference System (e.g., "EPSG:4326")
- `bounds::NamedTuple`: Geographic bounds (minx, miny, maxx, maxy)
- `timestamp::DateTime`: When data was ingested
"""
mutable struct GeoSpatialData
    data::DataFrame
    metadata::Dict{String, Any}
    geometry::Union{Vector, Nothing}
    crs::String
    bounds::Union{NamedTuple, Nothing}
    timestamp::DateTime

    function GeoSpatialData(data::DataFrame;
                           metadata=Dict(),
                           geometry=nothing,
                           crs="EPSG:4326",
                           bounds=nothing)
        new(data, metadata, geometry, crs, bounds, now(UTC))
    end
end

"""
    DataSource

Configuration for a data source.

# Fields
- `name::String`: Name of the data source
- `source_type::String`: Type (NOAA, USGS, OpenStreetMap, etc.)
- `url::String`: API endpoint or data location
- `credentials::Dict`: Authentication credentials (if needed)
- `parameters::Dict`: Default parameters for queries
- `description::String`: Description of data source
"""
struct DataSource
    name::String
    source_type::String
    url::String
    credentials::Dict{String, String}
    parameters::Dict{String, Any}
    description::String
    enabled::Bool
end

"""
    AnalysisConfig

Configuration for an analysis operation.

# Fields
- `operation::String`: Type of analysis to perform
- `parameters::Dict`: Operation-specific parameters
- `output_format::String`: Format for results (GeoJSON, GeoTIFF, NetCDF, etc.)
- `coordinate_system::String`: Output coordinate system
"""
struct AnalysisConfig
    operation::String
    parameters::Dict{String, Any}
    output_format::String
    coordinate_system::String
end

"""
    GeoEngineConfig

Global configuration for the GeoSpatialEngine.

# Fields
- `cache_enabled::Bool`: Enable data caching
- `cache_dir::String`: Directory for cache storage
- `parallel_processing::Bool`: Enable parallel processing
- `num_workers::Int`: Number of parallel workers
- `timeout::Float64`: Request timeout in seconds
- `log_level::String`: Logging level (Debug, Info, Warn, Error)
"""
@kwdef mutable struct GeoEngineConfig
    cache_enabled::Bool = true
    cache_dir::String = joinpath(pwd(), ".geo_cache")
    parallel_processing::Bool = true
    num_workers::Int = Threads.nthreads()
    timeout::Float64 = 30.0
    log_level::String = "Info"
end

"""
    AnalysisResult

Container for analysis results.

# Fields
- `result::Any`: The analysis result
- `analysis_config::AnalysisConfig`: Configuration used
- `metadata::Dict`: Result metadata
- `timestamp::DateTime`: When analysis was performed
- `execution_time::Float64`: Time taken in seconds
"""
struct AnalysisResult
    result::Any
    analysis_config::AnalysisConfig
    metadata::Dict{String, Any}
    timestamp::DateTime
    execution_time::Float64
end

"""
    WorkflowPipeline

Orchestrates a sequence of data ingestion and analysis steps.

# Fields
- `name::String`: Name of the pipeline
- `steps::Vector`: Vector of pipeline steps
- `data_store::Dict`: In-memory data store for pipeline results
"""
mutable struct WorkflowPipeline
    name::String
    steps::Vector{Any}
    data_store::Dict{String, Any}

    function WorkflowPipeline(name::String)
        new(name, [], Dict())
    end
end

# ============================================================================
# Enumerations
# ============================================================================

@enum DataFormat begin
    GEOJSON = 1
    GEOTIFF = 2
    NETCDF = 3
    SHAPEFILE = 4
    CSV = 5
    PARQUET = 6
    ARROW = 7
end

@enum SpatialAnalysisType begin
    BUFFER = 1
    INTERSECT = 2
    UNION = 3
    DIFFERENCE = 4
    DISSOLVE = 5
    CLIP = 6
end

@enum SourceType begin
    NOAA = 1
    USGS = 2
    OPENSTREETMAP = 3
    COPERNICUS = 4
    GENERIC_API = 5
    LOCAL_FILE = 6
end
