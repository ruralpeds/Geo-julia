# report.jl — DiseaseMapping report

using Statistics

"""
    DiseaseMappingReport
"""
struct DiseaseMappingReport
    disease_name   ::String
    n_areas        ::Int
    total_observed ::Float64
    total_expected ::Float64
    overall_smr    ::Float64
    n_elevated     ::Int       # areas with SMR > 1 and p < 0.05
    max_smr        ::Float64
    min_smr        ::Float64
    eb_alpha       ::Float64
    eb_beta        ::Float64
    bym_dic        ::Float64
    n_scan_clusters::Int
    timestamp      ::String
end

"""
    disease_mapping_report(O, E, coords; disease_name, run_bym, run_scan, rng) -> DiseaseMappingReport
"""
function disease_mapping_report(O::AbstractVector, E::AbstractVector;
                                 coords::Union{AbstractMatrix,Nothing}=nothing,
                                 disease_name::String="DiseaseName",
                                 run_bym::Bool=false,
                                 run_scan::Bool=false,
                                 n_bym_iter::Int=500,
                                 n_sim::Int=49,
                                 rng::AbstractRNG=Random.GLOBAL_RNG)
    smr_res = batch_smr(O, E)
    smr_vals = [r.smr for r in smr_res]
    n_elev   = sum(r.significant && r.smr > 1 for r in smr_res)

    eb = eb_smooth(O, E)

    bym_dic = NaN
    if run_bym && !isnothing(coords)
        W, Q, _ = build_adjacency(coords)
        bym = bym_fit(O, E, W, Q; n_iter=n_bym_iter, rng=rng)
        bym_dic = bym.dic
    end

    n_clusters = 0
    if run_scan && !isnothing(coords)
        sc = spatial_scan(O, E, coords; n_sim=n_sim, rng=rng)
        n_clusters = sum(s.significant for s in sc)
    end

    DiseaseMappingReport(disease_name, length(O),
                         Float64(sum(O)), Float64(sum(E)),
                         sum(O) / max(sum(E), 1e-10),
                         n_elev, maximum(smr_vals), minimum(smr_vals),
                         eb.α_hat, eb.β_hat, bym_dic, n_clusters,
                         "2026-01-01")
end

function print_disease_mapping_report(r::DiseaseMappingReport)
    println("=" ^ 60)
    println("  Disease Mapping Report: $(r.disease_name)")
    println("=" ^ 60)
    println("  Areas: $(r.n_areas)")
    println("  Observed: $(round(r.total_observed,digits=0))  Expected: $(round(r.total_expected,digits=1))")
    println("  Overall SMR: $(round(r.overall_smr,digits=3))")
    println("  Areas with elevated SMR (p<0.05): $(r.n_elevated)")
    println("  SMR range: [$(round(r.min_smr,digits=3)), $(round(r.max_smr,digits=3))]")
    println("  EB Gamma: α=$(round(r.eb_alpha,digits=3)), β=$(round(r.eb_beta,digits=3))")
    if !isnan(r.bym_dic)
        println("  BYM DIC: $(round(r.bym_dic,digits=1))")
    end
    if r.n_scan_clusters > 0
        println("  Significant scan clusters: $(r.n_scan_clusters)")
    end
    println("=" ^ 60)
end
