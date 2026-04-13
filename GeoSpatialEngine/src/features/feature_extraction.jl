"""
Feature extraction and engineering for geospatial machine learning.

Provides methods to:
- Extract spatial features from geometry
- Compute neighborhood statistics
- Generate temporal features
- Create distance-based features
- Normalize and scale features
- Handle missing values
"""

using Statistics
using StatsBase

"""
    extract_spatial_features(data::GeoSpatialData)::DataFrame

Extract geometric features from geospatial data.

Computes spatial characteristics including:
- Coordinates (latitude, longitude)
- Distance from origin
- Clustering indicators
- Neighbor counts

# Returns
- `DataFrame`: Original data with spatial features added
"""
function extract_spatial_features(data::GeoSpatialData)::DataFrame
    @info "Extracting spatial features from $(nrow(data.data)) features"

    if nrow(data.data) == 0
        return DataFrame()
    end

    result_df = copy(data.data)

    # Extract coordinate features
    if haskey(result_df, :latitude) && haskey(result_df, :longitude)
        lats = result_df[!, :latitude]
        lons = result_df[!, :longitude]

        # Distance from origin (centroid)
        center_lat = mean(skipmissing(lats))
        center_lon = mean(skipmissing(lons))

        result_df[!, :distance_from_centroid] = [
            haversine_distance(lat, lon, center_lat, center_lon)
            for (lat, lon) in zip(lats, lons)
        ]

        # Quadrant features (for spatial binning)
        result_df[!, :lat_quadrant] = [lat > center_lat ? 1 : 0 for lat in lats]
        result_df[!, :lon_quadrant] = [lon > center_lon ? 1 : 0 for lon in lons]

        # Spherical coordinates encoding
        lat_rad = deg2rad.(lats)
        lon_rad = deg2rad.(lons)

        result_df[!, :x_coord] = cos.(lat_rad) .* cos.(lon_rad)
        result_df[!, :y_coord] = cos.(lat_rad) .* sin.(lon_rad)
        result_df[!, :z_coord] = sin.(lat_rad)
    end

    return result_df
end

"""
    compute_neighborhood_statistics(data::GeoSpatialData, radius::Float64;
                                   statistic::String="mean")::DataFrame

Compute statistics of features within neighborhood of each point.

Useful for:
- Local trend analysis
- Feature aggregation
- Spatial smoothing
- Neighborhood characterization

# Arguments
- `data::GeoSpatialData`: Input data with numeric features
- `radius::Float64`: Neighborhood radius in meters
- `statistic::String`: Aggregation function ("mean", "median", "std", "count")

# Returns
- `DataFrame`: Data with neighborhood statistics added
"""
function compute_neighborhood_statistics(data::GeoSpatialData, radius::Float64;
                                        statistic::String="mean")::DataFrame
    @info "Computing $statistic neighborhood statistics (radius: $(radius)m)"

    if nrow(data.data) < 2
        return data.data
    end

    if !(haskey(data.data, :latitude) && haskey(data.data, :longitude))
        @warn "Latitude/longitude columns not found"
        return data.data
    end

    result_df = copy(data.data)
    lats = data.data[!, :latitude]
    lons = data.data[!, :longitude]

    # Find numeric columns for neighborhood stats
    numeric_cols = [col for col in names(result_df)
                   if eltype(result_df[!, col]) <: Number && !(col in [:latitude, :longitude])]

    if isempty(numeric_cols)
        @warn "No numeric columns found for neighborhood statistics"
        return result_df
    end

    # Compute neighborhood statistics
    for col in numeric_cols
        neighborhood_vals = [Float64[] for _ in 1:nrow(result_df)]

        for i in 1:nrow(result_df)
            for j in 1:nrow(result_df)
                if i != j
                    dist = haversine_distance(lats[i], lons[i], lats[j], lons[j])
                    if dist <= radius && !ismissing(result_df[j, col])
                        push!(neighborhood_vals[i], result_df[j, col])
                    end
                end
            end
        end

        # Compute requested statistic
        col_name = Symbol("$(col)_neighborhood_$(statistic)")

        result_df[!, col_name] = [
            if isempty(vals)
                missing
            elseif statistic == "mean"
                mean(vals)
            elseif statistic == "median"
                median(vals)
            elseif statistic == "std"
                std(vals)
            elseif statistic == "count"
                Float64(length(vals))
            else
                missing
            end
            for vals in neighborhood_vals
        ]
    end

    return result_df
end

