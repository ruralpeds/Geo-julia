"""
Statistical plots and visualizations.
"""

function plot_distribution(data::GeoSpatialData, variable::String)
    @info "Plotting distribution for: $variable"
    return nothing
end

function plot_time_series(data::GeoSpatialData, variable::String, time_col::String)
    @info "Plotting time series for: $variable"
    return nothing
end

function plot_correlation_matrix(data::GeoSpatialData)
    @info "Plotting correlation matrix"
    return nothing
end

function plot_scatter(data::GeoSpatialData, x::String, y::String)
    @info "Plotting scatter: $x vs $y"
    return nothing
end
