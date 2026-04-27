# Import required modules
using Dates
using Random

"""
    load_worldpop(country::String, year::Int; resolution="250m") -> RasterGrid

Load WorldPop population density grid for a specified country and year.

WorldPop provides high-resolution gridded population counts and density estimates
globally. This function loads cached data or generates mock data for testing.

# Arguments
- `country::String` — Country name or ISO3 code (e.g., "Nigeria", "NGA")
- `year::Int` — Reference year (e.g., 2020)
- `resolution::String` — Grid resolution: "1km", "250m", "100m" (default: "250m")

# Keyword Arguments
- `use_cache::Bool` — Use local cache (~/.cache/worldpop/) if available (default: true)
- `bounds::NamedTuple` — Optional spatial bounds (west, east, south, north) to clip results

# Returns
- `RasterGrid{Float32}` — Population density grid with metadata:
  - `source`: "WorldPop"
  - `year`: specified year
  - `resolution`: grid resolution in meters
  - `uncertainty`: typical uncertainty estimate (15% for WorldPop)
  - `units`: "persons per grid cell"

# Example
```julia
# Load Nigeria population for 2020 at 250m resolution
pop = load_worldpop("Nigeria", 2020)
println("Population grid: \$(size(pop))")
println("Total population: \$(sum(pop.data))")

# Load with custom bounds
bounds = (west=-6.0, east=-4.0, south=6.0, north=8.0)
pop_clipped = load_worldpop("Nigeria", 2020; bounds=bounds)
```

# Notes
- This is a mock implementation for testing. In production, download from
  http://www.worldpop.org.uk/
- Cache directory: `~/.cache/worldpop/`
- Data is returned as persons per grid cell
"""
function load_worldpop(
    country::String,
    year::Int;
    resolution::String = "250m",
    use_cache::Bool = true,
    bounds::Union{NamedTuple, Nothing} = nothing
)

    # Normalize country name to ISO3 code
    iso3 = _normalize_country_code(country)

    # Resolution to meters
    res_m = _parse_resolution(resolution)

    # Cache directory
    cache_dir = expanduser("~/.cache/worldpop")

    # Check cache first
    if use_cache
        cached_file = joinpath(cache_dir, "$(iso3)_$(year)_$(resolution).dat")
        if isfile(cached_file)
            return _load_worldpop_cached(cached_file, bounds)
        end
    end

    # Generate mock data for testing
    return _generate_worldpop_mock(iso3, year, resolution, res_m, bounds)
end

"""
    _normalize_country_code(country::String) -> String

Normalize country name to ISO3 code.
"""
function _normalize_country_code(country::String)
    # Simple mapping for common countries
    iso3_map = Dict(
        "Nigeria" => "NGA",
        "NGA" => "NGA",
        "Kenya" => "KEN",
        "KEN" => "KEN",
        "Uganda" => "UGA",
        "UGA" => "UGA",
        "Tanzania" => "TZA",
        "TZA" => "TZA",
        "Ethiopia" => "ETH",
        "ETH" => "ETH",
        "Ghana" => "GHA",
        "GHA" => "GHA",
        "Senegal" => "SEN",
        "SEN" => "SEN",
        "Mali" => "MLI",
        "MLI" => "MLI",
    )
    return get(iso3_map, country, uppercase(country[1:min(3, length(country))]))
end

"""
    _parse_resolution(resolution::String) -> Float64

Parse resolution string to meters.
"""
function _parse_resolution(resolution::String)::Float64
    if resolution == "1km"
        return 1000.0
    elseif resolution == "250m"
        return 250.0
    elseif resolution == "100m"
        return 100.0
    else
        # Try to parse as numeric
        try
            m = match(r"(\d+)m", resolution)
            if m !== nothing
                return parse(Float64, m.captures[1])
            end
        catch
        end
        error("Unknown resolution format: $resolution")
    end
end

