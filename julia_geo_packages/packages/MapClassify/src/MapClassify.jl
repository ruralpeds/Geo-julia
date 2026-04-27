module MapClassify

using Colors
using Clustering
using StatsBase
using Statistics

# Type definitions
include("types.jl")

# Metrics and utilities
include("metrics.jl")

# Classification methods
include("methods/quantile.jl")
include("methods/equal_interval.jl")
include("methods/natural_breaks.jl")
include("methods/std_deviation.jl")
include("methods/pretty_breaks.jl")
include("methods/headtail_breaks.jl")
include("methods/maximum_breaks.jl")
include("methods/box_breaks.jl")
include("methods/percentiles.jl")
include("methods/kmeans_clusters.jl")
include("methods/custom_breaks.jl")
include("methods/geometric_interval.jl")
include("methods/arithmetic_progression.jl")
include("methods/nested_means.jl")

# Color utilities
include("colors/colorbrewer.jl")

# Export main API
export ClassificationResult
export classify, classify_with_colors
export get_colorbrewer_palette, list_colorbrewer_palettes
export gini_index, shannon_entropy, goodness_of_variance_fit, compute_class_counts

# Export individual methods
export classify_quantile, classify_quartile, classify_decile
export classify_equal_interval
export classify_natural_breaks
export classify_std_deviation, classify_1std, classify_2std, classify_3std
export classify_pretty_breaks
export classify_headtail_breaks
export classify_maximum_breaks
export classify_box_breaks
export classify_percentiles, classify_deciles, classify_quintiles
export classify_kmeans
export classify_custom_breaks
export classify_geometric_interval
export classify_arithmetic_progression
export classify_nested_means

"""
    classify(data::Vector; method::Symbol=:quantile, n_classes::Int=5, 
              palette::Symbol=:viridis, labels::Vector{String}=String[]) -> ClassificationResult

Classify data using the specified method and return a ClassificationResult.

# Arguments
- `data::Vector`: Data to classify
- `method::Symbol`: Classification method (default: :quantile)
  * :quantile, :equal_interval, :natural_breaks, :standard_deviation, :pretty_breaks
  * :head_tail_breaks, :maximum_breaks, :box_plot, :percentiles, :kmeans
  * :custom_breaks, :geometric_interval, :arithmetic_progression, :nested_means
- `n_classes::Int`: Number of classes (default: 5)
- `palette::Symbol`: Color palette name (default: :Blues)
- `labels::Vector{String}`: Custom class labels (auto-generated if empty)

# Returns
- `ClassificationResult`: Classification with boundaries, labels, colors, and metrics

# Examples
```julia
result = classify([1, 2, 3, 4, 5, 10, 20, 50], method=:natural_breaks, n_classes=3)
result = classify(accessibility_scores, method=:quantile, n_classes=5, palette=:RdYlGn)
```
"""
function compare_classifiers(values::AbstractVector{<:Real}, k::Int = 5;
                               schemes = nothing)::DataFrame
    if schemes === nothing
        schemes = [
            EqualInterval(k), Quantiles(k), NaturalBreaks(k),
            JenksCaspall(k), MaximumBreaks(k), Percentiles(),
            BoxPlot(), HeadTailBreaks(), StdMean(),
        ]
    end

    rows = []
    for sc in schemes
        r = classify(values, sc)
        push!(rows, (
            scheme = r.classifier,
            k      = r.k,
            gvf    = round(r.gvf; digits=4),
            adcm   = round(r.adcm; digits=4),
        ))
    end

    DataFrame(rows)
end

# ============================================================================
# bins_to_labels and choropleth_classify
# ============================================================================

"""
    bins_to_labels(result; labels, fmt) -> Vector{String}

Convert a ClassificationResult to human-readable class labels.
"""
function bins_to_labels(result::ClassificationResult;
                         labels :: Union{Nothing, Vector{String}} = nothing,
                         fmt    :: String = "%.2f")::Vector{String}
    if labels !== nothing
        length(labels) == result.k || error("Need $(result.k) labels, got $(length(labels))")
        return [labels[a] for a in result.assignments]
    end

    class_labels = Vector{String}(undef, result.k)
    for i in 1:result.k
        lo = i == 1 ? -Inf : result.bins[i-1]
        hi = result.bins[i]
        lo_s = isinf(lo) ? "≤$(sprintf1(fmt, hi))" : "$(sprintf1(fmt, lo))–$(sprintf1(fmt, hi))"
        class_labels[i] = lo_s
    end

    [class_labels[a] for a in result.assignments]
