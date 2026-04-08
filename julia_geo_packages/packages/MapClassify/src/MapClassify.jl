"""
    MapClassify.jl

Choropleth map classification schemes for Julia.
Port of Python's mapclassify library to Julia.

Implements 15 classification schemes:
1.  EqualInterval       — equal-width bins
2.  Quantiles           — equal-count bins
3.  NaturalBreaks       — Fisher-Jenks optimal natural breaks
4.  JenksCaspall        — Jenks-Caspall heuristic
5.  FisherJenks         — Fisher (1958) dynamic programming (identical result to NaturalBreaks)
6.  StdMean             — standard deviation around mean
7.  MaximumBreaks       — largest gaps between sorted values
8.  BoxPlot             — hinge-based (1.5 IQR)
9.  HeadTailBreaks      — Jiang (2013) head/tail recursive
10. Percentiles         — custom percentile cuts
11. UserDefined         — user-supplied break points
12. PrettyBreaks        — nice round-number breaks
13. GeometricInterval   — geometric progression bins
14. JenksCaspallSampled — sampled Jenks for large datasets
15. KMeans              — k-means clustering on 1D values

Vol 3 — Julia Package Engineering, Chapter 22.4
"""
module MapClassify

using Statistics
using StatsBase

# ── Type exports ─────────────────────────────────────────────────────────────
export AbstractClassifier
export EqualInterval, Quantiles, NaturalBreaks, FisherJenks, JenksCaspall
export StdMean, MaximumBreaks, BoxPlot, HeadTailBreaks, Percentiles
export UserDefined, PrettyBreaks, GeometricInterval, JenksCaspallSampled, KMeans
export ClassificationResult

# ── Function exports ──────────────────────────────────────────────────────────
export classify, compare_classifiers, bins_to_labels, choropleth_classify

# ============================================================================
# Types
# ============================================================================

"""Abstract base for all classification schemes."""
abstract type AbstractClassifier end

"""
    ClassificationResult

Result of a map classification.

# Fields
- `bins`       : upper bounds of each class (last = maximum value)
- `counts`     : number of observations in each class
- `assignments`: class index (1-based) for each observation
- `k`          : number of classes
- `classifier` : name of the scheme used
- `gvf`        : goodness of variance fit (0–1); 1 = perfect
- `adcm`       : average deviation from class means (lower = better)
"""
struct ClassificationResult
    bins        :: Vector{Float64}
    counts      :: Vector{Int}
    assignments :: Vector{Int}
    k           :: Int
    classifier  :: String
    gvf         :: Float64
    adcm        :: Float64
end

function Base.show(io::IO, r::ClassificationResult)
    println(io, "$(r.classifier)(k=$(r.k), GVF=$(round(r.gvf; digits=4)))")
    for i in 1:r.k
        lo = i == 1 ? -Inf : r.bins[i-1]
        hi = r.bins[i]
        println(io, "  Class $i: ($(round(lo;digits=3)), $(round(hi;digits=3))]: $(r.counts[i]) obs")
    end
end

# ── Classifier structs ────────────────────────────────────────────────────────

struct EqualInterval        <: AbstractClassifier; k::Int; end
struct Quantiles            <: AbstractClassifier; k::Int; end
struct NaturalBreaks        <: AbstractClassifier; k::Int; end
struct FisherJenks          <: AbstractClassifier; k::Int; end
struct JenksCaspall         <: AbstractClassifier; k::Int; end
struct StdMean              <: AbstractClassifier; multiples::Float64; end
struct MaximumBreaks        <: AbstractClassifier; k::Int; end
struct BoxPlot              <: AbstractClassifier; hinge::Float64; end
struct HeadTailBreaks       <: AbstractClassifier; end
struct Percentiles          <: AbstractClassifier; pcts::Vector{Float64}; end
struct UserDefined          <: AbstractClassifier; bins::Vector{Float64}; end
struct PrettyBreaks         <: AbstractClassifier; k::Int; end
struct GeometricInterval    <: AbstractClassifier; k::Int; end
struct JenksCaspallSampled  <: AbstractClassifier; k::Int; sample_size::Int; end
struct KMeans               <: AbstractClassifier; k::Int; max_iter::Int; end

