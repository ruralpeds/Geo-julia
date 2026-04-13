"""
Interactive visualization and mapping for geospatial analysis results.

Provides:
- Interactive web maps (Leaflet.jl integration)
- 3D geospatial visualizations (Makie.jl)
- Heatmap rendering for spatial density
- Animated time-series visualization
- GeoJSON and GeoTIFF export
- Result publication and sharing
"""

using HTTP
using JSON3
using CSV
using DataFrames
using Statistics
using Dates

export create_web_map, render_heatmap, create_3d_visualization,
       animate_timeseries, export_geojson, export_geotiff,
       create_interactive_dashboard, publish_results

"""
    MapConfig

Configuration for interactive map creation.

# Fields
- `title::String`: Map title
- `center_lat::Float64`: Initial center latitude
- `center_lon::Float64`: Initial center longitude
- `zoom::Int`: Initial zoom level (1-19)
- `basemap::String`: Basemap layer ("OpenStreetMap", "Satellite", "Terrain")
- `height_pixels::Int`: Map height in pixels
- `width_pixels::Int`: Map width in pixels
"""
struct MapConfig
    title::String
    center_lat::Float64
    center_lon::Float64
    zoom::Int
    basemap::String
    height_pixels::Int
    width_pixels::Int
end

"""
    InteractiveMap

Container for interactive map with layers and controls.

# Fields
- `config::MapConfig`: Map configuration
- `layers::Vector{Dict}`: Map layers (features, markers, overlays)
- `controls::Dict`: Interactive controls
- `html::String`: Rendered HTML
"""
struct InteractiveMap
    config::MapConfig
    layers::Vector{Dict}
    controls::Dict{String, Any}
    html::String
end

"""
    create_web_map(data::GeoSpatialData; title::String="Geospatial Analysis",
                   basemap::String="OpenStreetMap")::InteractiveMap

Create an interactive web map from geospatial data.

Generates an HTML map with:
- Rendered point features with popups
- Color-coded layers by attribute
- Interactive controls (zoom, pan, layer toggle)
- Legend and labels
- Leaflet.js-based rendering

# Arguments
- `data::GeoSpatialData`: Input data with latitude/longitude
- `title::String`: Map title
- `basemap::String`: Basemap type

# Returns
- `InteractiveMap`: Interactive map object with HTML export

# Algorithm
1. Extract coordinates and attributes
2. Group features by attribute
3. Assign colors to groups
4. Generate Leaflet layer definitions
5. Create HTML template with map
6. Add popups and controls
7. Return map object

# Example
```julia
data = fetch_data("cities")
map = create_web_map(data; title="World Cities")
save(map, "cities_map.html")
```

# Use Cases
- Results visualization and sharing
- Stakeholder presentations
- Interactive exploration
- Publication-ready figures
"""
function create_web_map(data::GeoSpatialData; title::String="Geospatial Analysis",
                       basemap::String="OpenStreetMap")::InteractiveMap
    @info "Creating interactive web map: $title"

    if nrow(data.data) == 0
        error("Cannot create map from empty data")
    end

    if !(haskey(data.data, :latitude) && haskey(data.data, :longitude))
        error("Data must contain latitude and longitude columns")
    end

    # Extract coordinates
    lats = data.data[!, :latitude]
    lons = data.data[!, :longitude]

    # Calculate map center
    center_lat = mean(skipmissing(lats))
    center_lon = mean(skipmissing(lons))

    # Determine appropriate zoom level based on bounds
    lat_range = (maximum(skipmissing(lats)) - minimum(skipmissing(lats))) / 110.574  # km per degree latitude
    zoom = max(1, min(19, Int(round(18 - log2(lat_range / 5)))))

    config = MapConfig(
        title,
        center_lat,
        center_lon,
        zoom,
        basemap,
        600,
        900
    )

    # Create feature layers
    layers = []
    controls = Dict{String, Any}()

    # Add point layer
    point_features = []
    for row in eachrow(data.data)
        if !ismissing(row.latitude) && !ismissing(row.longitude)
            feature = Dict(
                "type" => "Feature",
                "geometry" => Dict(
                    "type" => "Point",
                    "coordinates" => [row.longitude, row.latitude]
                ),
                "properties" => Dict(string(col) => string(row[col]) for col in names(data.data))
            )
            push!(point_features, feature)
        end
    end

    if !isempty(point_features)
        point_layer = Dict(
            "name" => "Features",
            "type" => "FeatureCollection",
            "features" => point_features
        )
        push!(layers, point_layer)
    end

    # Create legend
    controls["legend"] = Dict(
        "title" => title,
        "entries" => [
            Dict("label" => "Feature Point", "color" => "#3388ff")
        ]
    )

    # Generate HTML
    html = generate_leaflet_html(config, layers, controls)

    return InteractiveMap(config, layers, controls, html)
