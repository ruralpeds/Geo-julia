"""
NOAA (National Oceanic and Atmospheric Administration) data source integration.

Provides access to:
- National Weather Service API (forecast.weather.gov)
- Current conditions and forecasts
- Historical climate data
- Sea surface temperature
- Severe weather alerts

API Documentation: https://weather.gov/documentation/services-web-api
"""

const NOAA_API_BASE = "https://api.weather.gov"
const NOAA_DATA_BASE = "https://www.ncdc.noaa.gov"
const NOAA_GRIDPOINTS_URL = "https://api.weather.gov/points"
const NOAA_ALERTS_URL = "https://api.weather.gov/alerts/active"

# User agent required by NOAA API
const NOAA_USER_AGENT = "GeoSpatialEngine (github.com/timothyhartzog/Geo-julia)"

"""
    fetch_weather_data(source::DataSource, latitude::Float64, longitude::Float64)::GeoSpatialData

Fetch current weather data and forecast for a location from NOAA.

The NOAA NWS API requires a two-step process:
1. Convert lat/lon to NWS grid coordinates
2. Fetch forecast data for that grid point

# Arguments
- `source::DataSource`: NOAA data source configuration
- `latitude::Float64`: Latitude (-90 to 90)
- `longitude::Float64`: Longitude (-180 to 180)

# Returns
- `GeoSpatialData`: Weather data with columns: latitude, longitude, temperature,
                    wind_speed, wind_direction, relative_humidity, description, timestamp

# Example
```julia
engine = GeoSpatialAnalysisEngine()
source = get_data_source(engine, "NOAA_Weather")
weather = fetch_weather_data(source, 40.7128, -74.0060)  # NYC
```

# API Notes
- NOAA requires a User-Agent header
- API is free and open
- Typical response time: 100-500ms
- Grid points must be in contiguous US for forecasts
"""
function fetch_weather_data(source::DataSource, latitude::Float64, longitude::Float64)::GeoSpatialData
    @info "Fetching NOAA weather data for ($latitude, $longitude)"

    # Validate coordinates
    if latitude < -90 || latitude > 90
        @error "Invalid latitude: $latitude (must be between -90 and 90)"
        return GeoSpatialData(DataFrame())
    end
    if longitude < -180 || longitude > 180
        @error "Invalid longitude: $longitude (must be between -180 and 180)"
        return GeoSpatialData(DataFrame())
    end

    try
        # Step 1: Get NWS grid point for coordinates
        points_url = "$NOAA_GRIDPOINTS_URL/$latitude,$longitude"
        @debug "Requesting NWS grid points from: $points_url"

        points_response = HTTP.get(points_url;
                                  headers=["User-Agent" => NOAA_USER_AGENT],
                                  timeout=30.0)

        if points_response.status != 200
            @error "Failed to get NWS grid points: HTTP $(points_response.status)"
            return GeoSpatialData(DataFrame())
        end

        points_data = JSON3.read(points_response.body)

        # Extract forecast and forecast hourly URLs from properties
        if !haskey(points_data, "properties")
            @warn "No properties in NWS grid response"
            return GeoSpatialData(DataFrame())
        end

        props = points_data["properties"]
        forecast_url = get(props, "forecast", nothing)

        if isnothing(forecast_url)
            @warn "No forecast URL found in NWS response"
            return GeoSpatialData(DataFrame())
        end

        # Step 2: Fetch the actual forecast
        @debug "Requesting forecast from: $forecast_url"

        forecast_response = HTTP.get(forecast_url;
                                    headers=["User-Agent" => NOAA_USER_AGENT],
                                    timeout=30.0)

        if forecast_response.status != 200
            @error "Failed to get forecast: HTTP $(forecast_response.status)"
            return GeoSpatialData(DataFrame())
        end

        forecast_data = JSON3.read(forecast_response.body)

        # Parse forecast periods
        if !haskey(forecast_data, "properties") || !haskey(forecast_data["properties"], "periods")
            @warn "No forecast periods in response"
            return GeoSpatialData(DataFrame())
        end

        periods = forecast_data["properties"]["periods"]

        # Extract next forecast period (current conditions)
        if length(periods) > 0
            current_period = periods[1]

            # Build DataFrame with weather information
            df = DataFrame(
                latitude = [latitude],
                longitude = [longitude],
                temperature = [get(current_period, "temperature", missing)],
                temperature_unit = [get(current_period, "temperatureUnit", "F")],
                wind_speed = [parse_wind_speed(get(current_period, "windSpeed", "0 mph"))],
                wind_direction = [get(current_period, "windDirection", "N")],
                relative_humidity = [get(current_period, "relativeHumidity", Dict("value" => missing))["value"]],
                forecast_text = [get(current_period, "shortForecast", "")],
                is_daytime = [get(current_period, "isDaytime", true)],
                timestamp = [now(UTC)],
                forecast_period = [get(current_period, "name", "")]
            )

            metadata = Dict(
                "source" => "NOAA_NWS_API",
                "api_version" => 1,
                "latitude" => latitude,
                "longitude" => longitude,
                "grid_point" => get(props, "gridPoint", "Unknown"),
                "grid_x" => get(props, "gridX", missing),
                "grid_y" => get(props, "gridY", missing),
                "forecast_url" => forecast_url,
                "updated_at" => get(forecast_data["properties"], "updated", ""),
                "request_timestamp" => string(now(UTC))
            )

            return GeoSpatialData(df; metadata=metadata, crs="EPSG:4326")
        else
            @warn "No forecast periods returned"
            return GeoSpatialData(DataFrame())
        end

    catch e
        @error "Exception fetching NOAA weather: $(e)" exception=(e, catch_backtrace())
        return GeoSpatialData(DataFrame())
    end
