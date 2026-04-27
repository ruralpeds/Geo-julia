"""
    classify_percentiles(data::Vector, percentiles::Vector{Float64}) -> Vector{Float64}

Create classification boundaries at user-defined percentiles.

# Arguments
- `data::Vector`: Data to classify
- `percentiles::Vector{Float64}`: Percentiles in [0, 1] (e.g., [0.1, 0.5, 0.9])

# Returns
- `Vector{Float64}`: Boundaries at specified percentiles
"""
function classify_percentiles(data::Vector, percentiles::Vector)
    data_clean = float.(filter(x -> !ismissing(x) && !isnan(x) && !isinf(x), data))
    
    if length(data_clean) == 0
        error("No valid data to classify")
    end
    
    if any(p < 0 || p > 1 for p in percentiles)
        error("Percentiles must be in [0, 1]")
    end
    
    # Always include 0 and 1 for min and max
    p_set = sort(unique([0.0; percentiles; 1.0]))
    
    boundaries = quantile(data_clean, p_set)
    unique(boundaries)
end

"""
    classify_deciles(data::Vector) -> Vector{Float64}

Classify by deciles (10th, 20th, ..., 90th percentiles).
"""
function classify_deciles(data::Vector)
    percentiles = [i/10 for i in 1:9]
    classify_percentiles(data, percentiles)
end

"""
    classify_quintiles(data::Vector) -> Vector{Float64}

Classify by quintiles (20th, 40th, 60th, 80th percentiles).
"""
function classify_quintiles(data::Vector)
    percentiles = [i/5 for i in 1:4]
    classify_percentiles(data, percentiles)
end
