"""
    classify_quantile(data::Vector, n_classes::Int=5) -> Vector{Float64}

Create equal-frequency (quantile) classification boundaries.
Each class contains approximately the same number of observations.

# Arguments
- `data::Vector`: Data to classify
- `n_classes::Int`: Number of classes (default: 5 for quintile)

# Returns
- `Vector{Float64}`: Classification boundaries
"""
function classify_quantile(data::Vector, n_classes::Int=5)
    data_clean = float.(filter(x -> !ismissing(x) && !isnan(x) && !isinf(x), data))
    
    if length(data_clean) == 0
        error("No valid data to classify")
    end
    
    if length(data_clean) < n_classes
        @warn "Fewer observations ($length(data_clean)) than classes ($n_classes); will create fewer classes"
        n_classes = length(unique(data_clean))
    end
    
    # Compute quantile boundaries
    quantiles = [(i-1)/(n_classes-1) for i in 1:n_classes]
    boundaries = quantile(data_clean, quantiles)

    # Remove duplicates while preserving order
    unique_boundaries = Float64[]
    for b in boundaries
        if isempty(unique_boundaries) || abs(b - unique_boundaries[end]) > 1e-10
            push!(unique_boundaries, b)
        end
    end

    # Ensure at least 2 boundaries
    if length(unique_boundaries) < 2
        unique_boundaries = [minimum(data_clean), maximum(data_clean)]
    end

    unique_boundaries
end

"""
    classify_quartile(data::Vector) -> Vector{Float64}

Create quartile boundaries (4 classes, Q1, Q2, Q3).
"""
function classify_quartile(data::Vector)
    classify_quantile(data, 4)
end

"""
    classify_decile(data::Vector) -> Vector{Float64}

Create decile boundaries (10 classes).
"""
function classify_decile(data::Vector)
    classify_quantile(data, 10)
end
