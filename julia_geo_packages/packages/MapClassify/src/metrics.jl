"""
    gini_index(class_counts::Vector{Int}) -> Float64

Calculate the Gini coefficient for a classification.
Returns 0 for perfect equality (all classes same size) to 1 for perfect inequality.

# Arguments
- `class_counts::Vector{Int}`: Count of observations in each class

# Returns
- `Float64`: Gini coefficient (0-1)
"""
function gini_index(class_counts::Vector{Int})
    n = sum(class_counts)
    if n <= 1
        return 0.0
    end
    
    proportions = class_counts ./ n
    # Gini = 1 - sum(p_i^2) for each class proportion
    1.0 - sum(proportions .^ 2)
end

"""
    shannon_entropy(class_counts::Vector{Int}) -> Float64

Calculate Shannon entropy of a classification.
Higher entropy indicates more uniform distribution of classes.

# Arguments
- `class_counts::Vector{Int}`: Count of observations in each class

# Returns
- `Float64`: Shannon entropy (bits)
"""
function shannon_entropy(class_counts::Vector{Int})
    n = sum(class_counts)
    if n == 0
        return 0.0
    end
    
    proportions = class_counts ./ n
    entropy = 0.0
    for p in proportions
        if p > 0
            entropy -= p * log(2, p)
        end
    end
    entropy
end

"""
    goodness_of_variance_fit(data::Vector{Float64}, boundaries::Vector{Float64}) -> Float64

Calculate the Goodness of Variance Fit (GVF) metric.
Measures how well the classification captures variance in the data.
Range: 0-1, higher is better.

# Arguments
- `data::Vector{Float64}`: Original continuous data
- `boundaries::Vector{Float64}`: Classification boundaries

# Returns
- `Float64`: GVF metric (0-1)
"""
function goodness_of_variance_fit(data::Vector{Float64}, boundaries::Vector{Float64})
    data_clean = filter(x -> !isnan(x) && !isinf(x), data)
    
    if length(data_clean) == 0
        return 0.0
    end
    
    # Total sum of squared deviations from overall mean
    mean_data = mean(data_clean)
    sdam = sum((data_clean .- mean_data) .^ 2)
    
    if sdam == 0
        return 0.0  # Constant data
    end
    
    # Within-class sum of squared deviations
    sdcm = 0.0
    for i in 1:length(boundaries)-1
        mask = (data_clean .>= boundaries[i]) .& (data_clean .< boundaries[i+1])
        if any(mask)
            class_data = data_clean[mask]
            class_mean = mean(class_data)
            sdcm += sum((class_data .- class_mean) .^ 2)
        end
    end
    
    # Handle last boundary (inclusive)
    mask = (data_clean .>= boundaries[end-1]) .& (data_clean .<= boundaries[end])
    if any(mask)
        class_data = data_clean[mask]
        class_mean = mean(class_data)
        sdcm += sum((class_data .- class_mean) .^ 2)
    end
    
    1.0 - (sdcm / sdam)
end

"""
    compute_class_counts(data::Vector, boundaries::Vector) -> Vector{Int}

Count observations in each class defined by boundaries.

# Arguments
- `data::Vector`: Data to classify
- `boundaries::Vector`: Classification boundaries

# Returns
- `Vector{Int}`: Count in each class
"""
function compute_class_counts(data::Vector, boundaries::Vector)
    counts = zeros(Int, length(boundaries) - 1)
    
    data_clean = filter(x -> !ismissing(x) && !isnan(x) && !isinf(x), data)
    
    for i in 1:length(boundaries)-1
        if i < length(boundaries) - 1
            counts[i] = sum((data_clean .>= boundaries[i]) .& (data_clean .< boundaries[i+1]))
        else
            # Last class is inclusive on both ends
            counts[i] = sum((data_clean .>= boundaries[i]) .& (data_clean .<= boundaries[i+1]))
        end
    end
    
    counts
end
