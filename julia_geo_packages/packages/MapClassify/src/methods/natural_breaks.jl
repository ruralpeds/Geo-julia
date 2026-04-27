"""
    classify_natural_breaks(data::Vector, n_classes::Int=5) -> Vector{Float64}

Jenks/Fisher-Jenks natural breaks optimization algorithm.
Minimizes within-class variance to find optimal class boundaries.

This is an important method for healthcare metrics as it identifies
natural clusters in the data.

# Arguments
- `data::Vector`: Data to classify
- `n_classes::Int`: Number of classes (default: 5)

# Returns
- `Vector{Float64}`: Optimal classification boundaries
"""
function classify_natural_breaks(data::Vector, n_classes::Int=5)
    data_clean = sort(float.(filter(x -> !ismissing(x) && !isnan(x) && !isinf(x), data)))

    if length(data_clean) == 0
        error("No valid data to classify")
    end

    n = length(data_clean)

    if n < n_classes
        @warn "Fewer observations than classes; will create fewer classes"
        return unique(data_clean)
    end

    if n_classes == 1
        return [data_clean[1], data_clean[end]]
    end

    # Use dynamic programming to find optimal breaks
    # Based on Jenks natural breaks algorithm

    # Initialize matrices for the DP algorithm
    matrices = _jenks_matrices(data_clean, n_classes)
    
    # Extract class boundaries
    boundaries = _get_boundaries(data_clean, matrices, n_classes)
    
    boundaries
end

"""
    _jenks_matrices(data::Vector{Float64}, n_classes::Int) -> Tuple{Matrix, Matrix}

Internal function: Create matrices for Jenks algorithm.
Returns (SSM, ClassBreaks) matrices.
"""
function _jenks_matrices(data::Vector{Float64}, n_classes::Int)
    n = length(data)
    
    # Matrices: SSM = sum of squared deviations, ClassBreaks = class break indices
    SSM = fill(Inf, (n, n_classes))
    ClassBreaks = fill(0, (n, n_classes))
    
    # Precompute cumulative sums for efficiency
    cumsum_val = cumsum(data)
    cumsum_sq = cumsum(data .^ 2)
    
    # Fill the matrices
    for i in 1:n
        for j in 1:n_classes
            if j == 1
                # First class: from start to i
                SSM[i, j] = _gvf_variant(cumsum_val, cumsum_sq, 1, i)
                ClassBreaks[i, j] = 1
            else
                min_ssm = Inf
                min_k = 1
                
                for k in j-1:i-1
                    # Cost of assigning k:i to class j
                    new_ssm = SSM[k, j-1] + _gvf_variant(cumsum_val, cumsum_sq, k+1, i)
                    
                    if new_ssm < min_ssm
                        min_ssm = new_ssm
                        min_k = k
                    end
                end
                
                SSM[i, j] = min_ssm
                ClassBreaks[i, j] = min_k
            end
        end
    end
    
    (SSM, ClassBreaks)
end

"""
    _gvf_variant(cumsum_val::Vector, cumsum_sq::Vector, i::Int, j::Int) -> Float64

Compute sum of squared deviations for a range [i, j].
"""
function _gvf_variant(cumsum_val::Vector, cumsum_sq::Vector, i::Int, j::Int)
    if i > j
        return 0.0
    end
    
    n = j - i + 1
    sum_val = cumsum_val[j] - (i > 1 ? cumsum_val[i-1] : 0.0)
    sum_sq = cumsum_sq[j] - (i > 1 ? cumsum_sq[i-1] : 0.0)
    
    # Variance formula: sum((x - mean)^2) = sum(x^2) - (sum(x))^2/n
    sum_sq - (sum_val ^ 2) / n
end

"""
    _get_boundaries(data::Vector{Float64}, matrices::Tuple, n_classes::Int) -> Vector{Float64}

Extract boundaries from DP matrices.
"""
function _get_boundaries(data::Vector{Float64}, matrices::Tuple, n_classes::Int)
    SSM, ClassBreaks = matrices
    n = length(data)
    
    # Backtrack to find optimal breaks
    breaks = [n]  # Last index is always included
    k = n
    
    for j in n_classes:-1:2
        k = ClassBreaks[k, j]
        push!(breaks, k)
    end
    
    reverse!(breaks)
    push!(breaks, n)  # Ensure end index
    
    # Convert indices to data values
    boundaries = data[breaks]
    boundaries = unique(boundaries)
    
    # Ensure we have minimum and maximum
    if boundaries[1] != data[1]
        boundaries = [data[1]; boundaries]
    end
    if boundaries[end] != data[end]
        boundaries = [boundaries; data[end]]
    end
    
    boundaries
end