# Convenience constructors with defaults
StdMean(;multiples=1.0) = StdMean(multiples)
BoxPlot(;hinge=1.5) = BoxPlot(hinge)
HeadTailBreaks() = HeadTailBreaks()
JenksCaspallSampled(k; sample_size=3000) = JenksCaspallSampled(k, sample_size)
KMeans(k; max_iter=300) = KMeans(k, max_iter)
Percentiles(pcts=[10,25,50,75,90,100.0]) = Percentiles(Float64.(pcts))

# ============================================================================
# classify — main dispatch
# ============================================================================

"""
    classify(values, classifier) -> ClassificationResult

Classify a numeric vector using the given scheme.
"""
function classify(values::AbstractVector{<:Real}, c::AbstractClassifier)::ClassificationResult
    _classify(Float64.(values), c)
end

# ── EqualInterval ─────────────────────────────────────────────────────────────
function _classify(x::Vector{Float64}, c::EqualInterval)::ClassificationResult
    lo, hi = minimum(x), maximum(x)
    width = (hi - lo) / c.k
    bins = [lo + i * width for i in 1:c.k]
    bins[end] = hi
    _make_result(x, bins, "EqualInterval")
end

# ── Quantiles ─────────────────────────────────────────────────────────────────
function _classify(x::Vector{Float64}, c::Quantiles)::ClassificationResult
    probs = [(i / c.k) for i in 1:c.k]
    bins  = quantile(x, probs)
    bins[end] = maximum(x)
    _make_result(x, bins, "Quantiles")
end

# ── NaturalBreaks / FisherJenks ───────────────────────────────────────────────
"""
Fisher-Jenks O(n·k) dynamic programming natural breaks.
Populates error_matrix[i,j] = within-class SSE for classes 1..j ending at index i.
"""
function _classify(x::Vector{Float64}, c::NaturalBreaks)::ClassificationResult
    bins = _fisher_jenks_dp(sort(x), c.k)
    _make_result(x, bins, "NaturalBreaks")
end

function _classify(x::Vector{Float64}, c::FisherJenks)::ClassificationResult
    bins = _fisher_jenks_dp(sort(x), c.k)
    _make_result(x, bins, "FisherJenks")
end

function _fisher_jenks_dp(xs::Vector{Float64}, k::Int)::Vector{Float64}
    n = length(xs)
    k = min(k, n)
    k == 1 && return [xs[end]]
    k == n && return xs

    # error_matrix[i,j]: min SSE for j classes using elements 1..i
    error_matrix = fill(Inf, n, k)
    membership   = zeros(Int, n, k)

    # j=1: single class from 1..i
    for i in 1:n
        error_matrix[i, 1] = _sse(xs, 1, i)
        membership[i, 1]   = 1
    end

    # Fill for j=2..k
    for j in 2:k
        for i in j:n
            for m in (j-1):(i-1)
                cost = error_matrix[m, j-1] + _sse(xs, m+1, i)
                if cost < error_matrix[i, j]
                    error_matrix[i, j] = cost
                    membership[i, j]   = m
                end
            end
        end
    end

    # Backtrack to find break points
    breaks = Vector{Float64}(undef, k)
    breaks[k] = xs[n]
    idx = n
    for j in k:-1:2
        m = membership[idx, j]
        breaks[j-1] = xs[m]
        idx = m
    end
    breaks
end

# SSE of xs[lo..hi] (1-indexed, inclusive)
function _sse(xs::Vector{Float64}, lo::Int, hi::Int)::Float64
    n = hi - lo + 1
    n == 0 && return 0.0
    n == 1 && return 0.0
    μ = sum(xs[lo:hi]) / n
    sum((xs[i] - μ)^2 for i in lo:hi)
end

