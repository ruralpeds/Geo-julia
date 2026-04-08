# facility_network.jl — Healthcare facility network analysis
# Patient flow matrices, catchment area analysis, referral centrality

using Statistics, LinearAlgebra

# ── Patient flow analysis ─────────────────────────────────────────────────────

"""
    PatientFlowResult

Analysis of patient flows between facilities.
"""
struct PatientFlowResult
    n_facilities     ::Int
    facility_names   ::Vector{String}
    flow_matrix      ::Matrix{Float64}   # F[i,j] = patients from i to j
    referral_rate    ::Matrix{Float64}   # F[i,j] / row_sum (conditional)
    outflow          ::Vector{Float64}
    inflow           ::Vector{Float64}
    net_flow         ::Vector{Float64}
    self_sufficiency ::Vector{Float64}   # diagonal / row sum
    referral_graph   ::HealthGraph
end

"""
    patient_flow_analysis(F; facility_names) -> PatientFlowResult

Analyse a patient flow matrix F (n×n) where F[i,j] = patients
transferred from facility i to facility j (diagonal = treated locally).
"""
function patient_flow_analysis(F::AbstractMatrix;
                                facility_names::Vector{String}=["F$i" for i in 1:size(F,1)])
    n = size(F, 1)
    @assert size(F, 2) == n

    row_sums = vec(sum(F, dims=2))
    col_sums = vec(sum(F, dims=1))

    # Referral rate (row-normalised, off-diagonal only)
    R = zeros(n, n)
    for i in 1:n
        total_out = sum(F[i, j] for j in 1:n if j != i; init=0.0)
        total_out == 0 && continue
        for j in 1:n
            j != i && (R[i,j] = F[i,j] / total_out)
        end
    end

    outflow  = vec(sum(F[:, j] for j in 1:n if true; init=zeros(n)))
    outflow  = [sum(F[i,j] for j in 1:n if j != i; init=0.0) for i in 1:n]
    inflow   = [sum(F[j,i] for j in 1:n if j != i; init=0.0) for i in 1:n]
    net_flow = inflow .- outflow
    selfsufc = [row_sums[i] > 0 ? F[i,i] / row_sums[i] : 0.0 for i in 1:n]

    # Build referral graph (excluding self-loops)
    W_graph = copy(F)
    for i in 1:n; W_graph[i,i] = 0.0; end
    g = build_graph(W_graph; labels=facility_names, node_type=fill("facility", n))

    PatientFlowResult(n, facility_names, Matrix{Float64}(F), R, outflow, inflow,
                      net_flow, selfsufc, g)
end

# ── Catchment area ────────────────────────────────────────────────────────────

"""
    CatchmentResult

Gravity-model catchment area for a set of facilities.
"""
struct CatchmentResult
    facility_names  ::Vector{String}
    population_zones::Vector{String}
    gravity_weights ::Matrix{Float64}   # n_zones × n_facilities
    assignment      ::Vector{Int}       # zone → nearest facility (by gravity)
    catchment_pop   ::Vector{Float64}
    utilisation_rate::Vector{Float64}
end

"""
    catchment_area(pop, capacity, distance; α=1.0, β=2.0,
                   facility_names, zone_names) -> CatchmentResult

Enhanced two-step floating catchment area (E2SFCA) method.

Gravity weight W_ij = pop_i / distance_ij^β for facility j with capacity_j.
Step 1: R_j = capacity_j / Σ_i W_ij  (supply-to-demand ratio)
Step 2: A_i = Σ_j W_ij * R_j         (accessibility score)
"""
function catchment_area(pop::AbstractVector, capacity::AbstractVector,
                         distance::AbstractMatrix;
                         α::Float64=1.0, β::Float64=2.0,
                         facility_names::Vector{String}=["F$j" for j in 1:size(distance,2)],
                         zone_names::Vector{String}=["Z$i" for i in 1:length(pop)])
    n_zones = length(pop)
    n_fac   = length(capacity)
    @assert size(distance) == (n_zones, n_fac)

    # Gravity weights: W_ij = pop_i / d_ij^β  (0 if d=0)
    W = zeros(n_zones, n_fac)
    for i in 1:n_zones, j in 1:n_fac
        d = distance[i, j]
        W[i, j] = d > 0 ? pop[i] / d^β : pop[i]
    end

    # Step 1: supply-demand ratio for each facility
    R = [capacity[j] / max(sum(W[:, j]), 1e-8) for j in 1:n_fac]

    # Step 2: accessibility score for each zone
    A = vec(W * R)

    # Assignment: each zone assigned to highest-gravity facility
    assignment = [argmax(W[i, :]) for i in 1:n_zones]

    # Catchment population per facility
    catch_pop = zeros(n_fac)
    for i in 1:n_zones; catch_pop[assignment[i]] += pop[i]; end

    util_rate = [capacity[j] > 0 ? catch_pop[j] / capacity[j] : 0.0 for j in 1:n_fac]

    CatchmentResult(facility_names, zone_names, W, assignment, catch_pop, util_rate)
end

# ── Referral centrality ───────────────────────────────────────────────────────

"""
    referral_centrality(flow_result; method=:pagerank) -> NamedTuple

Compute hub/authority scores and PageRank on the referral network.

Returns a NamedTuple with pagerank, betweenness, in_strength, out_strength.
"""
function referral_centrality(flow_result::PatientFlowResult;
                              method::Symbol=:pagerank)
    g   = flow_result.referral_graph
    pr  = pagerank(g)
    bc  = betweenness_centrality(g)
    s_in  = strength_centrality(g; mode=:in)
    s_out = strength_centrality(g; mode=:out)
    (pagerank=pr, betweenness=bc, in_strength=s_in, out_strength=s_out,
     facility=flow_result.facility_names)
end

# ── Network vulnerability ─────────────────────────────────────────────────────

"""
    network_vulnerability(g; n_removals=3) -> DataFrame

Simulate targeted node removal (highest-degree first) and track
largest-component size — a measure of network resilience.
"""
function network_vulnerability(g::HealthGraph; n_removals::Int=3)
    n       = g.n
    results = NamedTuple{(:step, :removed_node, :largest_component), Tuple{Int,String,Int}}[]

    active = Set(1:n)
    for step in 1:min(n_removals, n)
        # Find highest-degree active node
        deg  = [length(g.adj[i]) for i in 1:n]
        best = 0; best_d = -1
        for i in active
            if deg[i] > best_d
                best_d = deg[i]; best = i
            end
        end
        delete!(active, best)

        # Build subgraph on active nodes
        W_sub = zeros(n, n)
        for i in active, (j, w) in g.adj[i]
            j in active && (W_sub[i,j] = w)
        end
        g_sub  = build_graph(W_sub)
        comps  = weakly_connected_components(g_sub)
        # Filter components to active nodes only
        active_comps = [filter(v -> v in active, c) for c in comps]
        lc = isempty(active_comps) ? 0 : maximum(length, active_comps)

        push!(results, (step=step, removed_node=g.labels[best], largest_component=lc))
    end
    results
end