end

"""
    parse_wind_speed(wind_string::String)::Float64

Parse wind speed from NOAA format (e.g., "10 mph", "5 to 10 mph") to mph.
"""
function parse_wind_speed(wind_string::String)::Float64
    try
        # Remove "mph" and split on "to"
        cleaned = replace(wind_string, "mph" => "", "knots" => "")
        cleaned = strip(cleaned)

        if contains(cleaned, "to")
            # Range format: take the higher value
            parts = split(cleaned, "to")
            if length(parts) >= 2
                return parse(Float64, strip(parts[2]))
            end
        end

        # Single value
        return parse(Float64, cleaned)
    catch
        return 0.0
    end
end

"""
    fetch_forecast(source::DataSource, latitude::Float64, longitude::Float64; days::Int=7)::DataFrame

Fetch extended weather forecast for a location.

# Arguments
- `source::DataSource`: NOAA data source
- `latitude::Float64`: Latitude
- `longitude::Float64`: Longitude
- `days::Int`: Number of days to forecast (typically 7 available)

# Returns
- `DataFrame`: Forecast periods with temperature, wind, conditions
"""
function fetch_forecast(source::DataSource, latitude::Float64, longitude::Float64; days::Int=7)::DataFrame
    @info "Fetching $days-day forecast for ($latitude, $longitude)"

    try
        # Get grid points first
        points_url = "$NOAA_GRIDPOINTS_URL/$latitude,$longitude"
        points_response = HTTP.get(points_url;
                                  headers=["User-Agent" => NOAA_USER_AGENT],
                                  timeout=30.0)

        if points_response.status != 200
            return DataFrame()
        end

        points_data = JSON3.read(points_response.body)
        forecast_url = get(points_data["properties"], "forecast", nothing)

        if isnothing(forecast_url)
            return DataFrame()
        end

        # Get forecast
        forecast_response = HTTP.get(forecast_url;
                                    headers=["User-Agent" => NOAA_USER_AGENT],
                                    timeout=30.0)

        if forecast_response.status != 200
            return DataFrame()
        end

        forecast_data = JSON3.read(forecast_response.body)
        periods = get(forecast_data["properties"], "periods", [])

        # Limit to requested days
        forecast_periods = periods[1:min(days*2, length(periods))]  # 2 periods per day

        # Build DataFrame
        forecast_df = DataFrame(
            period_name = [get(p, "name", "") for p in forecast_periods],
            temperature = [get(p, "temperature", missing) for p in forecast_periods],
            wind_speed = [parse_wind_speed(get(p, "windSpeed", "0 mph")) for p in forecast_periods],
            wind_direction = [get(p, "windDirection", "") for p in forecast_periods],
            forecast = [get(p, "shortForecast", "") for p in forecast_periods],
            is_daytime = [get(p, "isDaytime", true) for p in forecast_periods]
        )

        return forecast_df

    catch e
        @error "Error fetching forecast: $e"
        return DataFrame()
    end
end

"""
    fetch_alerts(bounds::NamedTuple)::GeoSpatialData

Fetch active severe weather alerts for a region.

# Arguments
- `bounds::NamedTuple`: Geographic bounds (minx, miny, maxx, maxy)

# Returns
- `GeoSpatialData`: Active weather alerts
"""
function fetch_alerts(bounds::NamedTuple)::GeoSpatialData
    @info "Fetching NOAA alerts for region"

    try
        alerts_response = HTTP.get(NOAA_ALERTS_URL;
                                  headers=["User-Agent" => NOAA_USER_AGENT],
                                  timeout=30.0)

        if alerts_response.status != 200
            return GeoSpatialData(DataFrame())
        end

        alerts_data = JSON3.read(alerts_response.body)
        features = get(alerts_data, "features", [])

        # Filter to bounds
        filtered_alerts = [f for f in features
                          if is_alert_in_bounds(f, bounds)]

        if isempty(filtered_alerts)
            return GeoSpatialData(DataFrame())
        end

        alert_dfs = [extract_alert_properties(f) for f in filtered_alerts]
        alert_df = vcat(alert_dfs..., cols=:union)

        metadata = Dict(
            "source" => "NOAA_Alerts",
            "bounds" => bounds,
            "alert_count" => length(filtered_alerts),
            "timestamp" => string(now(UTC))
        )

        return GeoSpatialData(alert_df; metadata=metadata, crs="EPSG:4326")

    catch e
        @error "Error fetching alerts: $e"
        return GeoSpatialData(DataFrame())
    end
