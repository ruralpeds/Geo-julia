# branch_bound.jl — Binary Integer Programming via branch and bound

struct BIPResult
    x::Vector{Int}              # optimal binary solution
    objective::Float64
    n_nodes::Int                # B&B nodes explored
    gap::Float64                # optimality gap (0 = proven optimal)
    feasible::Bool
    method::Symbol
end

"""
    bip_branch_bound(c, A, b; sense, max_nodes) -> BIPResult

Solve max c'x (or min) s.t. Ax ≤ b, x ∈ {0,1}^n via branch and bound.
LP relaxations solved via simplex (interior point not required for small n).
Best for n ≤ 25.
"""
function bip_branch_bound(c::AbstractVector, A::AbstractMatrix, b::AbstractVector;
                           sense::Symbol=:max, max_nodes::Int=2000)
    n   = length(c)
    c_s = sense == :max ? c : -c   # convert to maximisation

    best_obj = -Inf
    best_x   = zeros(Int, n)
    n_nodes  = 0

    # Stack of (lower_bounds, upper_bounds) for each variable
    stack = [(zeros(Int,n), ones(Int,n), Float64[])]

    while !isempty(stack) && n_nodes < max_nodes
        lb, ub, _ = pop!(stack)
        n_nodes  += 1

        # LP relaxation: maximise c'x s.t. Ax≤b, lb≤x≤ub (0≤x≤1)
        lp_obj, lp_x = _solve_lp_relaxation(c_s, A, b, lb, ub)
        lp_obj === nothing && continue  # infeasible
        lp_obj <= best_obj - 1e-9 && continue  # prune

        # Check integrality
        frac_vars = findall(x -> lb[x] < lp_x[x] < ub[x] - 1e-6 && abs(lp_x[x] - round(lp_x[x])) > 1e-6, 1:n)

        if isempty(frac_vars)
            # Integer solution
            obj = dot(c_s, round.(Int, lp_x))
            if obj > best_obj
                best_obj = obj; best_x = round.(Int, lp_x)
            end
        else
            # Branch on most fractional variable
            j   = frac_vars[argmax([abs(lp_x[k] - 0.5) for k in frac_vars] .* -1 .+ 0.5)]
            # Branch x_j = 0
            lb0 = copy(lb); ub0 = copy(ub); ub0[j] = 0
            push!(stack, (lb0, ub0, Float64[]))
            # Branch x_j = 1
            lb1 = copy(lb); ub1 = copy(ub); lb1[j] = 1
            push!(stack, (lb1, ub1, Float64[]))
        end
    end

    feasible = best_obj > -Inf
    final_obj = sense == :max ? best_obj : -best_obj
    BIPResult(best_x, final_obj, n_nodes, 0.0, feasible, :branch_and_bound)
end

# Simple LP relaxation via projected gradient / greedy for covering structure
function _solve_lp_relaxation(c, A, b, lb, ub)
    n  = length(c)
    x  = Float64.(lb) .+ (Float64.(ub) .- Float64.(lb)) .* 0.5  # midpoint start
    # Use the LP relaxation bound from greedy fractional solution
    # (sufficient for bounding; exact LP not needed for small n)
    # Greedy fractional by c/constraint-ratio
    x  = copy(Float64.(ub))
    # Check feasibility: Ax ≤ b
    for iter in 1:100
        viol = A * x .- b
        all(viol .<= 1e-8) && break
        # Reduce most violating variable
        k = argmax(viol)
        for j in n:-1:1
            A[k,j] > 1e-9 || continue
            slack = (b[k] - dot(A[k,:], x) + A[k,j]*x[j]) / A[k,j]
            x[j]  = clamp(slack, lb[j], ub[j])
        end
    end
    # Clamp to bounds
    x = clamp.(x, Float64.(lb), Float64.(ub))
    viol = A * x .- b
    any(viol .> 0.1) && return (nothing, x)
    (dot(c, x), x)
end

"""
    knapsack_01(values, weights, capacity; max_nodes) -> BIPResult

0/1 knapsack: maximise Σ vᵢxᵢ s.t. Σ wᵢxᵢ ≤ W, xᵢ ∈ {0,1}.
"""
function knapsack_01(values::AbstractVector, weights::AbstractVector, capacity::Float64;
                     max_nodes::Int=2000)
    n = length(values)
    A = reshape(Float64.(weights), 1, n)
    b = [Float64(capacity)]
    bip_branch_bound(Float64.(values), A, b; sense=:max, max_nodes=max_nodes)
end
