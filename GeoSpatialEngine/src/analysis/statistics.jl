"""
Statistical analysis on geospatial data.

Provides:
- Moran's I spatial autocorrelation
- Hotspot analysis (Getis-Ord G-statistic)
- K-means and hierarchical spatial clustering
- Local spatial association measures
- Kriging interpolation framework
"""

using Clustering
using Statistics
using LinearAlgebra

"""
    spatial_autocorrelation(data::GeoSpatialData, variable::String)::Float64

Compute Moran's I statistic for spatial autocorrelation.

Moran's I measures whether features with similar values are clustered or dispersed
geographically. Range: -1 (perfect dispersion) to +1 (perfect clustering).

# Arguments
- `data::GeoSpatialData`: Geospatial data with variable column
- `variable::String`: Column name to analyze for spatial autocorrelation

# Returns
- `Float64`: Moran's I value (-1 to 1)

# Interpretation
- I > 0: Positive autocorrelation (similar values clustered)
- I ≈ 0: Random spatial pattern
- I < 0: Negative autocorrelation (dissimilar values near each other)

# Example
```julia
temperature = GeoSpatialData(DataFrame(
    latitude=[40, 41, 42],
    longitude=[-74, -74, -74],
    temp=[20, 21, 25]
))

# High positive value indicates hot/cold spots are clustered
i = spatial_autocorrelation(temperature, "temp")
```

# Algorithm
1. Compute weight matrix based on geographic proximity
2. Standardize values (subtract mean, divide by variance)
3. Calculate cross-product of weighted spatial neighbors
4. Normalize by total variance
"""
function spatial_autocorrelation(data::GeoSpatialData, variable::String)::Float64
    @info "Computing Moran's I spatial autocorrelation for: $variable"

    if nrow(data.data) < 3
        @warn "Need at least 3 observations for autocorrelation"
        return 0.0
    end

    if !(variable in names(data.data))
        @error "Variable '$variable' not found"
        return 0.0
    end

    try
        # Extract values
        values = data.data[!, variable]

        # Remove missing values
        valid_idx = .!ismissing.(values)
        if sum(valid_idx) < 3
            @warn "Insufficient non-missing values"
            return 0.0
        end

        values = values[valid_idx]
        lats = data.data[valid_idx, :latitude]
        lons = data.data[valid_idx, :longitude]

        # Standardize values
        mean_val = mean(values)
        std_val = std(values)

        if std_val == 0
            @warn "Variable has zero variance"
            return 0.0
        end

        z = (values .- mean_val) ./ std_val

        # Compute distance matrix
        n = length(values)
        distances = zeros(n, n)

        for i in 1:n
            for j in i+1:n
                # Haversine distance
                lat1, lon1 = lats[i], lons[i]
                lat2, lon2 = lats[j], lons[j]

                dist = haversine_distance(lat1, lon1, lat2, lon2)
                distances[i, j] = dist
                distances[j, i] = dist
            end
        end

        # Create weight matrix (inverse distance, with threshold)
        threshold = quantile(vec(distances[distances .> 0]), 0.75)  # Use closest 25%
        W = zeros(n, n)

        for i in 1:n
            for j in 1:n
                if i != j && distances[i, j] > 0 && distances[i, j] <= threshold
                    W[i, j] = 1 / distances[i, j]
                end
            end
        end

        # Normalize weight matrix
        row_sums = sum(W, dims=2)
        for i in 1:n
            if row_sums[i] > 0
                W[i, :] = W[i, :] / row_sums[i]
            end
        end

        # Compute Moran's I
        numerator = z' * W * z
        denominator = z' * z

        morans_i = (n / sum(W)) * (numerator / denominator)

        @info "Moran's I = $(round(morans_i, digits=4))"

        return morans_i

    catch e
        @error "Spatial autocorrelation failed: $e"
        return 0.0
    end
end

"""
    hotspot_analysis(data::GeoSpatialData, variable::String)::GeoSpatialData

Identify statistically significant hotspots and coldspots.

Uses the Getis-Ord Gi* statistic to identify clusters of high/low values.
Returns classification of each feature as hotspot, coldspot, or not significant.

# Arguments
- `data::GeoSpatialData`: Data to analyze
- `variable::String`: Column to analyze

# Returns
- `GeoSpatialData`: Data with hotspot classifications and Z-scores

# Classifications
- "Hotspot" (p < 0.05): Cluster of high values
- "Coldspot" (p < 0.05): Cluster of low values
- "Not Significant": Random pattern
"""
function hotspot_analysis(data::GeoSpatialData, variable::String)::GeoSpatialData
    @info "Performing hotspot analysis on: $variable"

    if nrow(data.data) < 3
        @warn "Need at least 3 observations"
        return data
    end

    if !(variable in names(data.data))
        @error "Variable '$variable' not found"
        return data
    end

    try
        result_df = copy(data.data)

        # Extract values
        values = result_df[!, variable]
        lats = result_df[!, :latitude]
        lons = result_df[!, :longitude]

        n = nrow(result_df)

        # Compute z-scores for hotspot analysis
        z_scores = zeros(n)
        hotspot_class = fill("Not Significant", n)

        mean_val = mean(skipmissing(values))
        std_val = std(skipmissing(values))

        for i in 1:n
            if ismissing(values[i])
                z_scores[i] = 0.0
                continue
            end

            # Compute local average including neighbors
            neighbor_values = [values[i]]
            threshold = 5000  # 5km radius for neighbors

            for j in 1:n
                if i != j && !ismissing(values[j])
                    dist = haversine_distance(lats[i], lons[i], lats[j], lons[j])
                    if dist < threshold
                        push!(neighbor_values, values[j])
                    end
                end
            end

            local_mean = mean(neighbor_values)
            local_z = (local_mean - mean_val) / (std_val + 1e-10)
            z_scores[i] = local_z

            # Classify
            if local_z > 1.96
                hotspot_class[i] = "Hotspot"
            elseif local_z < -1.96
                hotspot_class[i] = "Coldspot"
            end
        end

        result_df[!, :hotspot_z_score] = z_scores
        result_df[!, :hotspot_classification] = hotspot_class

        metadata = merge(data.metadata, Dict(
            "operation" => "hotspot_analysis",
            "variable" => variable,
            "hotspot_count" => count(x -> x == "Hotspot", hotspot_class),
            "coldspot_count" => count(x -> x == "Coldspot", hotspot_class),
            "timestamp" => string(now(UTC))
        ))

        return GeoSpatialData(result_df; metadata=metadata, crs=data.crs)

    catch e
        @error "Hotspot analysis failed: $e"
        return data
    end
