# report.jl — PointPatterns report

using Statistics

"""
    PointPatternReport
"""
struct PointPatternReport
    pattern_name ::String
    n_points     ::Int
    area         ::Float64
    intensity    ::Float64
    bandwidth    ::Float64
    k_p_value    ::Float64   # K-function CSR test
    g_p_value    ::Float64
    n_clusters   ::Int
    n_noise      ::Int
    scan_llr     ::Float64
    scan_p_value ::Float64
    timestamp    ::String
end

"""
    point_pattern_report(pts, area; pattern_name, n_sim, ε, min_pts, rng) -> PointPatternReport
"""
function point_pattern_report(pts::AbstractMatrix, area::Real;
                               pattern_name::String="PointPattern",
                               n_sim::Int=99,
                               ε::Float64=0.0,
                               min_pts::Int=3,
                               rng::AbstractRNG=Random.GLOBAL_RNG)
    n = size(pts, 1)
    λ = n / Float64(area)
    h = silverman_bandwidth(pts)

    # K function
    kr = ripley_k(pts, area; n_sim=n_sim, rng=rng)

    # G function
    gf = nnd_distribution(pts, area; n_sim=n_sim, rng=rng)

    # DBSCAN
    ε_use = ε > 0 ? ε : h * 0.5
    db    = dbscan(pts; ε=ε_use, min_pts=min_pts)

    PointPatternReport(pattern_name, n, Float64(area), λ, h,
                       kr.p_value, gf.p_value,
                       db.n_clusters, db.n_noise,
                       0.0, 1.0,  # scan not run by default
                       "2026-01-01")
end

function print_point_pattern_report(r::PointPatternReport)
    println("=" ^ 58)
    println("  Point Pattern Report: $(r.pattern_name)")
    println("=" ^ 58)
    println("  N events: $(r.n_points)  Area: $(round(r.area,digits=2))")
    println("  Intensity λ: $(round(r.intensity,digits=4))")
    println("  KDE bandwidth: $(round(r.bandwidth,digits=4))")
    println()
    println("  CSR tests:")
    println("    K-function p: $(round(r.k_p_value,digits=3))")
    println("    G-function p: $(round(r.g_p_value,digits=3))")
    println("  DBSCAN: $(r.n_clusters) clusters, $(r.n_noise) noise points")
    println("=" ^ 58)
end
