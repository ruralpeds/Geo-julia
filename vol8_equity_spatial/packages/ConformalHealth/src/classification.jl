# classification.jl — Conformal prediction sets for classification
# Chapter 50 — Open-Source Healthcare GIS Textbook in Julia
#
# Adaptive Prediction Sets (Angelopoulos, Bates, Jordan & Malik 2021 — RAPS):
# Produces prediction sets C(x) ⊆ {1,...,K} with P(y ∈ C(x)) ≥ 1-α.
#
# Algorithm:
# 1. Sort class probabilities in decreasing order: π_1 ≥ π_2 ≥ ... ≥ π_K
# 2. Score: s(x,y) = Σ_{j: π_j ≥ π_y} π_j - u·π_y   (u ~ Uniform(0,1))
#    Simpler: s(x,y) = cumulative probability up to and including true class
# 3. q̂ = ⌈(n+1)(1-α)⌉/n quantile of {s_i}
# 4. C(x) = {y: s(x,y) ≤ q̂}

"""
    AdaptivePredictionSet

Calibrated conformal prediction set for classification.
"""
struct AdaptivePredictionSet
    q̂        :: Float64
    α        :: Float64
    n_calib  :: Int
    n_classes :: Int
    score_type :: Symbol   # :aps or :lac (least ambiguous classifier)
end

"""
    aps_fit(probs_calib, y_calib; α, score_type) -> AdaptivePredictionSet

Calibrate an Adaptive Prediction Set (APS) on held-out calibration data.
probs_calib: n_calib × n_classes probability matrix.
y_calib: true class labels (1-indexed).
"""
function aps_fit(
    probs_calib :: AbstractMatrix,
    y_calib     :: AbstractVector{<:Integer};
    α           :: Float64 = 0.1,
    score_type  :: Symbol  = :aps,
)
    n, K = size(probs_calib)
    scores = Float64[]

    for i in 1:n
        yi  = y_calib[i]
        pi  = probs_calib[i, :]
        s_i = _conformity_score(pi, yi, score_type)
        push!(scores, s_i)
    end

    level = ceil((n + 1) * (1 - α)) / n
    q̂ = quantile(scores, clamp(level, 0.0, 1.0))

    AdaptivePredictionSet(q̂, α, n, K, score_type)
end

function _conformity_score(p::AbstractVector, y::Integer, score_type::Symbol)
    K = length(p)
    order = sortperm(p; rev=true)   # decreasing probability order

    if score_type == :lac
        # Least Ambiguous Classifier: cumsum of sorted probs until y is included
        cum = 0.0
        for j in order
            cum += p[j]
            j == y && return cum
        end
        return 1.0
    else
        # APS: cumsum score with randomisation to handle ties
        cum = 0.0
        for j in order
            cum += p[j]
            j == y && return cum - rand() * p[j]  # subtract uniform·p_y
        end
        return 1.0
    end
end

"""
    aps_predict(model, probs_new) -> Vector{Vector{Int}}

Generate prediction sets for new observations.
"""
function aps_predict(model::AdaptivePredictionSet, probs_new::AbstractMatrix)
    n = size(probs_new, 1)
    sets = Vector{Vector{Int}}(undef, n)

    for i in 1:n
        pi = probs_new[i, :]
        order = sortperm(pi; rev=true)
        cum = 0.0
        pred_set = Int[]
        for j in order
            cum += pi[j]
            push!(pred_set, j)
            cum > model.q̂ && break
        end
        sets[i] = sort(pred_set)
    end
    sets
end

"""
    conformal_classify(probs_new, model) -> DataFrame

Return prediction sets with set sizes and uncertainty measures.
"""
function conformal_classify(probs_new::AbstractMatrix, model::AdaptivePredictionSet)
    sets = aps_predict(model, probs_new)
    n = size(probs_new, 1)

    DataFrame(
        pred_set   = [join(s, ",") for s in sets],
        set_size   = [length(s) for s in sets],
        max_prob   = [maximum(probs_new[i, :]) for i in 1:n],
        entropy    = [-sum(p*log(p+1e-12) for p in probs_new[i,:]) for i in 1:n],
        uncertain  = [length(s) > 1 for s in sets],
    )
end
