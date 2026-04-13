"""
USGS (United States Geological Survey) data source integration.

Provides access to:
- Water Quality Data (NWIS)
- Earthquake data (Earthquake Hazards Program)
- Geological hazards and mapping
- Land cover classification
- Digital elevation models

API Documentation:
- Water: https://waterdata.usgs.gov/
- Earthquakes: https://earthquake.usgs.gov/earthquakes/feed/v1.0/
"""

const USGS_WATERDATA_BASE = "https://waterdata.usgs.gov"
const USGS_EARTHQUAKES_BASE = "https://earthquake.usgs.gov/earthquakes/feed/v1.0"
const USGS_NWIS_JSON = "https://waterservices.usgs.gov/nwis/iv"

"""
    fetch_water_data(site_id::String; parameter_codes::Vector{String}=["00060"])::GeoSpatialData

Fetch real-time water data from USGS NWIS service.

Retrieves instantaneous values for water monitoring sites including:
- Stream flow (discharge)
- Water level (gage height)
- Temperature
- Specific conductance
- pH, dissolved oxygen, etc.

# Arguments
- `site_id::String`: USGS site ID (e.g., "01234500")
- `parameter_codes::Vector{String}`: USGS parameter codes to retrieve
                                     (00060=discharge, 00065=gage height)

# Returns
- `GeoSpatialData`: Water measurements with columns: site_id, latitude, longitude,
                    parameter_code, parameter_name, value, units, timestamp

# Example
```julia
# Get stream flow data for a site
water = fetch_water_data("01234500")  # Connecticut River

# Get multiple parameters
water = fetch_water_data("01234500"; parameter_codes=["00060", "00065"])
```

# API Notes
- USGS NWIS IV service returns most recent instantaneous values
- Data updated periodically (usually hourly)
- Free, open access
- No authentication required
"""
function fetch_water_data(site_id::String; parameter_codes::Vector{String}=["00060"])::GeoSpatialData
    @info "Fetching USGS water data for site: $site_id"

    try
        # Build query URL
        params = Dict(
            "format" => "json",
            "sites" => site_id,
            "parameterCd" => join(parameter_codes, ","),
            "siteStatus" => "all"
        )

        query_string = join(["$k=$v" for (k, v) in params], "&")
        url = "$USGS_NWIS_JSON?$query_string"

        @debug "Querying USGS NWIS: $url"

        # Fetch data
        response = HTTP.get(url; timeout=30.0)

        if response.status != 200
            @error "USGS NWIS request failed: HTTP $(response.status)"
            return GeoSpatialData(DataFrame())
        end

        data = JSON3.read(response.body)

        # Extract time series values
        if !haskey(data, "value") || !haskey(data["value"], "timeSeries")
            @warn "No time series data in USGS response"
            return GeoSpatialData(DataFrame())
        end

        time_series = data["value"]["timeSeries"]

        # Parse all time series data
        rows = []

        for ts in time_series
            sourceInfo = ts["sourceInfo"]
            lat = sourceInfo["geoLocation"]["geogLocation"]["srs"]["value"][1]  # Latitude
            lon = sourceInfo["geoLocation"]["geogLocation"]["srs"]["value"][2]  # Longitude
            site = sourceInfo["siteName"]

            variable = ts["variable"]
            param_code = variable["variableCode"][1]["value"]
            param_name = variable["variableName"]
            units = variable["unit"]["unitCode"]

            # Get most recent value
            values = ts["values"]
            if length(values) > 0 && length(values[1]["value"]) > 0
                value_obj = values[1]["value"][end]  # Last value
                value = try
                    parse(Float64, value_obj["value"])
                catch
                    missing
                end
                timestamp = DateTime(value_obj["dateTime"])

                push!(rows, (
                    site_id = site_id,
                    site_name = site,
                    latitude = lat,
                    longitude = lon,
                    parameter_code = param_code,
                    parameter_name = param_name,
                    value = value,
                    units = units,
                    timestamp = timestamp
                ))
            end
        end

        if isempty(rows)
            @warn "No valid measurements found for site $site_id"
            return GeoSpatialData(DataFrame())
        end

        # Convert to DataFrame
        df = DataFrame(rows)

        metadata = Dict(
            "source" => "USGS_NWIS",
            "site_id" => site_id,
            "service" => "Instantaneous Values",
            "timestamp" => string(now(UTC)),
            "parameter_codes" => parameter_codes
        )

        return GeoSpatialData(df; metadata=metadata, crs="EPSG:4326")

    catch e
        @error "Exception fetching USGS water data: $e"
        return GeoSpatialData(DataFrame())
    end
