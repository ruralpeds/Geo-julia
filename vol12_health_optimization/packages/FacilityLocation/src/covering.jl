# covering.jl — Set covering and Maximal Covering Location Problem (MCLP) via JuMP

struct SetCoverResult
    open_facilities::Vector{Int}
    covered::Vector{Bool}
    n_facilities::Int
    n_covered::Int
    coverage_fraction::Float64
    demand_covered::Float64
    demand_total::Float64
end

struct MCLPResult
    open_facilities::Vector{Int}
    covered::Vector{Bool}
    p::Int
    demand_covered::Float64
    demand_total::Float64
    coverage_fraction::Float64
end

"""
    set_cover(demand_pts, cand_pts; coverage_radius, weights) -> SetCoverResult

Set cover via JuMP IP: find the minimum number of facilities such that every
demand point is within `coverage_radius` of at least one open facility.
"""
function set_cover(demand_pts::AbstractMatrix,
                   cand_pts::AbstractMatrix;
                   coverage_radius::Float64,
                   weights::AbstractVector=ones(size(demand_pts,1)))
    n, m  = size(demand_pts,1), size(cand_pts,1)
    # Coverage matrix A[i,j] = 1 if demand i is within radius of candidate j
    A = [sqrt(sum((demand_pts[i,:] .- cand_pts[j,:]).^2)) <= coverage_radius
         for i in 1:n, j in 1:m]

    # ── JuMP IP formulation ──────────────────────────────────────────────────
    model = Model(HiGHS.Optimizer)
    set_silent(model)

    @variable(model, y[1:m], Bin)  # y[j] = 1 if facility j is open

    # Minimize number of facilities
    @objective(model, Min, sum(y))

    # Every demand point must be covered by at least one open facility
    # (only if it can be covered at all)
    for i in 1:n
        covering_j = findall(A[i,:])
        if !isempty(covering_j)
            @constraint(model, sum(y[j] for j in covering_j) >= 1)
        end
    end

    optimize!(model)

    if termination_status(model) in (OPTIMAL, LOCALLY_SOLVED, FEASIBLE_POINT)
        y_val = value.(y)
        open_set = sort([j for j in 1:m if y_val[j] > 0.5])
    else
        # Fallback: no feasible solution (some demands cannot be covered)
        open_set = Int[]
    end

    covered = [!isempty(open_set) && any(A[i,j] for j in open_set) for i in 1:n]
    w_cov = sum(weights[covered]; init=0.0)
    w_tot = sum(weights)
    SetCoverResult(open_set, covered, length(open_set), sum(covered),
                   sum(covered)/n, w_cov, w_tot)
end

"""
    mclp(demand_pts, cand_pts, p; coverage_radius, weights) -> MCLPResult

Maximal Covering Location Problem (Church & ReVelle 1974) via JuMP IP:
place exactly `p` facilities to maximise total weighted demand covered within
`coverage_radius`.
"""
function mclp(demand_pts::AbstractMatrix,
              cand_pts::AbstractMatrix,
              p::Int;
              coverage_radius::Float64,
              weights::AbstractVector=ones(size(demand_pts,1)),
              n_restarts::Int=5,
              rng=Random.default_rng())
    n, m = size(demand_pts,1), size(cand_pts,1)
    p    = min(p, m)
    A    = [sqrt(sum((demand_pts[i,:] .- cand_pts[j,:]).^2)) <= coverage_radius
            for i in 1:n, j in 1:m]

    # ── JuMP IP formulation ──────────────────────────────────────────────────
    model = Model(HiGHS.Optimizer)
    set_silent(model)

    @variable(model, y[1:m], Bin)   # y[j] = 1 if facility j is open
    @variable(model, z[1:n], Bin)   # z[i] = 1 if demand i is covered

    # Maximize weighted coverage
    @objective(model, Max, sum(weights[i] * z[i] for i in 1:n))

    # Open exactly p facilities
    @constraint(model, sum(y) == p)

    # Demand i can only be covered if at least one covering facility is open
    for i in 1:n
        covering_j = findall(A[i,:])
        if !isempty(covering_j)
            @constraint(model, z[i] <= sum(y[j] for j in covering_j))
        else
            @constraint(model, z[i] == 0)
        end
    end

    optimize!(model)

    y_val = value.(y)
    z_val = value.(z)
    open_set = sort([j for j in 1:m if y_val[j] > 0.5])
    covered = [z_val[i] > 0.5 for i in 1:n]
    w_cov = sum(weights[i] for i in 1:n if covered[i]; init=0.0)
    w_tot = sum(weights)
    MCLPResult(open_set, covered, p, w_cov, w_tot, w_cov/w_tot)
end