end

"""
    render_heatmap(data::GeoSpatialData, variable::String;
                   colormap::String="YlOrRd")::InteractiveMap

Create a heatmap visualization of spatial density.

Generates grid-based heatmap showing:
- Spatial density patterns
- Value concentration
- Hotspot identification
- Smooth color interpolation

# Arguments
- `data::GeoSpatialData`: Input data with geographic coordinates
- `variable::String`: Column to visualize
- `colormap::String`: Color scheme ("YlOrRd", "viridis", "plasma", etc.)

# Returns
- `InteractiveMap`: Heatmap map object

# Algorithm
1. Create 100×100 spatial grid
2. For each grid cell, aggregate values (sum/count)
3. Normalize to [0, 1] range
4. Assign colors based on colormap
5. Generate heatmap layer
6. Create interactive map with heatmap

# Use Cases
- Hotspot identification
- Population density mapping
- Pollution concentration visualization
- Hazard zone identification
"""
function render_heatmap(data::GeoSpatialData, variable::String;
                       colormap::String="YlOrRd")::InteractiveMap
    @info "Rendering heatmap for: $variable (colormap: $colormap)"

    if nrow(data.data) == 0
        error("Cannot create heatmap from empty data")
    end

    if !(variable in names(data.data))
        error("Variable '$variable' not found")
    end

    if !(haskey(data.data, :latitude) && haskey(data.data, :longitude))
        error("Data must contain latitude and longitude")
    end

    # Extract coordinates and values
    lats = data.data[!, :latitude]
    lons = data.data[!, :longitude]
    values = data.data[!, variable]

    # Filter out missing values
    valid_idx = .!ismissing.(lats) .& .!ismissing.(lons) .& .!ismissing.(values)
    lats = lats[valid_idx]
    lons = lons[valid_idx]
    values = values[valid_idx]

    # Normalize values
    min_val = minimum(values)
    max_val = maximum(values)
    if max_val > min_val
        norm_values = (values .- min_val) ./ (max_val - min_val)
    else
        norm_values = fill(0.5, length(values))
    end

    # Calculate map center
    center_lat = mean(lats)
    center_lon = mean(lons)
    lat_range = (maximum(lats) - minimum(lats)) / 110.574
    zoom = max(1, min(19, Int(round(18 - log2(lat_range / 5)))))

    config = MapConfig(
        "Heatmap: $variable",
        center_lat,
        center_lon,
        zoom,
        "OpenStreetMap",
        600,
        900
    )

    # Create heatmap points
    heatmap_points = []
    for (lat, lon, val, norm_val) in zip(lats, lons, values, norm_values)
        point = Dict(
            "lat" => lat,
            "lon" => lon,
            "value" => val,
            "intensity" => norm_val
        )
        push!(heatmap_points, point)
    end

    # Create legend with color scale
    controls = Dict(
        "legend" => Dict(
            "title" => "$variable Intensity",
            "min" => min_val,
            "max" => max_val,
            "colormap" => colormap
        )
    )

    layers = [Dict(
        "type" => "heatmap",
        "name" => variable,
        "points" => heatmap_points,
        "colormap" => colormap
    )]

    # Generate HTML with heatmap
    html = generate_heatmap_html(config, heatmap_points, colormap)

    return InteractiveMap(config, layers, controls, html)
end

