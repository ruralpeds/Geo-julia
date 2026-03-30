# report.jl — Equity reporting utilities for HealthEquity
# Chapter 48 — Open-Source Healthcare GIS Textbook in Julia

"""
    EquityReport

Comprehensive equity analysis report combining fairness metrics, inequality
indices, disparity decomposition, and mitigation recommendations.
"""
struct EquityReport
    model_name         :: String
    group_var          :: String
    n_groups           :: Int
    n_total            :: Int
    audit              :: FairnessAudit
    oaxaca             :: Union{OaxacaResult, Nothing}
    theil_decomp       :: Union{TheilDecomposition, Nothing}
    sii                :: Union{NamedTuple, Nothing}
    threshold_sweep_df :: Union{DataFrame, Nothing}
    recommendations    :: Vector{String}
    timestamp          :: String
end

"""
    equity_report(probs, y, groups, X; kwargs...) -> EquityReport

Generate a full equity report for a healthcare prediction model.
"""
function equity_report(
    probs     :: AbstractVector{<:AbstractFloat},
    y         :: AbstractVector{<:Integer},
    groups    :: AbstractVector;
    model_name :: String     = "Healthcare Model",
    group_var  :: String     = "group",
    X_features :: Union{AbstractMatrix, Nothing} = nothing,
    feature_names :: Vector{String} = String[],
    ses_var    :: Union{AbstractVector, Nothing} = nothing,
    include_sweep :: Bool = true,
    n_bins     :: Int  = 10,
)
    ŷ = Int.(probs .>= 0.5)
    audit = fairness_audit(probs, ŷ, y, groups; ses_var=ses_var, n_bins=n_bins)

    # Oaxaca-Blinder (if features provided and binary group)
    ob = nothing
    ug = unique(groups)
    if !isnothing(X_features) && length(ug) == 2
        g1, g2 = ug[1], ug[2]
        ob = oaxaca_blinder(
            X_features[groups .== g1, :], y[groups .== g1],
            X_features[groups .== g2, :], y[groups .== g2];
            feature_names=feature_names
        )
    end

    # Theil decomposition on predicted probabilities
    td = theil_decompose(probs, groups)

    # SII on predicted scores vs SES
    sii_val = isnothing(ses_var) ? nothing : slope_index_inequality(probs, ses_var)

    # Threshold sweep
    ts_df = include_sweep ? threshold_sweep(probs, y, groups) : nothing

    # Build recommendations
    recs = String[]
    !audit.overall_fair && push!(recs, "Model fails fairness checks — review before deployment")
    any(audit.violations .== r"Demographic parity") &&
        push!(recs, "Consider threshold optimisation (equalise_tpr/equalise_fpr) to reduce DP gap")
    if !isnothing(ob) && abs(ob.unexplained / max(abs(ob.total_gap), 1e-9)) > 0.5
        push!(recs, "Majority of outcome gap is unexplained — consider feature parity review")
    end
    if audit.gini > 0.4
        push!(recs, "High Gini index ($(round(audit.gini;digits=2))): predicted scores are unequal")
    end
    if !isnothing(sii_val) && abs(sii_val.rii) > 0.3
        push!(recs, "SES gradient in predictions (RII=$(round(sii_val.rii;digits=2))) — check for proxy discrimination")
    end

    ts = string(Dates.now())
    EquityReport(model_name, group_var, length(ug), length(y),
                 audit, ob, td, sii_val, ts_df, recs, ts)
end

function Base.show(io::IO, r::EquityReport)
    status = r.audit.overall_fair ? "PASS" : "FAIL"
    println(io, "┌─ EquityReport: $(r.model_name) [$status]")
    println(io, "│  Group variable: $(r.group_var) ($(r.n_groups) groups, n=$(r.n_total))")
    println(io, "│  Gini:           $(round(r.audit.gini; digits=3))")
    println(io, "│  Theil T:        $(round(r.audit.theil; digits=3))")
    if !isnothing(r.theil_decomp)
        pct_B = abs(r.theil_decomp.total) > 1e-12 ?
                round(100*r.theil_decomp.between/r.theil_decomp.total;digits=1) : 0.0
        println(io, "│  Between-group:  $pct_B% of Theil")
    end
    if !isnothing(r.audit.conc_index)
        println(io, "│  Conc. Index:    $(round(r.audit.conc_index; digits=3))")
    end
    if !isnothing(r.oaxaca)
        println(io, "│  Oaxaca gap:     $(round(r.oaxaca.total_gap;digits=4)) " *
                    "($(round(r.oaxaca.pct_explained;digits=1))% explained)")
    end
    if !isempty(r.audit.violations)
        println(io, "│  Violations:")
        for v in r.audit.violations
            println(io, "│    ✗ $v")
        end
    end
    if !isempty(r.recommendations)
        println(io, "│  Recommendations:")
        for rec in r.recommendations
            println(io, "│    → $rec")
        end
    end
    print(io, "└─ $(r.timestamp)")
end