# ── JenksCaspall (heuristic, faster than DP for large n) ─────────────────────
function _classify(x::Vector{Float64}, c::JenksCaspall)::ClassificationResult
    xs = sort(x)
    n  = length(xs)
    # Initial: equal interval
    bins = collect(range(xs[1], xs[end]; length=c.k+1))[2:end]
    bins[end] = xs[end]

    # Iterative reassignment
    for _ in 1:10
        assigns = _assign_bins(xs, bins)
        new_bins = copy(bins)
        for cls in 1:c.k
            members = xs[assigns .== cls]
            isempty(members) && continue
            new_bins[cls] = maximum(members)
        end
        new_bins[end] = xs[end]
        sort!(new_bins)
        new_bins == bins && break
        bins = new_bins
    end

    _make_result(x, bins, "JenksCaspall")
end

# ── StdMean ───────────────────────────────────────────────────────────────────
function _classify(x::Vector{Float64}, c::StdMean)::ClassificationResult
    μ, σ = mean(x), std(x; corrected=true)
    multiples = c.multiples
    # Classes: < μ-2σ, μ-2σ..μ-σ, μ-σ..μ, μ..μ+σ, μ+σ..μ+2σ, > μ+2σ
    raw_bins = [μ + m * σ for m in (-2*multiples, -multiples, 0.0, multiples, 2*multiples)]
    bins = vcat(raw_bins, maximum(x))
    bins = filter(b -> b > minimum(x), bins)
    bins[end] = maximum(x)
    sort!(unique!(bins))
    _make_result(x, bins, "StdMean")
end

# ── MaximumBreaks ─────────────────────────────────────────────────────────────
function _classify(x::Vector{Float64}, c::MaximumBreaks)::ClassificationResult
    xs = sort(x)
    gaps = diff(xs)
    # Top (k-1) largest gaps define break points
    break_indices = partialsortperm(gaps, 1:min(c.k-1, length(gaps)); rev=true)
    break_vals = sort([xs[i] for i in break_indices])
    bins = vcat(break_vals, maximum(xs))
    _make_result(x, bins, "MaximumBreaks")
end

# ── BoxPlot ───────────────────────────────────────────────────────────────────
function _classify(x::Vector{Float64}, c::BoxPlot)::ClassificationResult
    q1 = quantile(x, 0.25)
    q3 = quantile(x, 0.75)
    med = median(x)
    iqr = q3 - q1
    lo = q1 - c.hinge * iqr
    hi = q3 + c.hinge * iqr
    raw_bins = sort(unique([lo, q1, med, q3, hi, maximum(x)]))
    bins = filter(b -> b > minimum(x), raw_bins)
    isempty(bins) && (bins = [maximum(x)])
    bins[end] = maximum(x)
    _make_result(x, bins, "BoxPlot")
end

# ── HeadTailBreaks (Jiang 2013) ───────────────────────────────────────────────
function _classify(x::Vector{Float64}, ::HeadTailBreaks)::ClassificationResult
    breaks = _head_tail_recursive(x, Float64[])
    bins = sort(unique(vcat(breaks, maximum(x))))
    isempty(bins) && (bins = [maximum(x)])
    bins[end] = maximum(x)
    _make_result(x, bins, "HeadTailBreaks")
end

function _head_tail_recursive(x::Vector{Float64}, breaks::Vector{Float64})::Vector{Float64}
    length(x) < 2 && return breaks
    μ = mean(x)
    head = filter(>(μ), x)
    isempty(head) && return breaks
    length(head) / length(x) >= 0.4 && return vcat(breaks, μ)  # stop if not heavy-tailed
    _head_tail_recursive(head, vcat(breaks, μ))
end

# ── Percentiles ───────────────────────────────────────────────────────────────
function _classify(x::Vector{Float64}, c::Percentiles)::ClassificationResult
    pcts = sort(c.pcts)
    pcts[end] != 100.0 && push!(pcts, 100.0)
    bins = [quantile(x, p/100) for p in pcts]
    bins[end] = maximum(x)
    _make_result(x, bins, "Percentiles")