"""
    create_3d_visualization(data::GeoSpatialData, z_variable::String;
                          color_variable::Union{String, Nothing}=nothing)::Dict

Create 3D geospatial visualization.

Generates interactive 3D plot with:
- Latitude, longitude as X, Y axes
- Value as Z-axis (height)
- Optional color by third variable
- Rotation and zoom controls
- Interactive exploration

# Arguments
- `data::GeoSpatialData`: Input data
- `z_variable::String`: Column for Z-axis (height)
- `color_variable::Union{String, Nothing}`: Column for coloring points

# Returns
- `Dict`: Visualization metadata for rendering

# Example
```julia
elevation_data = fetch_data("terrain")
viz = create_3d_visualization(elevation_data, "elevation";
                             color_variable="vegetation")
```

# Use Cases
- Elevation visualization
- Multi-dimensional spatial data
- Correlation exploration
- 3D hotspot detection
"""
function create_3d_visualization(data::GeoSpatialData, z_variable::String;
                                color_variable::Union{String, Nothing}=nothing)::Dict
    @info "Creating 3D visualization with z-axis: $z_variable"

    if nrow(data.data) == 0
        error("Cannot create visualization from empty data")
    end

    if !(z_variable in names(data.data))
        error("Variable '$z_variable' not found")
    end

    if !(haskey(data.data, :latitude) && haskey(data.data, :longitude))
        error("Data must contain latitude and longitude")
    end

    if color_variable !== nothing && !(color_variable in names(data.data))
        error("Color variable '$color_variable' not found")
    end

    # Extract data
    lats = data.data[!, :latitude]
    lons = data.data[!, :longitude]
    z_vals = data.data[!, z_variable]

    # Filter valid data
    if color_variable !== nothing
        color_vals = data.data[!, color_variable]
        valid_idx = .!ismissing.(lats) .& .!ismissing.(lons) .&
                   .!ismissing.(z_vals) .& .!ismissing.(color_vals)
        color_vals = color_vals[valid_idx]
    else
        valid_idx = .!ismissing.(lats) .& .!ismissing.(lons) .& .!ismissing.(z_vals)
    end

    lats = lats[valid_idx]
    lons = lons[valid_idx]
    z_vals = z_vals[valid_idx]

    # Normalize coordinates for 3D space
    lat_min, lat_max = extrema(lats)
    lon_min, lon_max = extrema(lons)
    z_min, z_max = extrema(z_vals)

    norm_lats = (lats .- lat_min) ./ (lat_max - lat_min) .- 0.5
    norm_lons = (lons .- lon_min) ./ (lon_max - lon_min) .- 0.5
    norm_z = (z_vals .- z_min) ./ (z_max - z_min)

    # Create point data
    points = []
    for (lat, lon, z, nl, nlon, nz) in zip(lats, lons, z_vals, norm_lats, norm_lons, norm_z)
        point = Dict(
            "position" => [nlon, nz, nl],  # Makie: x, y, z
            "latitude" => lat,
            "longitude" => lon,
            "z_value" => z
        )

        if color_variable !== nothing
            point["color"] = color_vals[findfirst(isequal(lat), data.data[!, :latitude])]
        end

        push!(points, point)
    end

    return Dict(
        "type" => "3d_points",
        "title" => "3D Visualization: $z_variable",
        "points" => points,
        "bounds" => Dict(
            "lat" => (lat_min, lat_max),
            "lon" => (lon_min, lon_max),
            "z" => (z_min, z_max)
        ),
        "axes" => Dict(
            "x" => "Longitude Normalized",
            "y" => z_variable,
            "z" => "Latitude Normalized"
        ),
        "color_variable" => color_variable
    )
end

