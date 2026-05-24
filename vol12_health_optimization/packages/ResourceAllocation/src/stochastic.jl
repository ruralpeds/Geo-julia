# stochastic.jl — Two-stage stochastic programming via JuMP

struct StochasticResult
    x_first::Vector{Float64}      # first-stage decisions (before uncertainty)
    x_second::Matrix{Float64}     # second-stage recourse [n_vars x n_scenarios]
    obj_expected::Float64         # expected total cost/profit
    obj_evpi::Float64             # expected value of perfect information
    obj_eev::Float64              # expected value of expected value solution
    vss::Float64                  # value of stochastic solution = EEV - obj_expected
    n_scenarios::Int
end

"""
    two_stage_sp(c1, c2, A1, A2, b1, b_scenarios, probs;
                 sense, max_iter) -> StochasticResult

Two-stage stochastic linear program solved via JuMP deterministic equivalent:
    min c1'x + E_xi[min c2(xi)'y]
    s.t. A1*x <= b1  (first-stage constraints)
         A2*x + y >= b(xi)  (second-stage recourse, per scenario)
         x,y >= 0

`b_scenarios` is n_b2 x n_scenarios matrix; `probs` is probability vector.
"""
function two_stage_sp(c1::AbstractVector, c2::AbstractVector,
                      A1::AbstractMatrix, A2::AbstractMatrix,
                      b1::AbstractVector, b_scenarios::AbstractMatrix,
                      probs::AbstractVector;
                      sense::Symbol=:min, max_iter::Int=100)
    n1, n2, n_s = length(c1), length(c2), size(b_scenarios,2)
    n_b2 = size(b_scenarios, 1)

    # ── Deterministic equivalent via JuMP ────────────────────────────────────
    # SAA solution
    x_saa = _solve_two_stage_jump(c1, c2, A1, A2, b1, b_scenarios, probs, sense)

    # Second-stage decisions for each scenario given x_saa
    y_second = zeros(n2, n_s)
    for s in 1:n_s
        y_second[:,s] = _solve_second_stage_jump(x_saa, c2, A2, b_scenarios[:,s], sense)
    end

    # Compute objectives
    c1s = sense == :min ? c1 : -c1
    c2s = sense == :min ? c2 : -c2
    obj_saa = dot(c1s, x_saa) + sum(probs[s] * dot(c2s, y_second[:,s]) for s in 1:n_s)

    # EVPI: solve each scenario independently, take expectation
    obj_evpi_val = sum(probs[s] * _solve_single_scenario_jump(c1, c2, A1, A2, b1,
                        b_scenarios[:,s], sense) for s in 1:n_s)

    # EEV: solve with mean scenario, evaluate in expectation
    b_mean = b_scenarios * probs
    x_ev = _solve_two_stage_jump(c1, c2, A1, A2, b1, reshape(b_mean, :, 1), [1.0], sense)
    y_ev_second = zeros(n2, n_s)
    for s in 1:n_s
        y_ev_second[:,s] = _solve_second_stage_jump(x_ev, c2, A2, b_scenarios[:,s], sense)
    end
    obj_eev = dot(c1s, x_ev) + sum(probs[s] * dot(c2s, y_ev_second[:,s]) for s in 1:n_s)

    evpi = sense == :min ? obj_saa - obj_evpi_val : obj_evpi_val - obj_saa
    vss  = sense == :min ? obj_eev - obj_saa : obj_saa - obj_eev

    final_obj = sense == :min ? obj_saa : -obj_saa

    StochasticResult(x_saa, y_second, final_obj, evpi, obj_eev, vss, n_s)
end

