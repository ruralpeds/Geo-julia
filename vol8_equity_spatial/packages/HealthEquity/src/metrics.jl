# metrics.jl — Fairness and inequality metrics for HealthEquity
# Chapter 48 — Open-Source Healthcare GIS Textbook in Julia

# ── Binary classification fairness metrics ────────────────────────────────────

"""
    confusion_by_group(ŷ, y, groups) -> Dict

Compute confusion matrix components (TP, FP, TN, FN) per group.
"""
function confusion_by_group(ŷ::AbstractVector{<:Integer},
                             y::AbstractVector{<:Integer},
                             groups::AbstractVector)
    unique_groups = unique(groups)
    result = Dict{eltype(groups), NamedTuple}()
    for g in unique_groups
        mask = groups .== g
        ŷ_g = ŷ[mask]; y_g = y[mask]
        tp = sum((ŷ_g .== 1) .& (y_g .== 1))
        fp = sum((ŷ_g .== 1) .& (y_g .== 0))
        tn = sum((ŷ_g .== 0) .& (y_g .== 0))
        fn = sum((ŷ_g .== 0) .& (y_g .== 1))
        n  = length(y_g)
        result[g] = (tp=tp, fp=fp, tn=tn, fn=fn, n=n,
                     tpr = tp / max(tp+fn, 1),
                     fpr = fp / max(fp+tn, 1),
                     ppv = tp / max(tp+fp, 1),
                     acc = (tp+tn) / max(n, 1),
                     pos_rate = mean(ŷ_g),
                     base_rate = mean(y_g))
    end
    result
end

"""
    demographic_parity(ŷ, groups) -> DataFrame

Demographic parity: |P(Ŷ=1|A=a) - P(Ŷ=1|A=b)| for all group pairs.
Also known as statistical parity or equal selection rates.
"""
function demographic_parity(ŷ::AbstractVector, groups::AbstractVector)
    ug = sort(unique(groups))
    rates = Dict(g => mean(ŷ[groups .== g]) for g in ug)

    rows = []
    for i in eachindex(ug), j in (i+1):length(ug)
        ga, gb = ug[i], ug[j]
        diff = abs(rates[ga] - rates[gb])
        push!(rows, (group_a=string(ga), group_b=string(gb),
                     rate_a=rates[ga], rate_b=rates[gb],
                     dp_diff=diff,
                     dp_ratio=rates[ga] / max(rates[gb], 1e-9),
                     fair_dp=(diff <= 0.05)))
    end
    isempty(rows) ? DataFrame() : DataFrame(rows)
end

"""
    equalized_odds(ŷ, y, groups) -> DataFrame

Equalized odds: equal TPR and FPR across groups (Hardt et al. 2016).
Returns per-group metrics and pairwise differences.
"""
function equalized_odds(ŷ::AbstractVector{<:Integer},
                         y::AbstractVector{<:Integer},
                         groups::AbstractVector)
    cm = confusion_by_group(ŷ, y, groups)
    ug = sort(collect(keys(cm)))

    rows = []
    for g in ug
        c = cm[g]
        push!(rows, (group=string(g), n=c.n,
                     tpr=c.tpr, fpr=c.fpr, ppv=c.ppv, acc=c.acc,
                     base_rate=c.base_rate, pos_rate=c.pos_rate))
    end
    df = DataFrame(rows)

    # Pairwise equalized-odds gap
    if nrow(df) >= 2
        tpr_max = maximum(df.tpr); tpr_min = minimum(df.tpr)
        fpr_max = maximum(df.fpr); fpr_min = minimum(df.fpr)
        df[!, :eo_gap_tpr] .= tpr_max - tpr_min
        df[!, :eo_gap_fpr] .= fpr_max - fpr_min
        df[!, :fair_eo]    .= (tpr_max - tpr_min <= 0.05) && (fpr_max - fpr_min <= 0.05)
    end
    df
end

"""
    calibration_gap(probs, y, groups; n_bins) -> DataFrame

Calibration gap: |P(Y=1|p̂, A=a) - P(Y=1|p̂, A=b)| across probability bins.
Detects differential calibration (model under/over-confident for subgroups).
"""
function calibration_gap(probs::AbstractVector{<:AbstractFloat},
                          y::AbstractVector{<:Integer},
                          groups::AbstractVector;
                          n_bins::Int=10)
    ug = sort(unique(groups))
    bins = range(0, 1; length=n_bins+1)
    rows = []

    for b in 1:n_bins
        lo, hi = bins[b], bins[b+1]
        bin_mid = (lo + hi) / 2
        group_freqs = Dict{eltype(groups), Float64}()
        group_counts = Dict{eltype(groups), Int}()

        for g in ug
            mask = (groups .== g) .& (probs .>= lo) .& (probs .< hi)
            n_bin = sum(mask)
            group_counts[g] = n_bin
            group_freqs[g]  = n_bin > 0 ? mean(y[mask]) : NaN
        end

        if length(ug) >= 2
            g1, g2 = ug[1], ug[2]
            f1, f2 = group_freqs[g1], group_freqs[g2]
            gap = (isnan(f1) || isnan(f2)) ? NaN : abs(f1 - f2)
            push!(rows, (bin=b, bin_mid=bin_mid,
                         freq_g1=f1, freq_g2=f2,
                         n_g1=group_counts[g1], n_g2=group_counts[g2],
                         cal_gap=gap))
        end
    end
    isempty(rows) ? DataFrame() : DataFrame(rows)
end

# ── Inequality indices ────────────────────────────────────────────────────────