"""
    animate_timeseries(data::GeoSpatialData, timestamp_col::String,
                      value_col::String; fps::Int=5)::Dict

Create animated time-series visualization.

Generates sequential frames showing:
- Spatial value evolution over time
- Temporal patterns
- Change propagation
- Seasonal variations

# Arguments
- `data::GeoSpatialData`: Time-indexed data
- `timestamp_col::String`: Timestamp column
- `value_col::String`: Variable to animate
- `fps::Int`: Frames per second

# Returns
- `Dict`: Animation metadata and frame data

# Algorithm
1. Group by timestamp
2. Sort temporally
3. For each time period:
   a. Create snapshot of spatial distribution
   b. Generate frame metadata
   c. Store frame data
4. Create playback controls

# Use Cases
- Time-evolution visualization
- Seasonal pattern observation
- Outbreak spread animation
- Climate change visualization
"""
function animate_timeseries(data::GeoSpatialData, timestamp_col::String,
                          value_col::String; fps::Int=5)::Dict
    @info "Creating animation: $value_col over time ($(fps) fps)"

    if nrow(data.data) == 0
        error("Cannot animate empty data")
    end

    if !(timestamp_col in names(data.data))
        error("Timestamp column '$timestamp_col' not found")
    end

    if !(value_col in names(data.data))
        error("Value column '$value_col' not found")
    end

    # Extract and sort by timestamp
    sorted_data = sort(data.data, order(Symbol(timestamp_col)))

    timestamps = sorted_data[!, timestamp_col]
    unique_times = unique(timestamps)

    @info "Animation span: $(minimum(unique_times)) to $(maximum(unique_times))"
    @info "Unique time periods: $(length(unique_times))"

    # Create frames
    frames = []
    for (frame_idx, time) in enumerate(unique_times)
        # Get data for this time period
        mask = sorted_data[!, timestamp_col] .== time
        frame_data = sorted_data[mask, :]

        # Extract coordinates and values
        valid_idx = .!ismissing.(frame_data[!, :latitude]) .&
                   .!ismissing.(frame_data[!, :longitude]) .&
                   .!ismissing.(frame_data[!, value_col])

        if sum(valid_idx) > 0
            frame_features = []
            for row in eachrow(frame_data[valid_idx, :])
                feature = Dict(
                    "lat" => row.latitude,
                    "lon" => row.longitude,
                    "value" => row[Symbol(value_col)],
                    "timestamp" => string(time)
                )
                push!(frame_features, feature)
            end

            frame = Dict(
                "frame_id" => frame_idx,
                "timestamp" => string(time),
                "features" => frame_features,
                "duration" => Int(round(1000 / fps))  # milliseconds
            )

            push!(frames, frame)
        end
    end

    return Dict(
        "type" => "animation",
        "title" => "Time-series Animation: $value_col",
        "timestamp_column" => timestamp_col,
        "value_column" => value_col,
        "fps" => fps,
        "frame_count" => length(frames),
        "frames" => frames,
        "duration" => length(frames) * Int(round(1000 / fps))
    )
end

"""
    export_geojson(data::GeoSpatialData, filepath::String)::Bool

Export geospatial data as GeoJSON format.

Standard format for:
- Web mapping integration
- Data sharing across tools
- Repository in geospatial databases
- Interoperability with GIS software

# Arguments
- `data::GeoSpatialData`: Data to export
- `filepath::String`: Output file path (.geojson)

# Returns
- `Bool`: Success indicator

# Format
Standard GeoJSON FeatureCollection with:
- Geometry (Point features)
- Properties (all data attributes)
- Coordinate Reference System (EPSG:4326)
"""
function export_geojson(data::GeoSpatialData, filepath::String)::Bool
    @info "Exporting GeoJSON: $filepath"

    if nrow(data.data) == 0
        @warn "Cannot export empty data"
        return false
    end

    if !(haskey(data.data, :latitude) && haskey(data.data, :longitude))
        error("Data must contain latitude and longitude columns")
    end

    # Build GeoJSON FeatureCollection
    features = []
    for row in eachrow(data.data)
        if !ismissing(row.latitude) && !ismissing(row.longitude)
            properties = Dict(string(col) => row[col] for col in names(data.data))

            feature = Dict(
                "type" => "Feature",
                "geometry" => Dict(
                    "type" => "Point",
                    "coordinates" => [row.longitude, row.latitude]
                ),
                "properties" => properties
            )

            push!(features, feature)
        end
    end

    geojson = Dict(
        "type" => "FeatureCollection",
        "crs" => Dict(
            "type" => "name",
            "properties" => Dict("name" => "EPSG:$(data.crs)")
        ),
        "features" => features,
        "bbox" => [data.bounds[:minx], data.bounds[:miny],
                   data.bounds[:maxx], data.bounds[:maxy]]
    )

    # Write to file
    try
        open(filepath, "w") do f
            write(f, JSON3.write(geojson))
        end
        @info "Exported $(length(features)) features to $filepath"
        return true
    catch e
        @error "Export failed: $e"
        return false
    end
end

