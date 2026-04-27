"""
    classify_box_breaks(data::Vector) -> Vector{Float64}

Box plot-based classification using quartiles and whiskers.
Creates 6 boundaries: min_whisker, Q1, median, Q3, max_whisker, and outliers.

# Arguments
- `data::Vector`: Data to classify

# Returns
- `Vector{Float64}`: Boundaries at whisker and quartile positions
"""
function classify_box_breaks(data::Vector)
    data_clean = filter(x -> !ismissing(x) && !isnan(x) && !isinf(x), data)
    
    if length(data_clean) == 0
        error("No valid data to classify")
    end
    
    if length(data_clean) < 4
        @warn "Fewer than 4 observations; using min/max only"
        return unique(data_clean)
    end
    
    # Compute quartiles
    q1 = quantile(data_clean, 0.25)
    q2 = quantile(data_clean, 0.50)  # median
    q3 = quantile(data_clean, 0.75)
    
    # Compute IQR and whiskers
    iqr = q3 - q1
    whisker_lower = q1 - 1.5 * iqr
    whisker_upper = q3 + 1.5 * iqr
    
    # Clamp whiskers to data range
    min_val = minimum(data_clean)
    max_val = maximum(data_clean)
    
    whisker_lower = max(whisker_lower, min_val)
    whisker_upper = min(whisker_upper, max_val)
    
    # Combine boundaries
    boundaries = [min_val, whisker_lower, q1, q2, q3, whisker_upper, max_val]
    sort!(unique(boundaries))
    
    boundaries
end
