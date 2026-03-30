# fairness.jl — Bias mitigation and threshold optimisation for HealthEquity
# Chapter 48 — Open-Source Healthcare GIS Textbook in Julia

# ── Threshold sweep ───────────────────────────────────────────────────────────

"""
    threshold_sweep(probs, y, groups; thresholds) -> DataFrame

Evaluate fairness metrics at each decision threshold for each group.
Returns a DataFrame with TPR, FPR, PPV, accuracy, DP diff, EO gap at each threshold.
"""
function threshold_sweep(
    probs      :: AbstractVector{<:AbstractFloat},
    y          :: AbstractVector{<:Integer},
    groups     :: AbstractVector;
    thresholds :: AbstractVector{<:AbstractFloat} = 0.05:0.05:0.95,
)
    rows = []
    for τ in thresholds
        ŷ = Int.(probs .>= τ)
        ug = sort(unique(groups))
        tprs = Float64[]; fprs = Float64[]
        pos_rates = Float64[]

        for g in ug
            mask = groups .== g
            ŷ_g = ŷ[mask]; y_g = y[mask]
            tp = sum((ŷ_g .== 1) .& (y_g .== 1))
            fn = sum((ŷ_g .== 0) .& (y_g .== 1))
            fp = sum((ŷ_g .== 1) .& (y_g .== 0))
            tn = sum((ŷ_g .== 0) .& (y_g .== 0))
            push!(tprs, tp / max(tp+fn, 1))
            push!(fprs, fp / max(fp+tn, 1))
            push!(pos_rates, mean(ŷ_g))
        end

        acc = mean(ŷ .== y)
        dp_diff   = length(pos_rates) >= 2 ? maximum(pos_rates) - minimum(pos_rates) : 0.0
        eo_tpr    = length(tprs) >= 2 ? maximum(tprs) - minimum(tprs) : 0.0
        eo_fpr    = length(fprs) >= 2 ? maximum(fprs) - minimum(fprs) : 0.0

        push!(rows, (threshold=τ, accuracy=acc,
                     dp_diff=dp_diff, eo_gap_tpr=eo_tpr, eo_gap_fpr=eo_fpr,
                     pos_rate=mean(ŷ)))
    end
    DataFrame(rows)
end

"""
    equalise_tpr(probs, y, groups; α) -> Dict

Find group-specific decision thresholds such that all groups have
equal true positive rate (± tolerance α).  Returns Dict(group => threshold).
"""
function equalise_tpr(
    probs  :: AbstractVector{<:AbstractFloat},
    y      :: AbstractVector{<:Integer},
    groups :: AbstractVector;
    target_tpr :: Union{Float64, Nothing} = nothing,
)
    ug = sort(unique(groups))
    thresholds = 0.01:0.01:0.99

    # Compute TPR(τ) for each group
    group_tpr_curves = Dict{eltype(ug), Vector{Float64}}()
    for g in ug
        mask = groups .== g
        p_g  = probs[mask]; y_g = y[mask]
        tprs = Float64[]
        for τ in thresholds
            ŷ_g = Int.(p_g .>= τ)
            tp  = sum((ŷ_g .== 1) .& (y_g .== 1))
            fn  = sum((ŷ_g .== 0) .& (y_g .== 1))
            push!(tprs, tp / max(tp+fn, 1))
        end
        group_tpr_curves[g] = tprs
    end

    # Target: pooled TPR at threshold 0.5 (or user-specified)
    if isnothing(target_tpr)
        ŷ05 = Int.(probs .>= 0.5)
        tp  = sum((ŷ05 .== 1) .& (y .== 1))
        fn  = sum((ŷ05 .== 0) .& (y .== 1))
        target_tpr = tp / max(tp+fn, 1)
    end

    result = Dict{eltype(ug), Float64}()
    for g in ug
        tprs = group_tpr_curves[g]
        # Find threshold that achieves target_tpr (binary search on sorted curve)
        best_τ = 0.5
        best_dist = Inf
        for (i, τ) in enumerate(thresholds)
            dist = abs(tprs[i] - target_tpr)
            if dist < best_dist
                best_dist = dist
                best_τ = τ
            end
        end
        result[g] = best_τ
    end
    result
end