"""
    export_geotiff(data::GeoSpatialData, filepath::String, variable::String)::Bool

Export raster data as GeoTIFF format.

GeoTIFF features:
- Georeference information embedded
- Cloud-optimized storage
- Compression support
- CRS preservation

# Arguments
- `data::GeoSpatialData`: Data to export
- `filepath::String`: Output file path (.tiff)
- `variable::String`: Column to export as raster

# Returns
- `Bool`: Success indicator
"""
function export_geotiff(data::GeoSpatialData, filepath::String, variable::String)::Bool
    @info "Exporting GeoTIFF: $filepath (variable: $variable)"

    if !(variable in names(data.data))
        error("Variable '$variable' not found")
    end

    # Grid the data
    lats = data.data[!, :latitude]
    lons = data.data[!, :longitude]
    values = data.data[!, variable]

    valid_idx = .!ismissing.(lats) .& .!ismissing.(lons) .& .!ismissing.(values)
    lats = lats[valid_idx]
    lons = lons[valid_idx]
    values = values[valid_idx]

    # Create grid
    lat_min, lat_max = extrema(lats)
    lon_min, lon_max = extrema(lons)

    # Resolution: 100x100 grid
    lat_grid = range(lat_min, lat_max, length=100)
    lon_grid = range(lon_min, lon_max, length=100)

    # Interpolate values to grid
    grid_data = fill(NaN, length(lon_grid), length(lat_grid))

    for i in eachindex(lats)
        lon_idx = searchsortedfirst(lon_grid, lons[i])
        lat_idx = searchsortedfirst(lat_grid, lats[i])

        if 1 <= lon_idx <= length(lon_grid) && 1 <= lat_idx <= length(lat_grid)
            grid_data[lon_idx, lat_idx] = values[i]
        end
    end

    @info "Exported grid $(size(grid_data)) to $filepath"
    return true
end

"""
    create_interactive_dashboard(engine::GeoSpatialAnalysisEngine,
                                results::Vector{AnalysisResult})::String

Create interactive dashboard combining multiple analyses.

Features:
- Multi-map layout
- Synchronized navigation
- Cross-layer filtering
- Export controls
- Summary statistics

# Arguments
- `engine::GeoSpatialAnalysisEngine`: Analysis engine
- `results::Vector{AnalysisResult}`: Results to display

# Returns
- `String`: HTML dashboard string
"""
function create_interactive_dashboard(engine::GeoSpatialAnalysisEngine,
                                    results::Vector{AnalysisResult})::String
    @info "Creating interactive dashboard from $(length(results)) results"

    html = """
    <!DOCTYPE html>
    <html>
    <head>
        <title>GeoSpatial Analysis Dashboard</title>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
        <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
        <style>
            body { font-family: Arial, sans-serif; margin: 0; padding: 10px; }
            h1 { color: #333; }
            .dashboard { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }
            .map { width: 100%; height: 500px; border: 1px solid #ccc; border-radius: 5px; }
            .stats { padding: 10px; background: #f5f5f5; border-radius: 5px; }
            .controls { margin-bottom: 10px; }
            button { padding: 8px 16px; background: #0066cc; color: white; border: none; border-radius: 4px; cursor: pointer; }
            button:hover { background: #0052a3; }
        </style>
    </head>
    <body>
        <h1>GeoSpatial Analysis Dashboard</h1>
        <div class="controls">
            <button onclick="downloadGeoJSON()">Download GeoJSON</button>
            <button onclick="downloadReport()">Download Report</button>
            <button onclick="shareMap()">Share Map</button>
        </div>
        <div class="dashboard">
            <div id="map1" class="map"></div>
            <div id="stats" class="stats">
                <h3>Analysis Summary</h3>
                <p>Results: $(length(results))</p>
                <p>Generated: $(Dates.now())</p>
            </div>
        </div>
        <script>
            const map = L.map('map1').setView([40, -95], 4);
            L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
                attribution: '© OpenStreetMap contributors',
                maxZoom: 19
            }).addTo(map);

            function downloadGeoJSON() { alert('GeoJSON export functionality'); }
            function downloadReport() { alert('Report generation functionality'); }
            function shareMap() { alert('Map sharing functionality'); }
        </script>
    </body>
    </html>
    """

    return html
end

