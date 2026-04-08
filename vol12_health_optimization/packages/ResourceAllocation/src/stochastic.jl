# stochastic.jl — Two-stage stochastic programming for resource allocation

struct StochasticResult
    x_first::Vector{Float64}      # first-stage decisions (before uncertainty)
    x_second::Matrix{Float64}     # second-stage recourse [n_vars × n_scenarios]
    obj_expected::Float64         # expected total cost/profit
    obj_evpi::Float64             # expected value of perfect information
    obj_eev::Float64              # expected value of expected value solution
    vss::Float64                  # value of stochastic solution = EEV - obj_expected
    n_scenarios::Int
end

"""
    two_stage_sp(c1, c2, A1, A2, b1, b_scenarios, probs;
                 sense, max_iter) -> StochasticResult

Two-stage stochastic linear program:
    min c1'x + E_ξ[min c2(ξ)'y]
    s.t. A1·x ≤ b1  (first-stage constraints)
         A2·x + y ≤ b(ξ)  (second-stage recourse)
         x,y ≥ 0

Solved via sample-average approximation with LP relaxation per scenario.

`b_scenarios` is n_b2 × n_scenarios matrix; `probs` is probability vector.
"""
function two_stage_sp(c1::AbstractVector, c2::AbstractVector,
                      A1::AbstractMatrix, A2::AbstractMatrix,
                      b1::AbstractVector, b_scenarios::AbstractMatrix,
                      probs::AbstractVector;
                      sense::Symbol=:min, max_iter::Int=100)
    n1, n2, n_s = length(c1), length(c2), size(b_scenarios,2)
    c1s = sense == :min ? c1 : -c1
    c2s = sense == :min ? c2 : -c2

    # EV solution: solve with mean scenario
    b_mean = b_scenarios * probs
    x_ev   = _solve_lp_first_stage(c1s, c2s, A1, A2, b1, b_mean, max_iter)

    # SAA: for each scenario, compute optimal recourse given x
    x_saa  = _saa_first_stage(c1s, c2s, A1, A2, b1, b_scenarios, probs, max_iter)

    # Second-stage decisions
    y_second = zeros(n2, n_s)
    for s in 1:n_s
        y_second[:,s] = _second_stage(x_saa, c2s, A2, b_scenarios[:,s])
    end

    # Objectives
    obj_saa  = dot(c1s, x_saa) + sum(probs[s] * dot(c2s, y_second[:,s]) for s in 1:n_s)
    obj_evpi = sum(probs[s] * _optimal_scenario_obj(c1s, c2s, A1, A2, b1, b_scenarios[:,s], max_iter) for s in 1:n_s)
    obj_eev  = dot(c1s, x_ev) + sum(probs[s] * dot(c2s, _second_stage(x_ev, c2s, A2, b_scenarios[:,s])) for s in 1:n_s)

    evpi = sense == :min ? obj_saa - obj_evpi : obj_evpi - obj_saa
    vss  = sense == :min ? obj_eev - obj_saa  : obj_saa - obj_eev

    StochasticResult(x_saa, y_second, sense==:min ? obj_saa : -obj_saa,
                     evpi, obj_eev, vss, n_s)
end

# Simple LP heuristic: greedy fractional
function _solve_lp_first_stage(c1, c2, A1, A2, b1, b2, max_iter)
    n1 = length(c1)
    # Allocate first-stage resources proportional to c1 values
    x = zeros(n1)
    for j in sortperm(c1)[1:min(n1, length(b1))]
        slack = minimum(b1 .- A1*x)
        step  = slack > 0 ? min(1.0, slack/max(A1[1,j],1e-9)) : 0.0
        x[j]  = clamp(x[j] + step, 0.0, 1.0)
    end
    x
end

function _saa_first_stage(c1, c2, A1, A2, b1, b_scen, probs, max_iter)
    n1  = length(c1)
    n_s = size(b_scen,2)
    # Gradient-based: subgradient on expected recourse
    x   = fill(1.0/n1, n1)
    best_x = copy(x); best_obj = Inf
    α   = 0.1

    for iter in 1:max_iter
        grad = copy(c1)
        for s in 1:n_s
            y = _second_stage(x, c2, A2, b_scen[:,s])
            # Subgradient of recourse: A2'·λ where λ is dual on A2·x+y≤b
            grad .+= probs[s] .* (A2' * min.(A2*x .+ y .- b_scen[:,s], 0.0))
        end
        x .-= (α/iter) .* grad
        x    = max.(x, 0.0)
        # Project onto A1·x ≤ b1
        for _ in 1:10
            viol = A1*x .- b1
            any(viol .> 0) || break
            k = argmax(viol)
            x .-= (viol[k] / sum(A1[k,:].^2)) .* A1[k,:]
            x = max.(x, 0.0)
        end
        obj = dot(c1,x) + sum(probs[s]*dot(c2,_second_stage(x,c2,A2,b_scen[:,s])) for s in 1:n_s)
        obj < best_obj && (best_obj = obj; best_x = copy(x))
    end
    best_x
end

function _second_stage(x, c2, A2, b2)
    # Second-stage: min c2'y s.t. y ≥ b2 - A2·x, y ≥ 0
    y = max.(b2 .- A2*x, 0.0)
    max.(y, 0.0)
end

function _optimal_scenario_obj(c1, c2, A1, A2, b1, b2_s, max_iter)
    x = _solve_lp_first_stage(c1, c2, A1, A2, b1, b2_s, max_iter)
    y = _second_stage(x, c2, A2, b2_s)
    dot(c1,x) + dot(c2,y)
end

"""
    expected_value_solution(c1, c2, A1, A2, b1, b_scenarios, probs) -> NamedTuple

Compute the expected value solution (EV) and its performance in expectation.
"""
function expected_value_solution(c1, c2, A1, A2, b1, b_scenarios, probs)
    b_mean = b_scenarios * probs
    x_ev   = _solve_lp_first_stage(c1, c2, A1, A2, b1, b_mean, 100)
    n_s    = size(b_scenarios,2)
    obj_ev = dot(c1,x_ev) + sum(probs[s]*dot(c2, _second_stage(x_ev,c2,A2,b_scenarios[:,s]))
                                for s in 1:n_s)
    (x_ev=x_ev, obj=obj_ev, b_mean=b_mean)
end