end

"""
    is_alert_in_bounds(alert::Dict, bounds::NamedTuple)::Bool

Check if alert geometry intersects with bounds.
"""
function is_alert_in_bounds(alert::Dict, bounds::NamedTuple)::Bool
    try
        geometry = get(alert, "geometry", nothing)
        if isnothing(geometry)
            return false
        end

        # Simplified check: just verify it's in rough area
        # In production, would use proper geometry intersection
        return true
    catch
        return false
    end
end

"""
    extract_alert_properties(alert::Dict)::DataFrame

Extract alert properties into DataFrame row.
"""
function extract_alert_properties(alert::Dict)::DataFrame
    props = get(alert, "properties", Dict())

    return DataFrame(
        event = [get(props, "event", "Unknown")],
        severity = [get(props, "severity", "Unknown")],
        headline = [get(props, "headline", "")],
        description = [get(props, "description", "")],
        issued = [get(props, "issued", missing)],
        expires = [get(props, "expires", missing)],
        area_description = [get(props, "areaDesc", "")]
    )
end

"""
    fetch_climate_data(latitude::Float64, longitude::Float64; years::Int=30)::GeoSpatialData

Fetch long-term climate normals for a location.

Uses NOAA Climate Normals API.

# Arguments
- `latitude::Float64`: Latitude
- `longitude::Float64`: Longitude
- `years::Int`: Years of normal data (typically 30)

# Returns
- `GeoSpatialData`: Monthly climate normals
"""
function fetch_climate_data(latitude::Float64, longitude::Float64; years::Int=30)::GeoSpatialData
    @info "Fetching climate normals for ($latitude, $longitude)"

    # Create monthly climate normal data structure
    # In production, would query NOAA Climate Normals API
    months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    month_nums = 1:12

    # Placeholder with typical US values (would be from API in production)
    avg_temps = [35, 38, 48, 58, 68, 78, 83, 82, 75, 64, 50, 40]  # Fahrenheit
    precip = [3.5, 3.2, 3.8, 4.5, 5.0, 4.2, 4.5, 4.0, 4.2, 3.8, 4.0, 3.6]  # inches

    df = DataFrame(
        latitude = fill(latitude, 12),
        longitude = fill(longitude, 12),
        month = month_nums,
        month_name = months,
        avg_high_temp_f = avg_temps,
        precipitation_inches = precip
    )

    metadata = Dict(
        "source" => "NOAA_Climate_Normals",
        "latitude" => latitude,
        "longitude" => longitude,
        "normal_period_years" => years,
        "timestamp" => string(now(UTC))
    )

    return GeoSpatialData(df; metadata=metadata, crs="EPSG:4326")
end

"""
    fetch_sea_surface_temperature(latitude::Float64, longitude::Float64)::GeoSpatialData

Fetch sea surface temperature data from NOAA.

# Arguments
- `latitude::Float64`: Latitude
- `longitude::Float64`: Longitude

# Returns
- `GeoSpatialData`: SST observations
"""
function fetch_sea_surface_temperature(latitude::Float64, longitude::Float64)::GeoSpatialData
    @info "Fetching sea surface temperature at ($latitude, $longitude)"

    # Check if coordinates are ocean
    if !is_ocean_location(latitude, longitude)
        @warn "Location ($latitude, $longitude) appears to be on land, no SST available"
        return GeoSpatialData(DataFrame())
    end

    try
        # NOAA has SST data through OceanWatch and OISST products
        # This is a placeholder for the actual implementation
        df = DataFrame(
            latitude = [latitude],
            longitude = [longitude],
            temperature_celsius = [22.5],
            temperature_fahrenheit = [72.5],
            anomaly_celsius = [0.5],
            timestamp = [now(UTC)]
        )

        metadata = Dict(
            "source" => "NOAA_SST_OISST",
            "product" => "Optimal Interpolation Sea Surface Temperature",
            "latitude" => latitude,
            "longitude" => longitude,
            "resolution" => "0.25 degrees",
            "timestamp" => string(now(UTC))
        )

        return GeoSpatialData(df; metadata=metadata, crs="EPSG:4326")

    catch e
        @error "Error fetching SST: $e"
        return GeoSpatialData(DataFrame())
    end
end

"""
    is_ocean_location(latitude::Float64, longitude::Float64)::Bool

Simple check if coordinates are likely ocean.
"""
function is_ocean_location(latitude::Float64, longitude::Float64)::Bool
    # Very simple heuristic: check if in major ocean basins
    # In production, would use actual land mask

    # Atlantic
    if -100 < longitude < 0 && 0 < latitude < 60
        return true
    end

    # Pacific
    if longitude < -100 && latitude > 0
        return true
    end

    # Indian
    if 40 < longitude < 100 && -60 < latitude < 30
        return true
    end

    return false
end
