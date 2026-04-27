"""
    classify_arithmetic_progression(data::Vector, n_classes::Int=5) -> Vector{Float64}

Arithmetic progression classification.
Creates classes with width increasing by a constant amount.
Similar to equal interval but with increasing gaps.

# Arguments
- `data::Vector`: Data to classify
- `n_classes::Int`: Number of classes (default: 5)

# Returns
- `Vector{Float64}`: Arithmetically-spaced boundaries
"""
function classify_arithmetic_progression(data::Vector, n_classes::Int=5)
    data_clean = float.(filter(x -> !ismissing(x) && !isnan(x) && !isinf(x), data))
    
    if length(data_clean) == 0
        error("No valid data to classify")
    end
    
    min_val = minimum(data_clean)
    max_val = maximum(data_clean)
    
    if min_val == max_val
        @warn "Data is constant"
        return [min_val, max_val]
    end
    
    range_val = max_val - min_val
    
    # Compute arithmetic progression parameter
    # For n classes, sum of widths = range
    # If widths form arithmetic progression: d, d+Δ, d+2Δ, ...
    # Sum = n*d + Δ*(0+1+2+...+(n-1)) = n*d + Δ*n*(n-1)/2 = range
    
    # Use simple approach: start with equal intervals, increase slightly
    base_width = range_val / n_classes
    
    boundaries = [min_val]
    for i in 1:n_classes-1
        # Incrementally increase width
        width = base_width * (1 + 0.2 * (i / n_classes))
        next_boundary = boundaries[end] + width
        push!(boundaries, next_boundary)
    end
    
    # Ensure last boundary is exactly max
    boundaries[end] = max_val
    
    unique(sort(boundaries))
end
