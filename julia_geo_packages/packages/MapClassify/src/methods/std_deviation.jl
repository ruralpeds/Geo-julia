"""
    classify_std_deviation(data::Vector, n_std::Int=1) -> Vector{Float64}

Create boundaries based on standard deviations from the mean.
Useful for identifying outliers and symmetric classifications.

# Arguments
- `data::Vector`: Data to classify
- `n_std::Int`: Number of standard deviations (1, 2, or 3)

# Returns
- `Vector{Float64}`: Boundaries at ±n_std intervals
"""
function classify_std_deviation(data::Vector, n_std::Int=1)
    data_clean = filter(x -> !ismissing(x) && !isnan(x) && !isinf(x), data)
    
    if length(data_clean) == 0
        error("No valid data to classify")
    end
    
    if n_std < 1 || n_std > 3
        error("n_std must be 1, 2, or 3")
    end
    
    mean_val = mean(data_clean)
    std_val = std(data_clean)
    
    if std_val == 0
        @warn "Zero standard deviation; returning single boundary"
        return [minimum(data_clean), maximum(data_clean)]
    end
    
    # Create boundaries at ±std intervals
    boundaries = Float64[]
    push!(boundaries, minimum(data_clean))
    
    for i in 1:n_std
        lower = mean_val - i * std_val
        upper = mean_val + i * std_val
        if lower > minimum(data_clean) && lower < maximum(data_clean)
            push!(boundaries, lower)
        end
        if upper > minimum(data_clean) && upper < maximum(data_clean)
            push!(boundaries, upper)
        end
    end
    
    push!(boundaries, maximum(data_clean))
    
    sort!(unique(boundaries))
    boundaries
end

"""
    classify_1std(data::Vector) -> Vector{Float64}

Create boundaries at mean ± 1 standard deviation.
"""
function classify_1std(data::Vector)
    classify_std_deviation(data, 1)
end

"""
    classify_2std(data::Vector) -> Vector{Float64}

Create boundaries at mean ± 2 standard deviations.
"""
function classify_2std(data::Vector)
    classify_std_deviation(data, 2)
end

"""
    classify_3std(data::Vector) -> Vector{Float64}

Create boundaries at mean ± 3 standard deviations.
"""
function classify_3std(data::Vector)
    classify_std_deviation(data, 3)
end