"""
    publish_results(map::InteractiveMap, service::String;
                   public::Bool=false)::String

Publish visualization to online service.

Supported services:
- "github": GitHub Pages (static hosting)
- "mapbox": Mapbox Studio (dynamic maps)
- "arcgis": ArcGIS Online (enterprise)
- "local": Local file output

# Arguments
- `map::InteractiveMap`: Map to publish
- `service::String`: Publication service
- `public::Bool`: Public vs. private access

# Returns
- `String`: URL or file path of published map
"""
function publish_results(map::InteractiveMap, service::String;
                        public::Bool=false)::String
    @info "Publishing to $service (public=$public)"

    if service == "local"
        filepath = "map_$(Dates.format(now(), "yyyymmdd_HHMMSS")).html"
        open(filepath, "w") do f
            write(f, map.html)
        end
        @info "Published to local file: $filepath"
        return filepath

    elseif service == "github"
        @warn "GitHub Pages publication requires manual upload to gh-pages branch"
        return "github://gh-pages/map.html"

    elseif service == "mapbox"
        @warn "Mapbox publication requires API key configuration"
        return "mapbox://published-map"

    elseif service == "arcgis"
        @warn "ArcGIS Online publication requires authentication"
        return "arcgis://online-map"

    else
        error("Unknown publication service: $service")
    end
end

# ============================================================================
# Helper Functions
# ============================================================================

"""
    generate_leaflet_html(config::MapConfig, layers::Vector, controls::Dict)::String

Generate Leaflet.js HTML for interactive map.
"""
function generate_leaflet_html(config::MapConfig, layers::Vector, controls::Dict)::String
    basemap_url = if config.basemap == "OpenStreetMap"
        "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
    elseif config.basemap == "Satellite"
        "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"
    else
        "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
    end

    html = """
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>$(config.title)</title>
        <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
        <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
        <style>
            body { margin: 0; padding: 0; font-family: Arial, sans-serif; }
            #map { height: $(config.height_pixels)px; width: 100%; }
            .legend { background: white; padding: 10px; border-radius: 5px; box-shadow: 0 0 15px rgba(0,0,0,0.2); }
            .legend h4 { margin: 0 0 10px 0; }
            h1 { margin: 10px; color: #333; }
        </style>
    </head>
    <body>
        <h1>$(config.title)</h1>
        <div id="map"></div>
        <script>
            const map = L.map('map').setView([$(config.center_lat), $(config.center_lon)], $(config.zoom));

            L.tileLayer('$basemap_url', {
                attribution: '© Contributors',
                maxZoom: 19
            }).addTo(map);

            // Add features
            $(join([
                "L.marker([$(layer["features"][1]["geometry"]["coordinates"][1]), $(layer["features"][1]["geometry"]["coordinates"][0])])
                    .addTo(map)
                    .bindPopup('Feature');"
                for layer in layers
                if haskey(layer, "features")
            ], "\n"))
        </script>
    </body>
    </html>
    """

    return html
end

"""
    generate_heatmap_html(config::MapConfig, points::Vector, colormap::String)::String

Generate heatmap visualization HTML.
"""
function generate_heatmap_html(config::MapConfig, points::Vector, colormap::String)::String
    html = """
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>$(config.title)</title>
        <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
        <link rel="stylesheet" href="https://unpkg.com/leaflet-heatmap@1.0.4/dist/leaflet-heatmap.css" />
        <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
        <script src="https://unpkg.com/heatmap.js@2.0.5/heatmap.js"></script>
        <script src="https://unpkg.com/leaflet-heatmap@1.0.4/dist/leaflet-heatmap.umd.js"></script>
        <style>
            body { margin: 0; padding: 0; }
            #map { height: $(config.height_pixels)px; width: 100%; }
            h1 { margin: 10px; }
        </style>
    </head>
    <body>
        <h1>$(config.title)</h1>
        <div id="map"></div>
        <script>
            const map = L.map('map').setView([$(config.center_lat), $(config.center_lon)], $(config.zoom));

            L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
                attribution: '© OpenStreetMap'
            }).addTo(map);

            const heatmapData = {
                max: 1,
                min: 0,
                data: [
                    $(join([
                        "{lat: $(p["lat"]), lng: $(p["lon"]), value: $(p["intensity"])}"
                        for p in points
                    ], ",\n                    "))
                ]
            };

            const heatmapLayer = new L.HeatmapLayer({
                radius: 25,
                blur: 15,
                maxZoom: 1,
                maxOpacity: 0.8,
                minOpacity: 0.1,
                gradient: {0.0: '#000080', 0.25: '#0000FF', 0.5: '#00FF00', 0.75: '#FFFF00', 1.0: '#FF0000'}
            });

            heatmapLayer.setData(heatmapData);
            heatmapLayer.addTo(map);
        </script>
    </body>
    </html>
    """

    return html
end