end

# ── UserDefined ───────────────────────────────────────────────────────────────
function _classify(x::Vector{Float64}, c::UserDefined)::ClassificationResult
    bins = sort(c.bins)
    bins[end] < maximum(x) && push!(bins, maximum(x))
    _make_result(x, bins, "UserDefined")
end

# ── PrettyBreaks ──────────────────────────────────────────────────────────────
function _classify(x::Vector{Float64}, c::PrettyBreaks)::ClassificationResult
    lo, hi = minimum(x), maximum(x)
    range_val = hi - lo
    step_raw  = range_val / c.k
    mag = 10.0^floor(log10(step_raw))
    nice_steps = [1.0, 2.0, 2.5, 5.0, 10.0]
    step = mag * nice_steps[argmin(abs.(nice_steps .- step_raw / mag))]
    start = ceil(lo / step) * step
    bins = collect(start:step:(hi + step))
    bins = filter(b -> b > lo && b <= hi + 1e-9, bins)
    isempty(bins) && (bins = [hi])
    bins[end] = hi
    length(bins) > c.k && (bins = bins[round.(Int, range(1, length(bins); length=c.k))])
    _make_result(x, bins, "PrettyBreaks")
end

# ── GeometricInterval ─────────────────────────────────────────────────────────
function _classify(x::Vector{Float64}, c::GeometricInterval)::ClassificationResult
    lo, hi = minimum(x), maximum(x)
    # All values must be positive for geometric intervals
    if lo <= 0
        @warn "GeometricInterval: non-positive values; shifting by $(1 - lo + 1e-9)"
        shift = 1 - lo + 1e-9
        x = x .+ shift
        lo, hi = minimum(x), maximum(x)
    end
    ratio = (hi / lo)^(1 / c.k)
    bins = [lo * ratio^i for i in 1:c.k]
    bins[end] = maximum(x)
    _make_result(x, bins, "GeometricInterval")
end

# ── JenksCaspallSampled ───────────────────────────────────────────────────────
function _classify(x::Vector{Float64}, c::JenksCaspallSampled)::ClassificationResult
    n = length(x)
    if n > c.sample_size
        idx = sort(sample(1:n, c.sample_size; replace=false))
        x_s = x[idx]
    else
        x_s = x
    end
    r = _classify(x_s, JenksCaspall(c.k))
    # Apply breaks from sample to full dataset
    _make_result(x, r.bins, "JenksCaspallSampled")
end

# ── KMeans 1D ─────────────────────────────────────────────────────────────────
function _classify(x::Vector{Float64}, c::KMeans)::ClassificationResult
    xs = sort(x)
    n  = length(xs)
    k  = min(c.k, n)

    # Initialise centroids at quantiles
    centroids = [quantile(xs, i / (k + 1)) for i in 1:k]

    assigns = zeros(Int, n)
    for _ in 1:c.max_iter
        # Assignment step
        new_assigns = [argmin(abs.(v .- centroids)) for v in xs]
        new_assigns == assigns && break
        assigns = new_assigns
        # Update centroids
        for j in 1:k
            members = xs[assigns .== j]
            !isempty(members) && (centroids[j] = mean(members))
        end
    end

    # Derive bins from class boundaries
    bins = Float64[]
    for j in 1:(k-1)
        members_j   = xs[assigns .== j]
        members_j1  = xs[assigns .== j+1]
        isempty(members_j) && continue
        isempty(members_j1) && continue
        push!(bins, (maximum(members_j) + minimum(members_j1)) / 2)
    end
    push!(bins, maximum(xs))
    sort!(bins)
    _make_result(x, bins, "KMeans")
end

# ============================================================================
# Helpers
# ============================================================================

"""Assign each value in x to the appropriate bin (1-indexed)."""
function _assign_bins(x::AbstractVector{Float64}, bins::Vector{Float64})::Vector{Int}
    [searchsortedfirst(bins, v) for v in x]
end

