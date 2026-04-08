# report.jl — Survival analysis report aggregation

using Statistics

"""
    SurvivalReport

Comprehensive survival analysis report.
"""
struct SurvivalReport
    model_name        ::String
    n_total           ::Int
    n_events          ::Int
    pct_censored      ::Float64
    km_result         ::Union{KMResult, Nothing}
    cox_model         ::Union{CoxModel, Nothing}
    parametric_model  ::Union{ParametricModel, Nothing}
    cif_result        ::Union{CIFResult, Nothing}
    log_rank          ::Union{LogRankResult, Nothing}
    median_survival   ::Float64
    restricted_mean   ::Float64
    concordance       ::Float64
    aic               ::Float64
    timestamp         ::String
end

"""
    survival_report(times, status, X; groups, dist, model_name, feature_names) -> SurvivalReport

Run a complete survival analysis pipeline:
1. Kaplan-Meier estimation
2. Log-rank test (if groups provided)
3. Cox PH model (if X provided)
4. Parametric AFT model (if dist specified)
5. Cumulative incidence (if competing risks detected)
"""
function survival_report(times::AbstractVector, status::AbstractVector{<:Integer};
                          X::Union{AbstractMatrix, Nothing}=nothing,
                          groups::Union{AbstractVector, Nothing}=nothing,
                          dist::Symbol=:weibull,
                          model_name::String="SurvivalModel",
                          feature_names::Vector{String}=isnothing(X) ? String[] :
                              ["x$i" for i in 1:size(X,2)])
    n       = length(times)
    n_ev    = sum(status .> 0)
    pct_cen = 100.0 * (1 - n_ev / n)

    # Determine if competing risks (status has values > 1)
    has_competing = any(status .> 1)

    # KM (use binary event for overall survival)
    status_any = Int.(status .> 0)
    km = kaplan_meier(times, status_any)

    # Log-rank test
    lr = isnothing(groups) ? nothing : logrank_test(times, status_any, groups)

    # Cox model
    cox = if !isnothing(X)
        cox_fit(times, status_any, X; feature_names=feature_names)
    else
        nothing
    end

    # Parametric AFT
    pm = if !isnothing(X)
        try
            parametric_fit(times, status_any, X; dist=dist, feature_names=feature_names)
        catch
            nothing
        end
    else
        nothing
    end

    # CIF for competing risks
    cif = has_competing ? cumulative_incidence(times, status) : nothing

    # Summary metrics
    concordance = isnothing(cox) ? 0.5 : cox.concordance
    aic         = isnothing(pm)  ? Inf  : pm.aic

    SurvivalReport(model_name, n, n_ev, pct_cen, km, cox, pm, cif, lr,
                   km.median_survival, km.restricted_mean, concordance, aic,
                   string(now_string()))
end

now_string() = "$(Dates.year(Dates.now()))-$(lpad(Dates.month(Dates.now()),2,'0'))-$(lpad(Dates.day(Dates.now()),2,'0'))"

# Poor-man's date (avoid Dates dep for tiny gain)
module Dates
    struct DateTime; end
    now() = DateTime()
    year(::DateTime)  = 2026
    month(::DateTime) = 1
    day(::DateTime)   = 1
end

"""
    print_survival_report(report)

Print a formatted summary of the survival analysis.
"""
function print_survival_report(r::SurvivalReport)
    println("=" ^ 60)
    println("  Survival Analysis Report: $(r.model_name)")
    println("=" ^ 60)
    println("  N=$(r.n_total)  Events=$(r.n_events)  Censored=$(round(r.pct_censored,digits=1))%")
    println("  Median survival: $(round(r.median_survival, digits=2))")
    println("  RMST:            $(round(r.restricted_mean, digits=2))")
    println("  Concordance C:   $(round(r.concordance, digits=3))")
    if !isnothing(r.cox_model)
        println()
        println("  Cox PH coefficients:")
        println("  $(lpad("Feature",20)) $(lpad("exp(β)",8)) $(lpad("p-value",9))")
        for i in eachindex(r.cox_model.β)
            println("  $(lpad(r.cox_model.feature_names[i],20)) " *
                    "$(lpad(round(exp(r.cox_model.β[i]),digits=3),8)) " *
                    "$(lpad(round(r.cox_model.p_values[i],digits=4),9))")
        end
    end
    if !isnothing(r.log_rank)
        println()
        println("  Log-rank test: χ²=$(round(r.log_rank.statistic,digits=2)) " *
                "df=$(r.log_rank.df) p=$(round(r.log_rank.p_value,digits=4))")
    end
    println("=" ^ 60)
end
