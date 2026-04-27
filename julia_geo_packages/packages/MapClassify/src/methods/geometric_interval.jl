"""
    classify_geometric_interval(data::Vector, n_classes::Int=5) -> Vector{Float64}

Geometric interval classification (exponential/logarithmic progression).
Each class width increases geometrically rather than linearly.
Useful for data with exponential patterns.

# Arguments
- `data::Vector`: Data to classify
- `n_classes::Int`: Number of classes (default: 5)

# Returns
- `Vector{Float64}`: Geometrically-spaced boundaries
"""
function classify_geometric_interval(data::Vector, n_classes::Int=5)
    data_clean = filter(x -> !ismissing(x) && !isnan(x) && !isinf(x), data)
    
    if length(data_clean) == 0
        error("No valid data to classify")
    end
    
    min_val = minimum(data_clean)
    max_val = maximum(data_clean)
    
    if min_val == max_val
        @warn "Data is constant"
        return [min_val, max_val]
    end
    
    if min_val <= 0
        # Shift data to be positive
        shift = abs(min_val) + 1
        min_shifted = min_val + shift
        max_shifted = max_val + shift
    else
        shift = 0
        min_shifted = min_val
        max_shifted = max_val
    end
    
    # Use log scale for geometric progression
    log_min = log(min_shifted)
    log_max = log(max_shifted)
    
    log_breaks = range(log_min, log_max, length=n_classes+1) |> collect
    breaks = exp.(log_breaks)
    
    if shift > 0
        breaks = breaks .- shift
    end
    
    breaks
end
