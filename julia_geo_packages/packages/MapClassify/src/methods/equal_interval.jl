"""
    classify_equal_interval(data::Vector, n_classes::Int=5) -> Vector{Float64}

Create equal-width (equal-interval) classification boundaries.
Each class has the same width: (max - min) / n_classes.

# Arguments
- `data::Vector`: Data to classify
- `n_classes::Int`: Number of classes (default: 5)

# Returns
- `Vector{Float64}`: Classification boundaries
"""
function classify_equal_interval(data::Vector, n_classes::Int=5)
    data_clean = filter(x -> !ismissing(x) && !isnan(x) && !isinf(x), data)
    
    if length(data_clean) == 0
        error("No valid data to classify")
    end
    
    if n_classes < 1
        error("n_classes must be >= 1")
    end
    
    min_val = minimum(data_clean)
    max_val = maximum(data_clean)
    
    if min_val == max_val
        @warn "Data is constant; returning single boundary"
        return [min_val, max_val]
    end
    
    # Create equal-width boundaries
    boundaries = range(min_val, max_val, length=n_classes+1) |> collect
    
    boundaries
end