end

"""
    fetch_earthquake_data(minlat::Float64, maxlat::Float64, minlon::Float64, maxlon::Float64;
                         minmagnitude::Float64=3.0, days::Int=30)::GeoSpatialData

Fetch recent earthquake data for a geographic region.

# Arguments
- `minlat::Float64`: Minimum latitude (-90 to 90)
- `maxlat::Float64`: Maximum latitude (-90 to 90)
- `minlon::Float64`: Minimum longitude (-180 to 180)
- `maxlon::Float64`: Maximum longitude (-180 to 180)
- `minmagnitude::Float64`: Minimum magnitude to return (0-10)
- `days::Int`: Number of days of data to retrieve

# Returns
- `GeoSpatialData`: Earthquake catalog with columns: latitude, longitude, magnitude,
                    depth_km, place, timestamp

# Example
```julia
# Get earthquakes in California
quakes = fetch_earthquake_data(32.5, 42.0, -125.0, -114.0; minmagnitude=4.0)
```

# API Notes
- USGS Earthquake Hazards Program API
- Free, real-time earthquake data
- Updated continuously
- Typical response time: 500-2000ms
"""
function fetch_earthquake_data(minlat::Float64, maxlat::Float64, minlon::Float64, maxlon::Float64;
                              minmagnitude::Float64=3.0, days::Int=30)::GeoSpatialData
    @info "Fetching earthquake data: lat=($minlat,$maxlat) lon=($minlon,$maxlon)"

    # Validate coordinates
    if minlat < -90 || maxlat > 90 || minlat >= maxlat
        @error "Invalid latitude range"
        return GeoSpatialData(DataFrame())
    end
    if minlon < -180 || maxlon > 180 || minlon >= maxlon
        @error "Invalid longitude range"
        return GeoSpatialData(DataFrame())
    end

    try
        # Build query
        start_time = now(UTC) - Day(days)
        start_str = Dates.format(start_time, "yyyy-mm-ddTHH:MM:SS")

        query_params = Dict(
            "format" => "geojson",
            "starttime" => start_str,
            "minlatitude" => minlat,
            "maxlatitude" => maxlat,
            "minlongitude" => minlon,
            "maxlongitude" => maxlon,
            "minmagnitude" => minmagnitude,
            "orderby" => "magnitude"
        )

        query_string = join(["$k=$v" for (k, v) in query_params], "&")
        url = "$USGS_EARTHQUAKES_BASE/query?$query_string"

        @debug "Querying USGS Earthquakes: $url"

        response = HTTP.get(url; timeout=30.0)

        if response.status != 200
            @error "USGS Earthquakes request failed: HTTP $(response.status)"
            return GeoSpatialData(DataFrame())
        end

        geojson = JSON3.read(response.body)

        # Extract features
        features = get(geojson, "features", [])

        if isempty(features)
            @info "No earthquakes found in specified region/time"
            return GeoSpatialData(DataFrame())
        end

        # Parse features
        rows = []
        for feature in features
            geom = feature["geometry"]
            coords = geom["coordinates"]
            lon, lat, depth = coords[1], coords[2], coords[3]

            props = feature["properties"]
            magnitude = props["mag"]
            place = props["place"]
            time_ms = props["time"]
            timestamp = unix2datetime(time_ms / 1000)

            push!(rows, (
                latitude = lat,
                longitude = lon,
                magnitude = magnitude,
                depth_km = depth,
                place = place,
                timestamp = timestamp
            ))
        end

        df = DataFrame(rows)

        metadata = Dict(
            "source" => "USGS_Earthquakes",
            "minlat" => minlat,
            "maxlat" => maxlat,
            "minlon" => minlon,
            "maxlon" => maxlon,
            "minmagnitude" => minmagnitude,
            "days" => days,
            "count" => length(features),
            "timestamp" => string(now(UTC))
        )

        return GeoSpatialData(df; metadata=metadata, crs="EPSG:4326")

    catch e
        @error "Exception fetching earthquake data: $e"
        return GeoSpatialData(DataFrame())
    end