"""
    gini_coefficient(x) -> Float64

Gini coefficient: G = (2 Σ i·x_i) / (n Σ x_i) - (n+1)/n
Measures income/access inequality; 0 = perfect equality, 1 = maximal inequality.
"""
function gini_coefficient(x::AbstractVector{<:Real})
    n = length(x)
    n == 0 && return 0.0
    x_sorted = sort(x)
    μ = mean(x_sorted)
    abs(μ) < 1e-12 && return 0.0
    ranks = 1:n
    2 * sum(ranks .* x_sorted) / (n * sum(x_sorted)) - (n+1)/n
end

"""
    theil_index(x) -> Float64

Theil T index: T = (1/n) Σ (x_i/μ) log(x_i/μ)
0 = perfect equality. Decomposable into between/within group components.
"""
function theil_index(x::AbstractVector{<:Real})
    n = length(x)
    μ = mean(x)
    abs(μ) < 1e-12 && return 0.0
    ratios = x ./ μ
    mean(r > 0 ? r * log(r) : 0.0 for r in ratios)
end

"""
    concentration_index(y, rank_var) -> Float64

Concentration index (Wagstaff 1989): measures socioeconomic inequality.
C = (2/μ) Cov(y, r) where r = fractional rank in socioeconomic distribution.
C ∈ [-1, 1]: negative = concentrated in poor; positive = concentrated in rich.
"""
function concentration_index(y::AbstractVector{<:Real},
                               rank_var::AbstractVector{<:Real})
    n = length(y)
    μ = mean(y)
    abs(μ) < 1e-12 && return 0.0
    # Fractional rank
    r = (sortperm(sortperm(rank_var)) .- 0.5) ./ n
    2 * cov(y, r) / μ
end

"""
    dissimilarity_index(group_a, group_b, areas) -> Float64

Duncan dissimilarity index (1955): D = ½ Σ |a_i/A - b_i/B|
0 = full integration; 1 = complete segregation.
Fraction of group A (or B) that would need to move to achieve equal distribution.
"""
function dissimilarity_index(a::AbstractVector{<:Real},
                              b::AbstractVector{<:Real})
    A = sum(a); B = sum(b)
    (A < 1e-12 || B < 1e-12) && return 0.0
    0.5 * sum(abs.(a./A .- b./B))
end

"""
    isolation_exposure(a, b) -> NamedTuple{isolation, exposure}

Bell (1954) isolation and exposure indices:
- Isolation:  P = Σ (a_i/A) · (a_i/n_i)
- Exposure:   Q = Σ (a_i/A) · (b_i/n_i)  (cross-group exposure)
"""
function isolation_exposure(a::AbstractVector{<:Real},
                              b::AbstractVector{<:Real})
    n_i = a .+ b
    A = sum(a)
    A < 1e-12 && return (isolation=0.0, exposure=0.0)
    mask = n_i .> 0
    iso = sum((a[mask] ./ A) .* (a[mask] ./ n_i[mask]))
    exp_val = sum((a[mask] ./ A) .* (b[mask] ./ n_i[mask]))
    (isolation=iso, exposure=exp_val)
end

# ── Composite fairness audit ──────────────────────────────────────────────────

"""
    FairnessAudit

Summary of all fairness metrics for a model-group combination.
"""
struct FairnessAudit
    dp_table      :: DataFrame
    eo_table      :: DataFrame
    cal_gap_table :: DataFrame
    gini          :: Float64
    theil         :: Float64
    conc_index    :: Union{Float64, Nothing}
    overall_fair  :: Bool
    violations    :: Vector{String}
end

"""
    fairness_audit(ŷ_probs, ŷ, y, groups; ses_var, n_bins) -> FairnessAudit

Run all fairness metrics in one call.
"""
function fairness_audit(
    ŷ_probs :: AbstractVector{<:AbstractFloat},
    ŷ       :: AbstractVector{<:Integer},
    y       :: AbstractVector{<:Integer},
    groups  :: AbstractVector;
    ses_var :: Union{AbstractVector, Nothing} = nothing,
    n_bins  :: Int = 10,
)
    dp  = demographic_parity(ŷ, groups)
    eo  = equalized_odds(ŷ, y, groups)
    cg  = calibration_gap(ŷ_probs, y, groups; n_bins=n_bins)
    g   = gini_coefficient(ŷ_probs)
    th  = theil_index(ŷ_probs)
    ci  = isnothing(ses_var) ? nothing : concentration_index(ŷ_probs, ses_var)

    violations = String[]
    if !isempty(dp) && any(dp.dp_diff .> 0.05)
        push!(violations, "Demographic parity violated (max diff=$(round(maximum(dp.dp_diff);digits=3)))")
    end
    if !isempty(eo) && hasproperty(eo, :eo_gap_tpr)
        eo_gap = maximum(eo.eo_gap_tpr)
        eo_gap > 0.05 && push!(violations, "Equalized odds TPR gap=$(round(eo_gap;digits=3))")
    end
    if !isnothing(ci) && abs(ci) > 0.2
        push!(violations, "Concentration index=$(round(ci;digits=3)) — unequal SES distribution")
    end

    FairnessAudit(dp, eo, cg, g, th, ci, isempty(violations), violations)
end

function Base.show(io::IO, fa::FairnessAudit)
    status = fa.overall_fair ? "PASS" : "FAIL"
    println(io, "FairnessAudit [$status]")
    println(io, "  Gini:  $(round(fa.gini; digits=3))")
    println(io, "  Theil: $(round(fa.theil; digits=3))")
    isnothing(fa.conc_index) || println(io, "  Conc.Index: $(round(fa.conc_index;digits=3))")
    if !fa.overall_fair
        println(io, "  Violations:")
        for v in fa.violations
            println(io, "    • $v")
        end
    end
end
