# report.jl — Facility location summary report

struct FacilityReport
    study_name::String
    n_demand::Int
    n_candidates::Int
    p::Int
    pmedian_obj::Float64
    pmedian_facilities::Vector{Int}
    mclp_coverage::Float64
    mclp_facilities::Vector{Int}
    setcover_n::Int
    setcover_coverage::Float64
    capflp_obj::Float64
    capflp_feasible::Bool
    timestamp::String
end

function facility_report(demand_pts, cand_pts;
                         study_name="Facility Study",
                         p=3, coverage_radius=2.0,
                         weights=ones(size(demand_pts,1)),
                         capacities=fill(Inf, size(cand_pts,1)),
                         rng=Random.default_rng())
    pm  = p_median(demand_pts, cand_pts, p; weights=weights, rng=rng)
    mc  = mclp(demand_pts, cand_pts, p; coverage_radius=coverage_radius, weights=weights, rng=rng)
    sc  = set_cover(demand_pts, cand_pts; coverage_radius=coverage_radius, weights=weights)
    cap = cap_flp(demand_pts, cand_pts, p; weights=weights, capacities=capacities, rng=rng)
    FacilityReport(study_name, size(demand_pts,1), size(cand_pts,1), p,
                   pm.objective, pm.open_facilities,
                   mc.coverage_fraction, mc.open_facilities,
                   sc.n_facilities, sc.coverage_fraction,
                   cap.objective, cap.feasible, "$(time_ns())")
end

function print_facility_report(r::FacilityReport)
    println("=" ^ 58)
    println("  Facility Location: $(r.study_name)")
    println("  $(r.n_demand) demand pts  $(r.n_candidates) candidates  p=$(r.p)")
    println("-" ^ 58)
    println("  p-Median:     obj=$(round(r.pmedian_obj,digits=2))  sites=$(r.pmedian_facilities)")
    println("  MCLP:         coverage=$(round(r.mclp_coverage*100,digits=1))%  sites=$(r.mclp_facilities)")
    println("  Set cover:    $(r.setcover_n) facilities  coverage=$(round(r.setcover_coverage*100,digits=1))%")
    println("  Cap FLP:      obj=$(round(r.capflp_obj,digits=2))  feasible=$(r.capflp_feasible)")
    println("=" ^ 58)
end
