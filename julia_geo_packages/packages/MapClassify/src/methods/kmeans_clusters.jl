"""
    classify_kmeans(data::Vector, n_classes::Int=5) -> Vector{Float64}

K-means clustering classification.
Uses k-means to find cluster centers, then creates boundaries at midpoints.

# Arguments
- `data::Vector`: Data to classify
- `n_classes::Int`: Number of clusters/classes (default: 5)

# Returns
- `Vector{Float64}`: Cluster boundaries
"""
function classify_kmeans(data::Vector, n_classes::Int=5)
    data_clean = filter(x -> !ismissing(x) && !isnan(x) && !isinf(x), data)
    
    if length(data_clean) == 0
        error("No valid data to classify")
    end
    
    if length(data_clean) < n_classes
        @warn "Fewer observations than classes"
        return unique(sort(data_clean))
    end
    
    # Reshape data for Clustering.jl (requires matrix)
    X = reshape(data_clean, :, 1)
    
    # Perform k-means clustering
    result = kmeans(X', n_classes; maxiter=100)
    centers = sort(vec(result.centers))
    
    # Create boundaries at midpoints between centers
    boundaries = [minimum(data_clean)]
    
    for i in 1:length(centers)-1
        midpoint = (centers[i] + centers[i+1]) / 2
        push!(boundaries, midpoint)
    end
    
    push!(boundaries, maximum(data_clean))
    
    unique(boundaries)
end
