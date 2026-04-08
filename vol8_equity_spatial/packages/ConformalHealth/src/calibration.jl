# calibration.jl — Probability calibration for ConformalHealth
# Chapter 50 — Open-Source Healthcare GIS Textbook in Julia

# ── Temperature scaling ───────────────────────────────────────────────────────

"""
    temperature_scaling(logits, y; T_init, lr, max_iter) -> (T, calibrated_probs)

Temperature scaling (Guo et al. 2017): single scalar calibration for neural
network softmax outputs.  T* = argmin_T NLL(σ(logits/T), y).
"""
function temperature_scaling(
    logits  :: AbstractMatrix,    # n × K (before softmax)
    y       :: AbstractVector{<:Integer};
    T_init  :: Float64 = 1.0,
    lr      :: Float64 = 0.01,
    max_iter :: Int    = 500,
    tol     :: Float64 = 1e-6,
)
    n, K = size(logits)
    T = T_init

    function nll(T_val)
        T_val <= 0 && return Inf
        logits_T = logits ./ T_val
        log_p = logits_T .- log.(sum(exp.(logits_T .- maximum(logits_T; dims=2)); dims=2) .+ 1e-12 .+ maximum(logits_T; dims=2))
        -mean(log_p[i, y[i]] for i in 1:n)
    end

    # Gradient descent via finite differences
    for _ in 1:max_iter
        T_prev = T
        h = 1e-5
        g = (nll(T + h) - nll(T - h)) / (2h)
        T = max(T - lr * g, 0.01)
        abs(T - T_prev) < tol && break
    end

    # Calibrated probabilities
    logits_T = logits ./ T
    # Numerically stable softmax
    logits_T_shifted = logits_T .- maximum(logits_T; dims=2)
    probs = exp.(logits_T_shifted) ./ sum(exp.(logits_T_shifted); dims=2)

    T, probs
end

# ── Isotonic regression calibration ─────────────────────────────────────────

"""
    isotonic_calibrate(probs, y; n_bins) -> (calibrated_probs_fn, knots)

Fit a monotone isotonic regression calibration function on binary labels.
Uses Pool Adjacent Violators Algorithm (PAVA).
Returns a callable that maps raw probabilities to calibrated probabilities.
"""
function isotonic_calibrate(
    probs :: AbstractVector{<:AbstractFloat},
    y     :: AbstractVector{<:Integer};
    n_bins :: Int = 15,
)
    # Bin into n_bins equally-spaced probability bins
    order = sortperm(probs)
    p_sorted = probs[order]
    y_sorted = Float64.(y[order])

    # PAVA: pool adjacent violators to enforce monotonicity
    blocks = [(mean=y_sorted[i], w=1.0, lo=i, hi=i) for i in 1:length(y_sorted)]
    blocks = collect(blocks)

    changed = true
    while changed
        changed = false
        new_blocks = similar(blocks, 0)
        push!(new_blocks, blocks[1])
        for i in 2:length(blocks)
            if blocks[i].mean < new_blocks[end].mean
                # Merge with previous block
                prev = new_blocks[end]
                merged_w   = prev.w + blocks[i].w
                merged_mean = (prev.mean * prev.w + blocks[i].mean * blocks[i].w) / merged_w
                new_blocks[end] = (mean=merged_mean, w=merged_w, lo=prev.lo, hi=blocks[i].hi)
                changed = true
            else
                push!(new_blocks, blocks[i])
            end
        end
        blocks = new_blocks
    end

    # Build calibrated probability array
    cal_probs = zeros(length(p_sorted))
    for blk in blocks
        cal_probs[blk.lo:blk.hi] .= blk.mean
    end

    # Restore original order
    cal_probs_orig = similar(cal_probs)
    cal_probs_orig[order] = cal_probs

    # Build piecewise-linear interpolation function
    # (simplified: use sorted knot pairs)
    knots = collect(zip(p_sorted, cal_probs))

    cal_fn = function(p_new::AbstractVector)
        map(p_new) do p
            if p <= p_sorted[1]
                return cal_probs[1]
            elseif p >= p_sorted[end]
                return cal_probs[end]
            end
            idx = searchsortedfirst(p_sorted, p)
            lo, hi = max(1, idx-1), min(length(p_sorted), idx)
            t = (hi == lo) ? 0.0 : (p - p_sorted[lo]) / (p_sorted[hi] - p_sorted[lo])
            cal_probs[lo] * (1-t) + cal_probs[hi] * t
        end
    end

    cal_probs_orig, cal_fn, knots
end

# ── Calibration error ─────────────────────────────────────────────────────────

"""
    CalibrationResult

Expected Calibration Error (ECE) and related metrics.
"""
struct CalibrationResult
    ece         :: Float64   # Expected Calibration Error
    mce         :: Float64   # Maximum Calibration Error
    brier       :: Float64   # Brier score
    log_loss    :: Float64
    bins        :: DataFrame
end

"""
    calibration_error(probs, y; n_bins) -> CalibrationResult

Compute ECE = Σ_b |B_b|/n · |acc(B_b) - conf(B_b)|
"""
function calibration_error(
    probs :: AbstractVector{<:AbstractFloat},
    y     :: AbstractVector{<:Integer};
    n_bins :: Int = 10,
)
    n = length(probs)
    bins_edges = range(0, 1; length=n_bins+1)
    bin_rows = []

    for b in 1:n_bins
        lo, hi = bins_edges[b], bins_edges[b+1]
        mask = (probs .>= lo) .& (probs .< hi)
        n_b  = sum(mask)
        n_b == 0 && continue

        acc_b  = mean(Float64.(y[mask]))
        conf_b = mean(probs[mask])
        push!(bin_rows, (bin=b, lo=lo, hi=hi, n=n_b,
                          accuracy=acc_b, confidence=conf_b,
                          gap=abs(acc_b - conf_b),
                          weight=n_b/n))
    end

    bins_df = isempty(bin_rows) ? DataFrame() : DataFrame(bin_rows)
    ece = isempty(bins_df) ? 0.0 : sum(bins_df.weight .* bins_df.gap)
    mce = isempty(bins_df) ? 0.0 : maximum(bins_df.gap)

    # Brier score and log-loss
    ε = 1e-9
    p_c = clamp.(probs, ε, 1-ε)
    brier   = mean((p_c .- Float64.(y)).^2)
    log_loss = -mean(Float64.(y) .* log.(p_c) .+ (1 .- Float64.(y)) .* log.(1 .- p_c))

    CalibrationResult(ece, mce, brier, log_loss, bins_df)
end

"""
    reliability_diagram(probs, y; n_bins) -> DataFrame

Data for a reliability diagram: bin confidence vs observed frequency.
A well-calibrated model has points on the diagonal.
"""
function reliability_diagram(
    probs :: AbstractVector,
    y     :: AbstractVector;
    n_bins :: Int = 10,
)
    cr = calibration_error(probs, y; n_bins=n_bins)
    cr.bins
end

function Base.show(io::IO, r::CalibrationResult)
    println(io, "CalibrationResult")
    println(io, "  ECE:       $(round(r.ece;digits=4))")
    println(io, "  MCE:       $(round(r.mce;digits=4))")
    println(io, "  Brier:     $(round(r.brier;digits=4))")
    println(io, "  Log-loss:  $(round(r.log_loss;digits=4))")
end
