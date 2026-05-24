# branch_bound.jl — Binary Integer Programming via JuMP + HiGHS

# ── Input validation helpers ───────────────────────────────────────────────────
function _bip_validate(c, A, b; sense, max_nodes)
    isempty(c) && error("objective vector c must not be empty")
    size(A, 2) != length(c) &&
        error("A columns ($(size(A,2))) must equal length(c) ($(length(c)))")
    size(A, 1) != length(b) &&
        error("A rows ($(size(A,1))) must equal length(b) ($(length(b)))")
    sense ∉ (:max, :min) &&
        error("sense must be :max or :min (got $(sense))")
    max_nodes < 1 && error("max_nodes must be ≥ 1 (got $(max_nodes))")
    any(!isfinite, c) && error("objective vector c contains NaN or Inf")
    any(!isfinite, A) && error("constraint matrix A contains NaN or Inf")
    any(!isfinite, b) && error("right-hand side b contains NaN or Inf")
end

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

Solve max c'x (or min) s.t. Ax <= b, x in {0,1}^n via JuMP + HiGHS.
"""
function bip_branch_bound(c::AbstractVector, A::AbstractMatrix, b::AbstractVector;
                           sense::Symbol=:max, max_nodes::Int=2000)
    _bip_validate(c, A, b; sense=sense, max_nodes=max_nodes)
    n = length(c)

    model = Model(HiGHS.Optimizer)
    set_silent(model)

    # Set node limit
    set_attribute(model, "mip_max_nodes", max_nodes)

    @variable(model, x[1:n], Bin)

    if sense == :max
        @objective(model, Max, sum(c[j] * x[j] for j in 1:n))
    else
        @objective(model, Min, sum(c[j] * x[j] for j in 1:n))
    end

    # Constraints: Ax <= b
    m_rows = size(A, 1)
    @constraint(model, [i=1:m_rows], sum(A[i,j] * x[j] for j in 1:n) <= b[i])

    optimize!(model)

    status = termination_status(model)

    if status in (OPTIMAL, LOCALLY_SOLVED, FEASIBLE_POINT)
        x_val = round.(Int, value.(x))
        obj = objective_value(model)
        gap_val = 0.0
        try
            gap_val = relative_gap(model)
        catch
            gap_val = 0.0
        end
        n_nodes_explored = 1
        try
            n_nodes_explored = Int(JuMP.node_count(model))
        catch
            n_nodes_explored = 1
        end
        BIPResult(x_val, obj, n_nodes_explored, gap_val, true, :jump_highs)
    else
        BIPResult(zeros(Int, n), sense == :max ? -Inf : Inf, 1, Inf, false, :jump_highs)
    end
end

"""
    knapsack_01(values, weights, capacity; max_nodes) -> BIPResult

0/1 knapsack: maximise sum v_i x_i s.t. sum w_i x_i <= W, x_i in {0,1}.
"""
function knapsack_01(values::AbstractVector, weights::AbstractVector, capacity::Float64;
                     max_nodes::Int=2000)
    n = length(values)
    A = reshape(Float64.(weights), 1, n)
    b = [Float64(capacity)]
    bip_branch_bound(Float64.(values), A, b; sense=:max, max_nodes=max_nodes)
end
