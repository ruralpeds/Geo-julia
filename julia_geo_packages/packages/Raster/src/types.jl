"""
    RasterGrid{T<:Real}

A regular gridded raster dataset for geospatial analysis, supporting healthcare
population and infrastructure data from sources like WorldPop and GHSL.

# Fields
- `data::Matrix{T}` — Gridded values in (y, x) order (row-major: rows=y, cols=x) following
  raster convention where first row is northernmost (largest y-coordinate)
- `x_coords::Vector{Float64}` — X-axis (longitude) coordinates of grid cell centers, length(x_coords) = size(data, 2)
- `y_coords::Vector{Float64}` — Y-axis (latitude) coordinates of grid cell centers, length(y_coords) = size(data, 1)
- `crs::String` — Coordinate reference system (e.g., "EPSG:4326" for WGS84)
- `bounds::NamedTuple{(:west, :east, :south, :north), NTuple{4, Float64}}` — Geospatial bounds
  as (west=min_lon, east=max_lon, south=min_lat, north=max_lat)
- `resolution_m::Float64` — Spatial resolution in meters (approximate for geographic CRS)
- `metadata::Dict{String, Any}` — Data provenance tracking:
  - `source` (String): "WorldPop", "GHSL", or custom source identifier
  - `year` (Int): Reference year of data collection
  - `uncertainty` (Float64 or Vector): Measurement uncertainty estimates
  - `units` (String): Data units (e.g., "persons per grid cell", "hectares")
  - Any other custom metadata (author, processing date, notes, etc.)

# Example
```julia
# Create a 100×100 raster with 250m resolution
x = range(-74.0, -73.0, length=100)
y = range(39.0, 40.0, length=100)
data = randn(100, 100)
crs = "EPSG:4326"
bounds = (west=-74.0, east=-73.0, south=39.0, north=40.0)
metadata = Dict(
    "source" => "WorldPop",
    "year" => 2020,
    "uncertainty" => 0.15,
    "units" => "persons per grid cell"
)

raster = RasterGrid(data, collect(x), collect(y), crs, bounds, 250.0, metadata)
```
"""
struct RasterGrid{T<:Real}
    data::Matrix{T}
    x_coords::Vector{Float64}
    y_coords::Vector{Float64}
    crs::String
    bounds::NamedTuple{(:west, :east, :south, :north), NTuple{4, Float64}}
    resolution_m::Float64
    metadata::Dict{String, Any}

    function RasterGrid(
        data::Matrix{T},
        x_coords::Vector{Float64},
        y_coords::Vector{Float64},
        crs::String,
        bounds::NamedTuple{(:west, :east, :south, :north), NTuple{4, Float64}},
        resolution_m::Float64,
        metadata::Dict{String, Any} = Dict{String, Any}()
    ) where {T<:Real}

        # Validate dimensions
        if size(data, 2) != length(x_coords)
            error("Number of columns in data ($(size(data, 2))) must match length of x_coords ($(length(x_coords)))")
        end
        if size(data, 1) != length(y_coords)
            error("Number of rows in data ($(size(data, 1))) must match length of y_coords ($(length(y_coords)))")
        end

        # Validate bounds ordering
        if bounds.west >= bounds.east
            error("Western bound ($(bounds.west)) must be less than eastern bound ($(bounds.east))")
        end
        if bounds.south >= bounds.north
            error("Southern bound ($(bounds.south)) must be less than northern bound ($(bounds.north))")
        end

        # Validate resolution
        if resolution_m <= 0.0
            error("Resolution must be positive, got $(resolution_m)m")
        end

        # Ensure metadata has required source field
        if !haskey(metadata, "source")
            metadata["source"] = "Unknown"
        end

        new{T}(data, x_coords, y_coords, crs, bounds, resolution_m, metadata)
    end
end