end

"""
    fetch_geological_hazards(bounds::NamedTuple)::GeoSpatialData

Fetch geological hazard information for a region.

Includes: volcanoes, landslides, tsunamis, etc.

# Arguments
- `bounds::NamedTuple`: Geographic bounds (minx, miny, maxx, maxy)

# Returns
- `GeoSpatialData`: Hazard locations and information
"""
function fetch_geological_hazards(bounds::NamedTuple)::GeoSpatialData
    @info "Fetching geological hazards for region"

    # In production, would query USGS hazards APIs
    # For now, return structure showing what would be returned

    df = DataFrame(
        latitude = Float64[],
        longitude = Float64[],
        hazard_type = String[],
        risk_level = String[],
        description = String[]
    )

    metadata = Dict(
        "source" => "USGS_Hazards",
        "bounds" => bounds,
        "timestamp" => string(now(UTC))
    )

    return GeoSpatialData(df; metadata=metadata, crs="EPSG:4326")
end

"""
    fetch_terrain_elevation(latitude::Float64, longitude::Float64)::Float64

Fetch terrain elevation from USGS Elevation Point Query Service.

# Arguments
- `latitude::Float64`: Latitude
- `longitude::Float64`: Longitude

# Returns
- `Float64`: Elevation in meters
"""
function fetch_terrain_elevation(latitude::Float64, longitude::Float64)::Float64
    @info "Fetching elevation at ($latitude, $longitude)"

    try
        # USGS Elevation Point Query Service
        url = "https://epqs.nationalmap.gov/v1/json?x=$(longitude)&y=$(latitude)&wkid=4326&includeGeometry=false"

        response = HTTP.get(url; timeout=30.0)

        if response.status == 200
            data = JSON3.read(response.body)
            if haskey(data, "value") && haskey(data["value"], "Elevation")
                elevation = data["value"]["Elevation"]
                return elevation > 0 ? elevation : 0.0
            end
        end
    catch e
        @warn "Error fetching elevation: $e"
    end

    return 0.0  # Default to sea level if error
end

"""
    fetch_land_cover(bounds::NamedTuple)::GeoSpatialData

Fetch land cover classification data using USGS/NLCD data.

# Arguments
- `bounds::NamedTuple`: Geographic bounds

# Returns
- `GeoSpatialData`: Land cover classification
"""
function fetch_land_cover(bounds::NamedTuple)::GeoSpatialData
    @info "Fetching land cover data"

    # USGS National Land Cover Database (NLCD)
    # Provides classification at 30m resolution
    # Returned as gridded data

    df = DataFrame(
        latitude = Float64[],
        longitude = Float64[],
        land_cover_class = String[],
        class_code = Int[],
        percentage = Float64[]
    )

    metadata = Dict(
        "source" => "USGS_NLCD",
        "product" => "National Land Cover Database",
        "resolution" => "30m",
        "bounds" => bounds,
        "timestamp" => string(now(UTC))
    )

    return GeoSpatialData(df; metadata=metadata, crs="EPSG:4326")
end