"""
    extract_temporal_features(data::GeoSpatialData, timestamp_col::String)::DataFrame

Extract temporal features from timestamp data.

Generates:
- Day of week
- Month
- Season
- Hour of day
- Days since epoch
- Temporal cyclical encoding

# Arguments
- `data::GeoSpatialData`: Data with timestamp column
- `timestamp_col::String`: Name of timestamp column

# Returns
- `DataFrame`: Data with temporal features
"""
function extract_temporal_features(data::GeoSpatialData, timestamp_col::String)::DataFrame
    @info "Extracting temporal features from: $timestamp_col"

    if nrow(data.data) == 0
        return DataFrame()
    end

    if !(timestamp_col in names(data.data))
        @error "Timestamp column '$timestamp_col' not found"
        return data.data
    end

    result_df = copy(data.data)
    timestamps = result_df[!, timestamp_col]

    # Extract temporal components
    result_df[!, :year] = [year(t) for t in timestamps]
    result_df[!, :month] = [month(t) for t in timestamps]
    result_df[!, :day] = [day(t) for t in timestamps]
    result_df[!, :dayofweek] = [dayofweek(t) for t in timestamps]
    result_df[!, :dayofyear] = [dayofyear(t) for t in timestamps]
    result_df[!, :hour] = [hour(t) for t in timestamps]
    result_df[!, :minute] = [minute(t) for t in timestamps]

    # Cyclical encoding for periodic features
    result_df[!, :month_sin] = sin.(2π .* result_df[!, :month] ./ 12)
    result_df[!, :month_cos] = cos.(2π .* result_df[!, :month] ./ 12)
    result_df[!, :hour_sin] = sin.(2π .* result_df[!, :hour] ./ 24)
    result_df[!, :hour_cos] = cos.(2π .* result_df[!, :hour] ./ 24)

    # Season encoding
    result_df[!, :season] = [
        if month(t) in [12, 1, 2]
            "winter"
        elseif month(t) in [3, 4, 5]
            "spring"
        elseif month(t) in [6, 7, 8]
            "summer"
        else
            "autumn"
        end
        for t in timestamps
    ]

    # Is weekend
    result_df[!, :is_weekend] = [dayofweek(t) in [6, 7] ? 1 : 0 for t in timestamps]

    return result_df
end

"""
    create_interaction_features(data::DataFrame, cols::Vector{String})::DataFrame

Create interaction features between specified columns.

Useful for capturing non-linear relationships between features.

# Example
```julia
df = DataFrame(lat=[40, 41], lon=[-74, -73], temp=[20, 25])
interactions = create_interaction_features(df, ["lat", "temp"])
# Creates: lat_x_temp column
```
"""
function create_interaction_features(data::DataFrame, cols::Vector{String})::DataFrame
    @info "Creating interaction features for: $(join(cols, ", "))"

    result_df = copy(data)

    for i in 1:length(cols)-1
        for j in i+1:length(cols)
            col1, col2 = cols[i], cols[j]

            if col1 in names(result_df) && col2 in names(result_df)
                interaction_name = Symbol("$(col1)_x_$(col2)")
                result_df[!, interaction_name] = result_df[!, col1] .* result_df[!, col2]
            end
        end
    end

    return result_df
end

"""
    normalize_features(features::DataFrame; method::String="standardize")::DataFrame

Normalize features for machine learning.

Methods:
- "standardize": (x - mean) / std (default, zero mean unit variance)
- "minmax": (x - min) / (max - min) (range 0-1)
- "robust": (x - median) / IQR (robust to outliers)

# Arguments
- `features::DataFrame`: Features to normalize
- `method::String`: Normalization method

# Returns
- `DataFrame`: Normalized features
- `Dict`: Normalization parameters (for inverse transform)
"""
function normalize_features(features::DataFrame; method::String="standardize")::Tuple{DataFrame, Dict}
    @info "Normalizing features using: $method"

    result_df = copy(features)
    norm_params = Dict{String, Dict}()

    numeric_cols = [col for col in names(result_df)
                   if eltype(result_df[!, col]) <: Number]

    for col in numeric_cols
        values = result_df[!, col]
        valid_values = collect(skipmissing(values))

        if isempty(valid_values)
            continue
        end

        if method == "standardize"
            mean_val = mean(valid_values)
            std_val = std(valid_values)
            if std_val > 0
                result_df[!, col] = (values .- mean_val) ./ std_val
                norm_params[col] = Dict("mean" => mean_val, "std" => std_val)
            end

        elseif method == "minmax"
            min_val = minimum(valid_values)
            max_val = maximum(valid_values)
            if max_val > min_val
                result_df[!, col] = (values .- min_val) ./ (max_val - min_val)
                norm_params[col] = Dict("min" => min_val, "max" => max_val)
            end

        elseif method == "robust"
            median_val = median(valid_values)
            q1 = quantile(valid_values, 0.25)
            q3 = quantile(valid_values, 0.75)
            iqr = q3 - q1
            if iqr > 0
                result_df[!, col] = (values .- median_val) ./ iqr
                norm_params[col] = Dict("median" => median_val, "iqr" => iqr)
            end
        end
    end

    return result_df, norm_params
end

"""
    haversine_distance(lat1::Float64, lon1::Float64, lat2::Float64, lon2::Float64)::Float64

Calculate great-circle distance between two points in meters.
"""
function haversine_distance(lat1::Float64, lon1::Float64, lat2::Float64, lon2::Float64)::Float64
    R = 6371000.0  # Earth radius in meters
    lat1_rad = deg2rad(lat1)
    lat2_rad = deg2rad(lat2)
    dlat = deg2rad(lat2 - lat1)
    dlon = deg2rad(lon2 - lon1)
    a = sin(dlat / 2)^2 + cos(lat1_rad) * cos(lat2_rad) * sin(dlon / 2)^2
    c = 2 * asin(sqrt(a))
    return R * c
end