"""
    RasterGrid(data, x_coords, y_coords; crs="EPSG:4326", resolution_m=250.0, metadata=Dict())

Convenience constructor for RasterGrid with automatic bounds calculation.

# Arguments
- `data::Matrix{T}` — Gridded data (y×x order)
- `x_coords::Vector{Float64}` — X-axis coordinates
- `y_coords::Vector{Float64}` — Y-axis coordinates
- `crs::String` — Coordinate reference system (default: WGS84)
- `resolution_m::Float64` — Resolution in meters
- `metadata::Dict` — Data provenance information

# Returns
- `RasterGrid{T}` — Initialized raster grid with computed bounds
"""
function RasterGrid(
    data::Matrix{T},
    x_coords::Vector{Float64},
    y_coords::Vector{Float64};
    crs::String = "EPSG:4326",
    resolution_m::Float64 = 250.0,
    metadata::Dict{String, Any} = Dict{String, Any}()
) where {T<:Real}

    x_min, x_max = extrema(x_coords)
    y_min, y_max = extrema(y_coords)

    # Calculate cell half-width for accurate bounds
    x_step = length(x_coords) > 1 ? (x_coords[end] - x_coords[1]) / (length(x_coords) - 1) : 0.0
    y_step = length(y_coords) > 1 ? (y_coords[end] - y_coords[1]) / (length(y_coords) - 1) : 0.0

    x_half = x_step / 2
    y_half = y_step / 2

    bounds = (
        west = x_min - x_half,
        east = x_max + x_half,
        south = y_min - y_half,
        north = y_max + y_half
    )

    RasterGrid(data, x_coords, y_coords, crs, bounds, resolution_m, metadata)
end

"""
    Base.size(raster::RasterGrid) -> (Int, Int)

Return the dimensions of the raster grid (ny, nx).
"""
Base.size(raster::RasterGrid) = size(raster.data)

"""
    Base.size(raster::RasterGrid, dim::Int) -> Int

Return the size along a specific dimension.
"""
Base.size(raster::RasterGrid, dim::Int) = size(raster.data, dim)

"""
    Base.getindex(raster::RasterGrid, args...)

Access raster data using standard array indexing: `raster[y, x]`.
"""
Base.getindex(raster::RasterGrid, args...) = getindex(raster.data, args...)

"""
    Base.setindex!(raster::RasterGrid, args...)

Modify raster data using standard array assignment: `raster[y, x] = value`.
"""
Base.setindex!(raster::RasterGrid, args...) = setindex!(raster.data, args...)

"""
    Base.show(io::IO, raster::RasterGrid{T})

Pretty-print summary of raster grid.
"""
function Base.show(io::IO, raster::RasterGrid{T}) where {T}
    ny, nx = size(raster)
    println(io, "RasterGrid{$T}")
    println(io, "  Dimensions: $ny × $nx (y × x)")
    println(io, "  Bounds: west=$(raster.bounds.west), east=$(raster.bounds.east), south=$(raster.bounds.south), north=$(raster.bounds.north)")
    println(io, "  CRS: $(raster.crs)")
    println(io, "  Resolution: $(raster.resolution_m) m")
    println(io, "  Data range: $(extrema(raster.data))")
    source = get(raster.metadata, "source", "Unknown")
    println(io, "  Source: $source")
end

"""
    center_coordinates(raster::RasterGrid) -> (Vector{Float64}, Vector{Float64})

Get (x_coords, y_coords) of grid cell centers.
"""
function center_coordinates(raster::RasterGrid)
    return (raster.x_coords, raster.y_coords)
end

"""
    pixel_coordinates(raster::RasterGrid, i::Int, j::Int) -> (Float64, Float64)

Get (x, y) coordinate of grid cell center at indices (i, j) where i is row (y) and j is column (x).
"""
function pixel_coordinates(raster::RasterGrid, i::Int, j::Int)
    return (raster.x_coords[j], raster.y_coords[i])
end

"""
    get_metadata(raster::RasterGrid, key::String, default=nothing)

Safely retrieve metadata value with optional default.
"""
function get_metadata(raster::RasterGrid, key::String, default=nothing)
    return get(raster.metadata, key, default)
end

"""
    update_metadata!(raster::RasterGrid, key::String, value)

Update or add metadata entry.
"""
function update_metadata!(raster::RasterGrid, key::String, value)
    raster.metadata[key] = value
    return raster
end
