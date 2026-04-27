"""
    classify_pretty_breaks(data::Vector, n_classes::Int=5) -> Vector{Float64}

R-style "pretty" breaks algorithm for aesthetically pleasing classification.
Generates round boundaries that are easy to interpret.

# Arguments
- `data::Vector`: Data to classify
- `n_classes::Int`: Approximate number of classes (default: 5)

# Returns
- `Vector{Float64}`: Pretty break boundaries
"""
function classify_pretty_breaks(data::Vector, n_classes::Int=5)
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
    
    # Find a nice unit for breaking
    range_val = max_val - min_val
    unit = _pretty_unit(range_val / n_classes)
    
    # Generate pretty breaks
    breaks = Float64[]
    
    # Start from a multiple of unit below min
    start = floor(min_val / unit) * unit
    current = start
    
    while current <= max_val + unit
        if current >= min_val - unit * 0.1
            push!(breaks, current)
        end
        current += unit
    end
    
    # Ensure we have min and max
    if breaks[1] > min_val
        pushfirst!(breaks, min_val)
    end
    if breaks[end] < max_val
        push!(breaks, max_val)
    end
    
    unique(breaks)
end

"""
    _pretty_unit(interval::Float64) -> Float64

Find a pretty unit for the given interval.
"""
function _pretty_unit(interval::Float64)
    if interval <= 0
        return 1.0
    end
    
    z = 10 ^ floor(log10(interval))
    
    # Choose unit based on interval relative to z
    if interval / z < 1.5
        unit = z
    elseif interval / z < 3
        unit = 2 * z
    elseif interval / z < 7
        unit = 5 * z
    else
        unit = 10 * z
    end
    
    unit
end
