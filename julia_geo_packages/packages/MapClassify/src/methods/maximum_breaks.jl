"""
    classify_maximum_breaks(data::Vector) -> Vector{Float64}

Maximum breaks algorithm based on gap analysis.
Identifies natural clusters by finding the largest gaps in the sorted data.
Useful for separating high-value observations from the rest.

# Arguments
- `data::Vector`: Data to classify

# Returns
- `Vector{Float64}`: Break boundaries at largest gaps
"""
function classify_maximum_breaks(data::Vector)
    data_clean = sort(filter(x -> !ismissing(x) && !isnan(x) && !isinf(x), data))
    
    if length(data_clean) == 0
        error("No valid data to classify")
    end
    
    if length(data_clean) < 2
        return data_clean
    end
    
    # Compute gaps between consecutive values
    gaps = diff(data_clean)
    
    if length(gaps) == 0 || all(gap == 0 for gap in gaps)
        @warn "No variation in data"
        return [data_clean[1], data_clean[end]]
    end
    
    # Find indices of largest gaps
    sorted_gaps = sort(collect(enumerate(gaps)), by=x -> -x[2])
    
    # Take the largest gap
    gap_indices = [sorted_gaps[1][1]]
    
    # Sort gap indices to maintain order
    gap_indices = sort(gap_indices)
    
    # Create boundaries
    boundaries = [data_clean[1]]
    for idx in gap_indices
        push!(boundaries, data_clean[idx+1])
    end
    push!(boundaries, data_clean[end])
    
    unique(boundaries)
end