end

"""Simple sprintf helper for formatting."""
function sprintf1(fmt::String, x::Float64)::String
    # Parse %[.N]f format
    m = match(r"^%\.?(\d*)f$", fmt)
    if m !== nothing
        n = isempty(m.captures[1]) ? 2 : parse(Int, m.captures[1])
        return string(round(x; digits=n))
    end
    string(x)

function classify(data::Vector;
                  method::Symbol=:quantile,
                  n_classes::Int=5,
                  palette::Symbol=:Blues,
                  labels::Vector{String}=String[])
    
    # Get boundaries based on method
    boundaries = _get_boundaries_for_method(data, method, n_classes)
    
    # Generate labels if not provided
    if isempty(labels)
        labels = _generate_labels(boundaries)
    end
    
    # Get colors from palette
    colors = get_colorbrewer_palette(palette, length(boundaries) - 1)
    
    # Count observations in each class
    counts = compute_class_counts(data, boundaries)
    
    # Compute metrics
    data_clean = filter(x -> !ismissing(x) && !isnan(x) && !isinf(x), data)
    gini = gini_index(counts)
    entropy = shannon_entropy(counts)
    gvf = goodness_of_variance_fit(float.(data_clean), boundaries)
    
    ClassificationResult(boundaries, labels, counts, colors, method, gini, entropy, gvf)

end

"""
    classify_with_colors(data::Vector, method::Symbol; n_classes::Int=5, 
                         palette::Symbol=:viridis) -> ClassificationResult

Convenience function to classify data with automatic color assignment.
"""
function classify_with_colors(data::Vector, method::Symbol;
                              n_classes::Int=5,
                              palette::Symbol=:Blues)
    classify(data; method=method, n_classes=n_classes, palette=palette)
end

"""
    _get_boundaries_for_method(data::Vector, method::Symbol, n_classes::Int) -> Vector{Float64}

Dispatch to the appropriate classification method.
"""
function _get_boundaries_for_method(data::Vector, method::Symbol, n_classes::Int)
    if method == :quantile
        return classify_quantile(data, n_classes)
    elseif method == :equal_interval
        return classify_equal_interval(data, n_classes)
    elseif method == :natural_breaks || method == :jenks
        return classify_natural_breaks(data, n_classes)
    elseif method == :standard_deviation || method == :std_dev
        return classify_std_deviation(data, min(n_classes, 3))
    elseif method == :pretty_breaks
        return classify_pretty_breaks(data, n_classes)
    elseif method == :head_tail_breaks
        return classify_headtail_breaks(data)
    elseif method == :maximum_breaks
        return classify_maximum_breaks(data)
    elseif method == :box_plot || method == :box
        return classify_box_breaks(data)
    elseif method == :percentiles
        return classify_percentiles(data, collect(range(0, 1, length=n_classes+1)[2:end-1]))
    elseif method == :kmeans
        return classify_kmeans(data, n_classes)
    elseif method == :custom_breaks
        # For custom breaks, use equal intervals as default
        return classify_equal_interval(data, n_classes)
    elseif method == :geometric_interval
        return classify_geometric_interval(data, n_classes)
    elseif method == :arithmetic_progression
        return classify_arithmetic_progression(data, n_classes)
    elseif method == :nested_means
        return classify_nested_means(data)
    else
        error("Unknown classification method: $method")
    end
end

"""
    _generate_labels(boundaries::Vector{Float64}) -> Vector{String}

Generate class labels from boundaries.
"""
function _generate_labels(boundaries::Vector{Float64})
    if length(boundaries) < 2
        return ["All"]
    end

    labels = String[]
    for i in 1:length(boundaries)-1
        lower = round(boundaries[i], digits=2)
        upper = round(boundaries[i+1], digits=2)
        push!(labels, "[$lower - $upper)")
    end
    labels[end] = replace(labels[end], ")" => "]")  # Make last interval inclusive
    labels
end

end  # module MapClassify
