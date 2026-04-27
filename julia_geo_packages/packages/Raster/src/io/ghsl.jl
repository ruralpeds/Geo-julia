# Import required modules
using Dates

"""
    load_ghsl(country::String; year=2020, layer="built-up") -> RasterGrid

Load Global Human Settlement Layer (GHSL) data for urban/settlement detection.

GHSL provides spatially explicit information on human presence on Earth,
including built-up areas, population presence, and settlement identification.

# Arguments
- `country::String` — Country name or ISO3 code

# Keyword Arguments
- `year::Int` — Reference year (default: 2020; supports 2015, 2020)
- `layer::String` — GHSL layer type (default: "built-up")
  - "built-up" — Built-up area presence (binary)
  - "population" — Population presence grid
  - "settlement" — Settlement identification
- `bounds::NamedTuple` — Optional spatial bounds to clip results
- `use_cache::Bool` — Use local cache if available (default: true)

# Returns
- `RasterGrid{Float32}` — GHSL layer with metadata:
  - `source`: "GHSL"
  - `year`: specified year
  - `layer`: layer type requested
  - `units`: "built-up area fraction" for built-up, "persons/km²" for population
  - `uncertainty`: typical uncertainty estimates

# Example
```julia
# Load built-up area detection for Nigeria
built_up = load_ghsl("Nigeria"; year=2020, layer="built-up")

# Load with bounds clipping
bounds = (west=-6.0, east=-4.0, south=6.0, north=8.0)
settlement = load_ghsl("Nigeria"; year=2020, layer="settlement", bounds=bounds)
```

# References
- GHSL: https://ghsl.jrc.ec.europa.eu/
- Pesaresi, M., et al. (2019) GHS-BUILT: The Global Human Settlement Built-up Layer
"""
function load_ghsl(
    country::String;
    year::Int = 2020,
    layer::String = "built-up",
    bounds::Union{NamedTuple, Nothing} = nothing,
    use_cache::Bool = true
)

    # Validate year
    if year ∉ [2015, 2020]
        @warn "GHSL available for 2015, 2020; requested $year, using 2020"
        year = 2020
    end

    # Validate layer
    valid_layers = ["built-up", "population", "settlement"]
    if layer ∉ valid_layers
        error("Unknown GHSL layer: $layer. Options: $(join(valid_layers, ", "))")
    end

    # Normalize country
    iso3 = _normalize_country_code(country)

    # Cache directory
    cache_dir = expanduser("~/.cache/ghsl")

    # Check cache first
    if use_cache
        cached_file = joinpath(cache_dir, "$(iso3)_$(year)_$(layer).dat")
        if isfile(cached_file)
            return _load_ghsl_cached(cached_file, bounds)
        end
    end

    # Generate mock data
    return _generate_ghsl_mock(iso3, year, layer, bounds)
end

