"""
    classify_headtail_breaks(data::Vector) -> Vector{Float64}

Head-Tail breaks algorithm for bimodal and skewed distributions.
Recursively splits data at the mean, separating "head" (above mean) from "tail" (below mean).

# Arguments
- `data::Vector`: Data to classify

# Returns
- `Vector{Float64}`: Head-tail break boundaries
"""
function classify_headtail_breaks(data::Vector)
    data_clean = filter(x -> !ismissing(x) && !isnan(x) && !isinf(x), data)
    
    if length(data_clean) == 0
        error("No valid data to classify")
    end
    
    boundaries = Float64[minimum(data_clean), maximum(data_clean)]
    
    # Recursively apply head-tail breaks
    _add_headtail_break(data_clean, boundaries, minimum(data_clean), maximum(data_clean))
    
    sort!(unique(boundaries))
    boundaries
end

"""
    _add_headtail_break(data::Vector, boundaries::Vector, lower::Float64, upper::Float64)

Internal recursive function for head-tail breaks.
"""
function _add_headtail_break(data::Vector, boundaries::Vector, lower::Float64, upper::Float64)
    # Filter data in current range
    subset = filter(x -> x >= lower && x <= upper, data)
    
    if length(subset) <= 1
        return
    end
    
    mean_val = mean(subset)
    
    # If mean is at boundary or data is constant, stop
    if abs(mean_val - lower) < 1e-10 || abs(mean_val - upper) < 1e-10
        return
    end
    
    # Add mean as boundary if not already present
    if mean_val > lower && mean_val < upper
        push!(boundaries, mean_val)
        
        # Recursively split head
        head = filter(x -> x > mean_val, subset)
        if length(head) > 1
            _add_headtail_break(data, boundaries, mean_val, upper)
        end
    end
end
