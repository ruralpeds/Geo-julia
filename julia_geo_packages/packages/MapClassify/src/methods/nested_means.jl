"""
    classify_nested_means(data::Vector) -> Vector{Float64}

Nested means classification.
Recursively divides data by computing mean and splitting above/below.
Creates a tree-like hierarchy of class boundaries.

# Arguments
- `data::Vector`: Data to classify

# Returns
- `Vector{Float64}`: Recursively-computed mean boundaries
"""
function classify_nested_means(data::Vector)
    data_clean = sort(filter(x -> !ismissing(x) && !isnan(x) && !isinf(x), data))
    
    if length(data_clean) == 0
        error("No valid data to classify")
    end
    
    if length(data_clean) < 2
        return data_clean
    end
    
    boundaries = Float64[minimum(data_clean), maximum(data_clean)]
    
    # Recursively add mean boundaries
    _add_nested_mean(data_clean, boundaries, minimum(data_clean), maximum(data_clean))
    
    sort!(unique(boundaries))
    boundaries
end

"""
    _add_nested_mean(data::Vector, boundaries::Vector, lower::Float64, upper::Float64)

Internal recursive function for nested means.
"""
function _add_nested_mean(data::Vector, boundaries::Vector, lower::Float64, upper::Float64; depth::Int=0)
    if depth > 5  # Limit recursion depth
        return
    end
    
    # Filter data in current range
    subset = filter(x -> x >= lower && x <= upper, data)
    
    if length(subset) <= 2
        return
    end
    
    mean_val = mean(subset)
    
    # If mean is at boundary, stop
    if abs(mean_val - lower) < 1e-10 || abs(mean_val - upper) < 1e-10
        return
    end
    
    # Add mean as boundary
    if mean_val > lower && mean_val < upper
        push!(boundaries, mean_val)
        
        # Recursively split
        _add_nested_mean(data, boundaries, lower, mean_val, depth=depth+1)
        _add_nested_mean(data, boundaries, mean_val, upper, depth=depth+1)
    end
end