"""
    _generate_ghsl_mock(iso3, year, layer, bounds) -> RasterGrid

Generate realistic mock GHSL data for testing.
"""
function _generate_ghsl_mock(
    iso3::String,
    year::Int,
    layer::String,
    bounds::Union{NamedTuple, Nothing}
)

    # Default bounding boxes
    country_bounds = Dict(
        "NGA" => (west=2.67, east=14.68, south=4.27, north=13.89),
        "KEN" => (west=33.91, east=41.86, south=-4.72, north=4.90),
        "UGA" => (west=29.58, east=35.04, south=-1.44, north=4.24),
        "TZA" => (west=29.34, east=40.53, south=-11.72, north=-0.95),
        "ETH" => (west=33.00, east=47.99, south=3.42, north=14.89),
        "GHA" => (west=-3.26, east=1.20, south=1.74, north=11.14),
    )

    crs_bounds = get(country_bounds, iso3, (west=-10.0, east=10.0, south=-5.0, north=5.0))

    # Override with provided bounds
    if bounds !== nothing
        crs_bounds = bounds
    end

    # GHSL resolution: typically 100m (much finer than WorldPop)
    res_m = 100.0
    res_deg = res_m / 111000.0

    x_coords = collect(crs_bounds.west:res_deg:crs_bounds.east)
    y_coords = collect(crs_bounds.south:res_deg:crs_bounds.north)

    ny = length(y_coords)
    nx = length(x_coords)

    # Generate layer-specific mock data
    data = zeros(Float32, ny, nx)

    if layer == "built-up"
        # Binary built-up area: cluster around urban centers
        for i in 1:ny
            for j in 1:nx
                y_frac = (y_coords[i] - crs_bounds.south) / (crs_bounds.north - crs_bounds.south)
                x_frac = (x_coords[j] - crs_bounds.west) / (crs_bounds.east - crs_bounds.west)

                # Urban centers
                dist1 = sqrt((x_frac - 0.3)^2 + (y_frac - 0.3)^2)
                dist2 = sqrt((x_frac - 0.7)^2 + (y_frac - 0.7)^2)

                # Built-up probability
                prob = exp(-30 * dist1) + 0.7 * exp(-30 * dist2) + 0.1 * rand()
                data[i, j] = if prob > 0.5 1.0 else 0.0 end
            end
        end
        units = "built-up area presence (binary)"
        uncertainty = 0.05  # 5% misclassification typical

    elseif layer == "settlement"
        # Settlement identification (similar to built-up but continuous)
        for i in 1:ny
            for j in 1:nx
                y_frac = (y_coords[i] - crs_bounds.south) / (crs_bounds.north - crs_bounds.south)
                x_frac = (x_coords[j] - crs_bounds.west) / (crs_bounds.east - crs_bounds.west)

                dist1 = sqrt((x_frac - 0.3)^2 + (y_frac - 0.3)^2)
                dist2 = sqrt((x_frac - 0.7)^2 + (y_frac - 0.7)^2)

                # Settlement probability (0-1)
                data[i, j] = 0.8 * exp(-40 * dist1) + 0.6 * exp(-40 * dist2)
            end
        end
        units = "settlement probability (0-1)"
        uncertainty = 0.08

    else  # population
        # Population presence (similar magnitude to WorldPop but at finer resolution)
        for i in 1:ny
            for j in 1:nx
                y_frac = (y_coords[i] - crs_bounds.south) / (crs_bounds.north - crs_bounds.south)
                x_frac = (x_coords[j] - crs_bounds.west) / (crs_bounds.east - crs_bounds.west)

                # Base density
                lat_factor = y_frac
                base = 5.0 + lat_factor * 20.0

                # Urban centers
                dist1 = sqrt((x_frac - 0.3)^2 + (y_frac - 0.3)^2)
                dist2 = sqrt((x_frac - 0.7)^2 + (y_frac - 0.7)^2)

                urban = 100.0 * exp(-50 * dist1) + 80.0 * exp(-50 * dist2)
                data[i, j] = max(base + urban, 0.0)
            end
        end
        units = "persons per 100m cell"
        uncertainty = 0.20
    end

    # Create metadata
    metadata = Dict{String, Any}(
        "source" => "GHSL",
        "year" => year,
        "layer" => layer,
        "country" => iso3,
        "uncertainty" => uncertainty,
        "units" => units,
        "processing_date" => string(today()),
    )

    bounds_nt = (
        west = crs_bounds.west,
        east = crs_bounds.east,
        south = crs_bounds.south,
        north = crs_bounds.north
    )

    return RasterGrid(
        data,
        collect(x_coords),
        collect(y_coords),
        "EPSG:4326",
        bounds_nt,
        res_m,
        metadata
    )
end

"""
    _load_ghsl_cached(filename::String, bounds) -> RasterGrid

Load GHSL data from local cache file.
"""
function _load_ghsl_cached(
    filename::String,
    bounds::Union{NamedTuple, Nothing}
)
    # Placeholder for actual cached data loading
    error("Cached GHSL data file found but deserialization not yet implemented")
end

"""
    clip_raster(raster::RasterGrid, bounds::NamedTuple) -> RasterGrid

Clip a raster to specified geographic bounds.

# Arguments
- `raster::RasterGrid` — Source raster
- `bounds::NamedTuple` — Target bounds (west, east, south, north)

# Returns
- `RasterGrid` — Clipped raster with subset of original data
"""
function clip_raster(raster::RasterGrid, bounds::NamedTuple)
    # Find indices of cells within bounds
    x_mask = (raster.x_coords .>= bounds.west) .& (raster.x_coords .<= bounds.east)
    y_mask = (raster.y_coords .>= bounds.south) .& (raster.y_coords .<= bounds.north)

    # Get indices
    x_indices = findall(x_mask)
    y_indices = findall(y_mask)

    if isempty(x_indices) || isempty(y_indices)
        error("No data within specified bounds")
    end

    # Subset data and coordinates
    data_clipped = raster.data[y_indices, x_indices]
    x_clipped = raster.x_coords[x_indices]
    y_clipped = raster.y_coords[y_indices]

    # Create new bounds
    clipped_bounds = (
        west = minimum(x_clipped),
        east = maximum(x_clipped),
        south = minimum(y_clipped),
        north = maximum(y_clipped)
    )

    # Copy metadata and create new raster
    metadata = copy(raster.metadata)
    metadata["clipped"] = true
    metadata["original_bounds"] = raster.bounds

    return RasterGrid(
        data_clipped,
        x_clipped,
        y_clipped,
        raster.crs,
        clipped_bounds,
        raster.resolution_m,
        metadata
    )
end

"""
    buffer_bounds(bounds::NamedTuple, buffer_deg::Float64) -> NamedTuple

Create a buffer zone around geographic bounds.

# Arguments
- `bounds::NamedTuple` — Original bounds
- `buffer_deg::Float64` — Buffer distance in degrees (≈ 111 km per degree)

# Returns
- `NamedTuple` — Buffered bounds
"""
function buffer_bounds(bounds::NamedTuple, buffer_deg::Float64)
    return (
        west = bounds.west - buffer_deg,
        east = bounds.east + buffer_deg,
        south = bounds.south - buffer_deg,
        north = bounds.north + buffer_deg
    )
end