"""Compute ClassificationResult from values and break points."""
function _make_result(x::Vector{Float64}, bins::Vector{Float64}, name::String)::ClassificationResult
    bins = sort(unique(bins))
    isempty(bins) && push!(bins, maximum(x))
    bins[end] < maximum(x) && (bins[end] = maximum(x))
    k = length(bins)

    assigns = _assign_bins(x, bins)
    # Clamp any overflows to k
    assigns = clamp.(assigns, 1, k)

    counts = [count(==(j), assigns) for j in 1:k]

    gvf  = _gvf(x, assigns, k)
    adcm = _adcm(x, assigns, k)

    ClassificationResult(bins, counts, assigns, k, name, gvf, adcm)
end

"""Goodness of Variance Fit = 1 - SDCM/SDAM"""
function _gvf(x::Vector{Float64}, assigns::Vector{Int}, k::Int)::Float64
    sdam = sum((xi - mean(x))^2 for xi in x)
    sdam ≈ 0.0 && return 1.0
    sdcm = sum(
        begin
            members = x[assigns .== j]
            isempty(members) ? 0.0 : sum((v - mean(members))^2 for v in members)
        end
        for j in 1:k
    )
    1.0 - sdcm / sdam
end

"""Average Deviation from Class Means"""
function _adcm(x::Vector{Float64}, assigns::Vector{Int}, k::Int)::Float64
    total = 0.0
    for j in 1:k
        members = x[assigns .== j]
        isempty(members) && continue
        μ = mean(members)
        total += sum(abs(v - μ) for v in members)
    end
    total / max(length(x), 1)
end

"""Fisher-Jenks without replacement sample"""
function sample(pool::AbstractVector, n::Int; replace::Bool=false)
    replace && return pool[rand(1:length(pool), n)]
    copy(pool[shuffle!(collect(1:length(pool)))[1:min(n, length(pool))]])
end

function shuffle!(x::Vector)
    n = length(x)
    for i in n:-1:2
        j = rand(1:i)
        x[i], x[j] = x[j], x[i]
    end
    x
end

# ============================================================================
# compare_classifiers
# ============================================================================

"""
    compare_classifiers(values, k; schemes) -> DataFrame

Compare multiple classification schemes on the same dataset.
Returns a DataFrame with GVF, ADCM, and class counts for each scheme.

# Arguments
- `values`  : numeric vector
- `k`       : number of classes to use for k-based schemes
- `schemes` : vector of classifier instances (default: all k-based schemes)
"""
function compare_classifiers(values::AbstractVector{<:Real}, k::Int = 5;
                               schemes = nothing)::DataFrames.DataFrame
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

    DataFrames.DataFrame(rows)
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
end

"""
    choropleth_classify(values, k; scheme=:NaturalBreaks) -> ClassificationResult

Convenience wrapper: classify for choropleth mapping.
Scheme can be a Symbol (:NaturalBreaks, :Quantiles, :EqualInterval, etc.) or
an AbstractClassifier instance.
"""
function choropleth_classify(values::AbstractVector{<:Real}, k::Int;
                               scheme = :NaturalBreaks)::ClassificationResult
    classifier = if scheme isa Symbol
        scheme_map = Dict(
            :NaturalBreaks  => NaturalBreaks(k),
            :FisherJenks    => FisherJenks(k),
            :Quantiles      => Quantiles(k),
            :EqualInterval  => EqualInterval(k),
            :JenksCaspall   => JenksCaspall(k),
            :MaximumBreaks  => MaximumBreaks(k),
            :BoxPlot        => BoxPlot(),
            :HeadTailBreaks => HeadTailBreaks(),
            :StdMean        => StdMean(),
            :KMeans         => KMeans(k),
        )
        get(scheme_map, scheme) do
            error("Unknown scheme :$(scheme). Available: $(keys(scheme_map))")
        end
    else
        scheme
    end
    classify(values, classifier)
end

end # module MapClassify

# Import DataFrames for compare_classifiers
using DataFrames
