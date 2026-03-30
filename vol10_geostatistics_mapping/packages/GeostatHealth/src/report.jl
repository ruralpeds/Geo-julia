# report.jl — GeostatHealth report

using Statistics

"""
    GeostatReport

Geostatistical analysis report.
"""
struct GeostatReport
    series_name   ::String
    n_data        ::Int
    variogram_model::VariogramModel
    nugget_ratio  ::Float64
    loo_rmse      ::Float64
    loo_picp_95   ::Float64
    n_sims        ::Int
    timestamp     ::String
end

"""
    geostat_report(z, coords; vm, series_name, n_sims, rng) -> GeostatReport
"""
function geostat_report(z::AbstractVector, coords::AbstractMatrix;
                         vm::Union{VariogramModel,Nothing}=nothing,
                         series_name::String="HealthSurface",
                         n_sims::Int=3,
                         rng::AbstractRNG=Random.GLOBAL_RNG)
    if isnothing(vm)
        ev = empirical_variogram(coords, z; n_lags=10)
        vm = fit_variogram(ev; model=:spherical)
    end

    loo = kriging_loo_cv(z, coords, vm; method=:ordinary)

    GeostatReport(series_name, length(z), vm,
                  vm.nugget / max(vm.sill, 1e-10),
                  loo.rmse, loo.picp_95, n_sims, "2026-01-01")
end

function print_geostat_report(r::GeostatReport)
    println("=" ^ 58)
    println("  Geostatistical Report: $(r.series_name)")
    println("=" ^ 58)
    println("  N data points: $(r.n_data)")
    vm = r.variogram_model
    println("  Variogram model: $(vm.model)")
    println("    nugget=$(round(vm.nugget,digits=4))  sill=$(round(vm.sill,digits=4))" *
            "  range=$(round(vm.range,digits=4))")
    println("    nugget/sill=$(round(100*r.nugget_ratio,digits=1))%")
    println("  LOO CV RMSE:      $(round(r.loo_rmse,    digits=4))")
    println("  LOO 95% PI cov.:  $(round(100*r.loo_picp_95,digits=1))%")
    println("=" ^ 58)
end
