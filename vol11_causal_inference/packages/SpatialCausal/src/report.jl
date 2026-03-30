# report.jl — Spatial causal inference report

struct SpatialCausalReport
    study_name::String
    n_obs::Int
    n_units::Int
    direct_effect::Float64
    direct_se::Float64
    spillover_effect::Float64
    spillover_se::Float64
    conley_se_max::Float64
    ols_se_max::Float64
    se_inflation::Float64       # max(conley_se / ols_se)
    iv_tau::Float64
    iv_se::Float64
    iv_f_stat::Float64
    timestamp::String
end

function spatial_causal_report(;
        study_name::String="Spatial Causal Study",
        spatial_did_result=nothing,
        conley_result=nothing,
        geo_iv_result=nothing)

    de = isnothing(spatial_did_result) ? NaN : spatial_did_result.β_direct
    ds = isnothing(spatial_did_result) ? NaN : spatial_did_result.se_direct
    sp = isnothing(spatial_did_result) ? NaN : spatial_did_result.β_spillover
    ss = isnothing(spatial_did_result) ? NaN : spatial_did_result.se_spillover
    n_obs   = isnothing(spatial_did_result) ? 0 : spatial_did_result.n
    n_units = isnothing(spatial_did_result) ? 0 :
              (spatial_did_result.n_treated + spatial_did_result.n_spillover + spatial_did_result.n_control)

    con_max = isnothing(conley_result) ? NaN : maximum(conley_result.se_conley)
    ols_max = isnothing(conley_result) ? NaN : maximum(conley_result.se_ols)
    se_inf  = (isnan(con_max) || isnan(ols_max)) ? NaN : con_max / max(ols_max, 1e-10)

    iv_τ = isnothing(geo_iv_result) ? NaN : geo_iv_result.β_2sls[2]  # treatment coef
    iv_s = isnothing(geo_iv_result) ? NaN : geo_iv_result.se_2sls[2]
    iv_f = isnothing(geo_iv_result) ? NaN : geo_iv_result.f_stat

    SpatialCausalReport(study_name, n_obs, n_units, de, ds, sp, ss,
                        con_max, ols_max, se_inf, iv_τ, iv_s, iv_f, "$(time_ns())")
end

function print_spatial_causal_report(r::SpatialCausalReport)
    println("=" ^ 60)
    println("  Spatial Causal Inference: $(r.study_name)")
    println("  n=$(r.n_obs) obs  $(r.n_units) spatial units")
    println("-" ^ 60)
    if isfinite(r.direct_effect)
        println("  Spatial DiD:")
        println("    Direct effect:   $(round(r.direct_effect,digits=4)) ± $(round(r.direct_se,digits=4))")
        println("    Spillover:       $(round(r.spillover_effect,digits=4)) ± $(round(r.spillover_se,digits=4))")
    end
    if isfinite(r.conley_se_max)
        println("  Conley SE inflation: $(round(r.se_inflation,digits=3))×")
    end
    if isfinite(r.iv_tau)
        println("  2SLS IV τ: $(round(r.iv_tau,digits=4)) ± $(round(r.iv_se,digits=4))")
        println("  First-stage F: $(round(r.iv_f_stat,digits=2))")
        r.iv_f_stat < 10 && println("  ⚠  Weak instrument (F<10)")
    end
    println("=" ^ 60)
end
