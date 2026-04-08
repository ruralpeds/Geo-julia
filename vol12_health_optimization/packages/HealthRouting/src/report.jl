# report.jl — Routing summary report

struct RoutingReport
    study_name::String
    n_stops::Int
    tsp_nn_dist::Float64
    tsp_2opt_dist::Float64
    tsp_improvement_pct::Float64
    vrp_routes::Int
    vrp_total_dist::Float64
    mexclp_coverage::Float64
    erlang_c_pw::Float64
    erlang_c_min_servers::Int
    timestamp::String
end

function routing_report(pts, depot;
                         study_name="Routing Study",
                         demands=ones(size(pts,1)),
                         capacity=Inf,
                         coverage_radius=5.0,
                         λ=2.0, μ=1.0, c_init=3,
                         rng=Random.default_rng())
    nn   = tsp_nn(pts; rng=rng)
    to   = tsp_two_opt(pts; init_tour=nn.tour, rng=rng)
    vr   = vrp_cw(pts, depot; demands=demands, capacity=capacity)
    em   = mexclp(pts, pts, min(3, size(pts,1)); coverage_radius=coverage_radius, rng=rng)
    ec   = erlang_c(λ, μ, c_init)
    imp  = (nn.distance - to.distance) / max(nn.distance, 1e-10) * 100

    RoutingReport(study_name, size(pts,1), nn.distance, to.distance, imp,
                  vr.n_vehicles, vr.total_distance, em.total_expected_coverage,
                  ec.p_wait, ec.min_servers, "$(time_ns())")
end

function print_routing_report(r::RoutingReport)
    println("=" ^ 58)
    println("  Routing Report: $(r.study_name)  ($(r.n_stops) stops)")
    println("-" ^ 58)
    println("  TSP NN distance:  $(round(r.tsp_nn_dist,digits=2))")
    println("  TSP 2-opt:        $(round(r.tsp_2opt_dist,digits=2))  ($(round(r.tsp_improvement_pct,digits=1))% improvement)")
    println("  VRP routes:       $(r.vrp_routes)  total dist=$(round(r.vrp_total_dist,digits=2))")
    println("  MEXCLP coverage:  $(round(r.mexclp_coverage*100,digits=1))%")
    println("  Erlang-C P(wait): $(round(r.erlang_c_pw,digits=3))  min servers=$(r.erlang_c_min_servers)")
end
