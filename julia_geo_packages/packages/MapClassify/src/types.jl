"""
    ClassificationResult

Stores the results of a classification operation, including boundaries, labels,
colors, and quality metrics.

# Fields
- `boundaries::Vector{Float64}`: Classification boundaries (min, cutpoints..., max)
- `labels::Vector{String}`: Labels for each class
- `class_counts::Vector{Int}`: Number of observations in each class
- `colors::Vector`: RGB colors for each class
- `method::Symbol`: Classification method used
- `n_classes::Int`: Number of classes
- `gini_index::Float64`: Gini coefficient (0=perfect inequality, 1=perfect equality)
- `entropy::Float64`: Shannon entropy of classifications
- `goodness_of_variance_fit::Float64`: GVF metric (0-1, higher is better)
"""
struct ClassificationResult
    boundaries::Vector{Float64}
    labels::Vector{String}
    class_counts::Vector{Int}
    colors::Vector
    method::Symbol
    n_classes::Int
    gini_index::Float64
    entropy::Float64
    goodness_of_variance_fit::Float64
end

function ClassificationResult(
    boundaries::Vector{Float64},
    labels::Vector{String},
    class_counts::Vector{Int},
    colors::Vector,
    method::Symbol,
    gini::Float64,
    entropy::Float64,
    gvf::Float64
)
    n_classes = length(labels)
    ClassificationResult(boundaries, labels, class_counts, colors, method, n_classes, gini, entropy, gvf)
end

function Base.show(io::IO, result::ClassificationResult)
    println(io, "ClassificationResult")
    println(io, "  Method: $(result.method)")
    println(io, "  Classes: $(result.n_classes)")
    println(io, "  Boundaries: [$(join(round.(result.boundaries, digits=4), ", "))]")
    println(io, "  Gini Index: $(round(result.gini_index, digits=4))")
    println(io, "  Entropy: $(round(result.entropy, digits=4))")
    println(io, "  GVF: $(round(result.goodness_of_variance_fit, digits=4))")
    println(io, "  Class Counts: $(result.class_counts)")
    println(io, "  Labels: $(result.labels)")
end