"""
    equalise_fpr(probs, y, groups) -> Dict

Find group-specific thresholds achieving equal false positive rates.
"""
function equalise_fpr(
    probs  :: AbstractVector{<:AbstractFloat},
    y      :: AbstractVector{<:Integer},
    groups :: AbstractVector;
    target_fpr :: Union{Float64, Nothing} = nothing,
)
    ug = sort(unique(groups))
    thresholds = 0.01:0.01:0.99

    group_fpr_curves = Dict{eltype(ug), Vector{Float64}}()
    for g in ug
        mask = groups .== g; p_g = probs[mask]; y_g = y[mask]
        fprs = Float64[]
        for τ in thresholds
            ŷ_g = Int.(p_g .>= τ)
            fp  = sum((ŷ_g .== 1) .& (y_g .== 0))
            tn  = sum((ŷ_g .== 0) .& (y_g .== 0))
            push!(fprs, fp / max(fp+tn, 1))
        end
        group_fpr_curves[g] = fprs
    end

    if isnothing(target_fpr)
        ŷ05 = Int.(probs .>= 0.5)
        fp  = sum((ŷ05 .== 1) .& (y .== 0))
        tn  = sum((ŷ05 .== 0) .& (y .== 0))
        target_fpr = fp / max(fp+tn, 1)
    end

    result = Dict{eltype(ug), Float64}()
    for g in ug
        fprs = group_fpr_curves[g]
        best_τ = 0.5; best_dist = Inf
        for (i, τ) in enumerate(thresholds)
            dist = abs(fprs[i] - target_fpr)
            if dist < best_dist
                best_dist = dist; best_τ = τ
            end
        end
        result[g] = best_τ
    end
    result
end

"""
    apply_group_thresholds(probs, groups, thresholds) -> Vector{Int}

Apply group-specific decision thresholds to produce binary predictions.
"""
function apply_group_thresholds(
    probs      :: AbstractVector{<:AbstractFloat},
    groups     :: AbstractVector,
    thresholds :: Dict,
)
    ŷ = similar(probs, Int)
    for i in eachindex(probs)
        g = groups[i]
        τ = get(thresholds, g, 0.5)
        ŷ[i] = Int(probs[i] >= τ)
    end
    ŷ
end

# ── Platt calibration by group ────────────────────────────────────────────────

"""
    platt_calibrate_by_group(probs_cal, y_cal, groups_cal; ε) -> Dict{group → (a, b)}

Fit a logistic (Platt) calibration model for each group independently.
Calibrated probability: p_cal = σ(a·logit(p) + b).
"""
function platt_calibrate_by_group(
    probs  :: AbstractVector{<:AbstractFloat},
    y      :: AbstractVector{<:Integer},
    groups :: AbstractVector;
    ε      :: Float64 = 1e-7,
    n_iter :: Int     = 100,
    lr     :: Float64 = 0.1,
)
    ug = sort(unique(groups))
    params = Dict{eltype(ug), NamedTuple}()

    for g in ug
        mask = groups .== g
        p_g  = probs[mask]; y_g = y[mask]

        # Logit transform
        p_clip = clamp.(p_g, ε, 1-ε)
        logit  = log.(p_clip ./ (1 .- p_clip))

        # Gradient descent on logistic loss
        a = 1.0; b = 0.0
        for _ in 1:n_iter
            p_cal = 1 ./ (1 .+ exp.(-(a .* logit .+ b)))
            # Gradient of BCE
            δ = p_cal .- y_g
            ∂a = mean(δ .* logit)
            ∂b = mean(δ)
            a -= lr * ∂a
            b -= lr * ∂b
        end
        params[g] = (a=a, b=b)
    end
    params
end

"""
    apply_group_calibration(probs, groups, calibration_params; ε) -> Vector{Float64}

Apply group-specific Platt calibration to raw probabilities.
"""
function apply_group_calibration(
    probs  :: AbstractVector{<:AbstractFloat},
    groups :: AbstractVector,
    params :: Dict;
    ε      :: Float64 = 1e-7,
)
    p_clip = clamp.(probs, ε, 1-ε)
    logit  = log.(p_clip ./ (1 .- p_clip))
    p_cal  = similar(probs)
    for i in eachindex(probs)
        g = groups[i]
        ab = get(params, g, (a=1.0, b=0.0))
        p_cal[i] = 1 / (1 + exp(-(ab.a * logit[i] + ab.b)))
    end
    p_cal
end