"""
    _generate_worldpop_mock(iso3, year, resolution, res_m, bounds) -> RasterGrid

Generate realistic mock WorldPop data for testing.
"""
function _generate_worldpop_mock(
    iso3::String,
    year::Int,
    resolution::String,
    res_m::Float64,
    bounds::Union{NamedTuple, Nothing}
)

    # Default bounding boxes for demo countries (approximate)
    country_bounds = Dict(
        "NGA" => (west=2.67, east=14.68, south=4.27, north=13.89),
        "KEN" => (west=33.91, east=41.86, south=-4.72, north=4.90),
        "UGA" => (west=29.58, east=35.04, south=-1.44, north=4.24),
        "TZA" => (west=29.34, east=40.53, south=-11.72, north=-0.95),
        "ETH" => (west=33.00, east=47.99, south=3.42, north=14.89),
        "GHA" => (west=-3.26, east=1.20, south=1.74, north=11.14),
        "SEN" => (west=-17.54, east=-11.37, south=12.37, north=16.13),
        "MLI" => (west=-12.29, east=4.27, south=10.16, north=25.16),
    )

    crs_bounds = get(country_bounds, iso3, (west=-10.0, east=10.0, south=-5.0, north=5.0))

    # Override with provided bounds if given
    if bounds !== nothing
        crs_bounds = bounds
    end

    # Create coordinate arrays at specified resolution (in degrees)
    # Approximate: 1 degree ≈ 111 km, so resolution_degrees ≈ res_m / 111000
    res_deg = res_m / 111000.0

    x_coords = collect(crs_bounds.west:res_deg:crs_bounds.east)
    y_coords = collect(crs_bounds.south:res_deg:crs_bounds.north)

    # Generate realistic population density
    ny = length(y_coords)
    nx = length(x_coords)

    # Base population density gradient (persons per cell)
    # Density decreases with latitude in this mock data
    data = zeros(Float32, ny, nx)

    # Create mock density with urban centers
    for i in 1:ny
        for j in 1:nx
            # Base density: varies by latitude
            lat_factor = (y_coords[i] - crs_bounds.south) / (crs_bounds.north - crs_bounds.south)
            base_density = 50.0 + lat_factor * 100.0

            # Add some "urban centers"
            y_frac = (y_coords[i] - crs_bounds.south) / (crs_bounds.north - crs_bounds.south)
            x_frac = (x_coords[j] - crs_bounds.west) / (crs_bounds.east - crs_bounds.west)

            # Urban centers at (0.3, 0.3), (0.7, 0.7)
            dist1 = sqrt((x_frac - 0.3)^2 + (y_frac - 0.3)^2)
            dist2 = sqrt((x_frac - 0.7)^2 + (y_frac - 0.7)^2)

            urban_density = 500.0 * exp(-50 * dist1) + 400.0 * exp(-50 * dist2)
            data[i, j] = max(base_density + urban_density, 1.0)
        end
    end

    # Add small random noise
    data .+= randn(Float32, ny, nx) .* 5.0
    data = max.(data, 0.0)

    # Create metadata
    metadata = Dict{String, Any}(
        "source" => "WorldPop",
        "year" => year,
        "country" => iso3,
        "resolution" => resolution,
        "uncertainty" => 0.15,  # 15% typical uncertainty
        "units" => "persons per grid cell",
        "data_type" => "population_count",
        "processing_date" => string(today()),
    )

    # Create bounds NamedTuple
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
    _load_worldpop_cached(filename::String, bounds) -> RasterGrid

Load WorldPop data from local cache file.
"""
function _load_worldpop_cached(
    filename::String,
    bounds::Union{NamedTuple, Nothing}
)
    # Placeholder for actual cached data loading
    # In production, this would deserialize a cached Julia object
    error("Cached data file found but deserialization not yet implemented")
end

"""
    cache_worldpop(country::String, year::Int; resolution="250m")

Download and cache WorldPop data for offline access.

This is a placeholder for production use. In actual implementation,
this would download from the WorldPop API or direct download links.
"""
function cache_worldpop(
    country::String,
    year::Int;
    resolution::String = "250m"
)
    cache_dir = expanduser("~/.cache/worldpop")
    if !isdir(cache_dir)
        mkpath(cache_dir)
    end

    iso3 = _normalize_country_code(country)
    res_m = _parse_resolution(resolution)

    # In production: download from WorldPop API
    # For now, just return success message
    @info "Cache directory created: $cache_dir"
    @info "To cache data: implement production download from worldpop.org"

    return cache_dir
end
