# report.jl — NetworkHealth report aggregation

using Statistics

"""
    NetworkReport

Comprehensive network and epidemic analysis report.
"""
struct NetworkReport
    model_name     ::String
    n_facilities   ::Int
    graph_density  ::Float64
    mean_degree    ::Float64
    mean_pagerank  ::Float64
    top_hubs       ::Vector{String}
    epidemic_r0    ::Float64
    epidemic_type  ::Symbol
    peak_prevalence::Float64
    herd_threshold ::Float64
    outbreak_risk  ::Bool
    timestamp      ::String
end

"""
    network_report(g, epidemic_result; model_name) -> NetworkReport

Aggregate graph topology and epidemic simulation results.
"""
function network_report(g::HealthGraph, epi_result;
                         model_name::String="HealthNetwork")
    n   = g.n
    deg = degree_centrality(g; mode=:total) .* (n - 1)  # unnormalise
    ρ   = 2.0 * sum(length(g.adj[i]) for i in 1:n) / max(n * (n-1), 1)
    pr  = pagerank(g)

    # Top 3 hubs by PageRank
    top_idx = partialsortperm(pr, 1:min(3, n); rev=true)
    top_hubs = g.labels[top_idx]

    # Extract R₀ from epidemic result
    R0   = hasproperty(epi_result, :R0) ? epi_result.R0 : NaN
    peak = if hasproperty(epi_result, :peak_I); epi_result.peak_I
           elseif hasproperty(epi_result, :I_mean); maximum(epi_result.I_mean)
           else NaN; end
    herd = hasproperty(epi_result, :herd_threshold) ? epi_result.herd_threshold :
           (R0 > 1 ? 1.0 - 1.0/R0 : 0.0)
    etype= hasproperty(epi_result, :E) ? :SEIR : :SIR

    NetworkReport(model_name, n, ρ, mean(deg), mean(pr), top_hubs,
                  R0, etype, peak, herd, R0 > 1.0, "2026-01-01")
end

"""
    print_network_report(r)
"""
function print_network_report(r::NetworkReport)
    println("=" ^ 60)
    println("  Network Health Report: $(r.model_name)")
    println("=" ^ 60)
    println("  Facilities: $(r.n_facilities)")
    println("  Graph density:  $(round(r.graph_density, digits=3))")
    println("  Mean degree:    $(round(r.mean_degree, digits=2))")
    println("  Top hubs (PR):  $(join(r.top_hubs, ", "))")
    println()
    println("  Epidemic model: $(r.epidemic_type)")
    println("  R₀ = $(round(r.epidemic_r0, digits=3))")
    println("  Peak prevalence: $(round(100*r.peak_prevalence, digits=2))%")
    println("  Herd immunity threshold: $(round(100*r.herd_threshold, digits=1))%")
    println("  Outbreak risk: $(r.outbreak_risk ? \"YES\" : \"NO\")")
    println("=" ^ 60)
end