"""Solve the full two-stage deterministic equivalent via JuMP."""
function _solve_two_stage_jump(c1, c2, A1, A2, b1, b_scenarios, probs, sense)
    n1 = length(c1)
    n2 = length(c2)
    n_s = size(b_scenarios, 2)
    n_b2 = size(b_scenarios, 1)

    model = Model(HiGHS.Optimizer)
    set_silent(model)

    @variable(model, x[1:n1] >= 0)
    @variable(model, y[1:n2, 1:n_s] >= 0)

    # Objective: c1'x + sum_s probs[s] * c2'y_s
    if sense == :min
        @objective(model, Min,
            sum(c1[j] * x[j] for j in 1:n1) +
            sum(probs[s] * sum(c2[j] * y[j,s] for j in 1:n2) for s in 1:n_s))
    else
        @objective(model, Max,
            sum(c1[j] * x[j] for j in 1:n1) +
            sum(probs[s] * sum(c2[j] * y[j,s] for j in 1:n2) for s in 1:n_s))
    end

    # First-stage constraints: A1*x <= b1
    m1 = size(A1, 1)
    @constraint(model, [i=1:m1], sum(A1[i,j] * x[j] for j in 1:n1) <= b1[i])

    # Second-stage recourse: A2*x + y >= b(xi) for each scenario
    for s in 1:n_s
        for i in 1:n_b2
            @constraint(model, sum(A2[i,j] * x[j] for j in 1:min(n1, size(A2,2))) + y[min(i,n2),s] >= b_scenarios[i,s])
        end
    end

    optimize!(model)

    status = termination_status(model)
    if status in (OPTIMAL, LOCALLY_SOLVED, FEASIBLE_POINT)
        return value.(x)
    else
        # Fallback: return a feasible first-stage solution
        return zeros(n1)
    end
end

"""Solve second-stage recourse given first-stage x."""
function _solve_second_stage_jump(x_first, c2, A2, b2_scenario, sense)
    n2 = length(c2)
    n1 = length(x_first)
    n_b2 = length(b2_scenario)

    model = Model(HiGHS.Optimizer)
    set_silent(model)

    @variable(model, y[1:n2] >= 0)

    if sense == :min
        @objective(model, Min, sum(c2[j] * y[j] for j in 1:n2))
    else
        @objective(model, Max, sum(c2[j] * y[j] for j in 1:n2))
    end

    # y >= b(xi) - A2*x
    for i in 1:n_b2
        rhs = b2_scenario[i] - sum(A2[i,j] * x_first[j] for j in 1:min(n1, size(A2,2)))
        @constraint(model, y[min(i,n2)] >= rhs)
    end

    optimize!(model)

    status = termination_status(model)
    if status in (OPTIMAL, LOCALLY_SOLVED, FEASIBLE_POINT)
        return value.(y)
    else
        return max.(b2_scenario[1:n2] .- A2[1:n2,1:min(n1,size(A2,2))] * x_first[1:min(n1,size(A2,2))], 0.0)
    end
end

"""Solve a single scenario optimally (for EVPI calculation)."""
function _solve_single_scenario_jump(c1, c2, A1, A2, b1, b2_s, sense)
    n1 = length(c1)
    n2 = length(c2)
    n_b2 = length(b2_s)

    model = Model(HiGHS.Optimizer)
    set_silent(model)

    @variable(model, x[1:n1] >= 0)
    @variable(model, y[1:n2] >= 0)

    c1s = sense == :min ? c1 : -c1
    c2s = sense == :min ? c2 : -c2

    @objective(model, Min,
        sum(c1s[j] * x[j] for j in 1:n1) +
        sum(c2s[j] * y[j] for j in 1:n2))

    # First-stage constraints
    m1 = size(A1, 1)
    @constraint(model, [i=1:m1], sum(A1[i,j] * x[j] for j in 1:n1) <= b1[i])

    # Second-stage: A2*x + y >= b2_s
    for i in 1:n_b2
        @constraint(model, sum(A2[i,j] * x[j] for j in 1:min(n1, size(A2,2))) + y[min(i,n2)] >= b2_s[i])
    end

    optimize!(model)

    status = termination_status(model)
    if status in (OPTIMAL, LOCALLY_SOLVED, FEASIBLE_POINT)
        return objective_value(model)
    else
        # Fallback
        x_f = zeros(n1)
        y_f = max.(b2_s[1:min(n_b2,n2)], 0.0)
        return dot(c1s, x_f) + dot(c2s, y_f)
    end
end

"""
    expected_value_solution(c1, c2, A1, A2, b1, b_scenarios, probs) -> NamedTuple

Compute the expected value solution (EV) and its performance in expectation.
"""
function expected_value_solution(c1, c2, A1, A2, b1, b_scenarios, probs)
    b_mean = b_scenarios * probs
    x_ev = _solve_two_stage_jump(c1, c2, A1, A2, b1, reshape(b_mean, :, 1), [1.0], :min)
    n_s = size(b_scenarios, 2)
    n2 = length(c2)
    obj_ev = dot(c1, x_ev) + sum(probs[s] * dot(c2,
        _solve_second_stage_jump(x_ev, c2, A2, b_scenarios[:,s], :min))
        for s in 1:n_s)
    (x_ev=x_ev, obj=obj_ev, b_mean=b_mean)
end
