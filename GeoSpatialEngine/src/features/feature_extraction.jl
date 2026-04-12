"""
Feature extraction from geospatial data.
"""

function extract_spatial_features(data::GeoSpatialData)
    @info "Extracting spatial features"
    return DataFrame()
end

function compute_neighborhood_statistics(data::GeoSpatialData, radius::Float64)
    @info "Computing neighborhood statistics with radius: $(radius)m"
    return DataFrame()
end

function extract_temporal_features(data::GeoSpatialData, timestamp_col::String)
    @info "Extracting temporal features"
    return DataFrame()
end

function normalize_features(features::DataFrame)
    @info "Normalizing features"
    return features
end
