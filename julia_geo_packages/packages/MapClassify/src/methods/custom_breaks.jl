"""
    classify_custom_breaks(data::Vector, breaks::Vector) -> Vector{Float64}

User-defined custom classification boundaries.

# Arguments
- `data::Vector`: Data to classify
- `breaks::Vector`: Custom break boundaries (will be sorted and deduplicated)

# Returns
- `Vector{Float64}`: Sorted custom boundaries
"""
function classify_custom_breaks(data::Vector, breaks::Vector)
    if isempty(breaks)
        error("breaks cannot be empty")
    end
    
    # Convert to Float64 and sort
    breaks_float = Float64.(breaks)
    sort!(unique(breaks_float))
    
    breaks_float
end