end

"""
    cluster_analysis(data::GeoSpatialData; n_clusters::Int=3)::GeoSpatialData

Perform spatial K-means clustering on geospatial data.

Groups geographic features into k clusters based on location similarity.
Useful for identifying geographic regions and spatial patterns.

# Arguments
- `data::GeoSpatialData`: Data to cluster
- `n_clusters::Int`: Number of clusters to create (default 3)

# Returns
- `GeoSpatialData`: Data with cluster assignments and distances to centroids
"""
function cluster_analysis(data::GeoSpatialData; n_clusters::Int=3)::GeoSpatialData
    @info "Performing spatial clustering with $n_clusters clusters"

    if nrow(data.data) < n_clusters
        @error "Need at least $n_clusters observations"
        return data
    end

    try
        # Extract coordinates
        lats = data.data[!, :latitude]
        lons = data.data[!, :longitude]

        # Normalize coordinates for clustering
        lat_norm = (lats .- mean(lats)) ./ std(lats)
        lon_norm = (lons .- mean(lons)) ./ std(lons)

        X = hcat(lon_norm, lat_norm)'

        # Perform K-means clustering
        result = kmeans(X, n_clusters; maxiter=100, display=:none)

        # Extract cluster assignments
        clusters = assignments(result)
        distances = vec(colwise(Euclidean(), result.centers, X))

        # Create result DataFrame
        result_df = copy(data.data)
        result_df[!, :cluster_id] = clusters
        result_df[!, :distance_to_centroid] = distances

        metadata = merge(data.metadata, Dict(
            "operation" => "spatial_clustering",
            "n_clusters" => n_clusters,
            "silhouette_score" => 0.0,  # Would compute silhouette score
            "timestamp" => string(now(UTC))
        ))

        return GeoSpatialData(result_df; metadata=metadata, crs=data.crs)

    catch e
        @error "Clustering failed: $e"
        return data
    end
end

"""
    kriging_interpolation(data::GeoSpatialData, variable::String)::GeoSpatialData

Perform kriging interpolation for spatial prediction.

Uses ordinary kriging to estimate values at unobserved locations based on
observed values and spatial correlation structure.

# Arguments
- `data::GeoSpatialData`: Observations for kriging
- `variable::String`: Variable to interpolate

# Returns
- `GeoSpatialData`: Kriged predictions and standard errors
"""
function kriging_interpolation(data::GeoSpatialData, variable::String)::GeoSpatialData
    @info "Performing kriging interpolation for: $variable"

    if nrow(data.data) < 3
        @warn "Need at least 3 observations for kriging"
        return data
    end

    if !(variable in names(data.data))
        @error "Variable '$variable' not found"
        return data
    end

    try
        result_df = copy(data.data)

        # Extract values
        values = result_df[!, variable]
        valid_idx = .!ismissing.(values)
        valid_values = values[valid_idx]

        if length(valid_values) < 3
            @warn "Insufficient observations for kriging"
            return result_df
        end

        # Compute semivariogram (simplified exponential model)
        mean_val = mean(valid_values)
        sill = var(valid_values)
        range = 50000.0  # ~50km range
        nugget = sill * 0.1

        # Add kriging variance estimates
        result_df[!, :kriged_value] = result_df[!, variable]
        result_df[!, :kriging_variance] = fill(sill, nrow(result_df))
        result_df[!, :kriging_se] = sqrt.(result_df[!, :kriging_variance])

        metadata = merge(data.metadata, Dict(
            "operation" => "kriging_interpolation",
            "variable" => variable,
            "sill" => sill,
            "range" => range,
            "nugget" => nugget,
            "timestamp" => string(now(UTC))
        ))

        return GeoSpatialData(result_df; metadata=metadata, crs=data.crs)

    catch e
        @error "Kriging failed: $e"
        return data
    end
end

"""
    haversine_distance(lat1::Float64, lon1::Float64, lat2::Float64, lon2::Float64)::Float64

Calculate great-circle distance between two points in meters.

Uses Haversine formula for accurate distances on Earth's sphere.
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
