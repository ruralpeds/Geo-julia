# mdp.jl — Markov Decision Processes for healthcare resource allocation

struct MDPResult
    V::Vector{Float64}            # value function V(s) for each state
    policy::Vector{Int}           # optimal action for each state
    n_states::Int
    n_actions::Int
    n_iter::Int
    converged::Bool
    discount::Float64
end

"""
    value_iteration(R, P, γ; tol, max_iter) -> MDPResult

Solve a finite MDP via value iteration.
R[s, a] = immediate reward in state s taking action a.
P[s, a, s'] = transition probability.
γ = discount factor.
"""
function value_iteration(R::AbstractMatrix, P::AbstractArray;
                          γ::Float64=0.95, tol::Float64=1e-6, max_iter::Int=1000)
    n_s, n_a = size(R)
    V    = zeros(n_s)
    pol  = ones(Int, n_s)
    converged = false; n_iter = 0

    for iter in 1:max_iter
        V_new = zeros(n_s)
        for s in 1:n_s
            Q = [R[s,a] + γ * sum(P[s,a,sp]*V[sp] for sp in 1:n_s) for a in 1:n_a]
            V_new[s], pol[s] = findmax(Q)
        end
        δ = maximum(abs.(V_new .- V))
        V = V_new; n_iter = iter
        if δ < tol; converged = true; break; end
    end

    MDPResult(V, pol, n_s, n_a, n_iter, converged, γ)
end

"""
    policy_iteration(R, P, γ; tol, max_iter) -> MDPResult

Solve a finite MDP via policy iteration (usually faster than value iteration).
"""
function policy_iteration(R::AbstractMatrix, P::AbstractArray;
                           γ::Float64=0.95, tol::Float64=1e-6, max_iter::Int=200)
    n_s, n_a = size(R)
    pol  = ones(Int, n_s)
    V    = zeros(n_s)
    converged = false; n_iter = 0

    for iter in 1:max_iter
        # Policy evaluation: solve (I - γP_π)V = R_π
        R_π = [R[s, pol[s]] for s in 1:n_s]
        P_π = [P[s, pol[s], sp] for s in 1:n_s, sp in 1:n_s]
        V   = (I - γ * P_π) \ R_π

        # Policy improvement
        pol_new = zeros(Int, n_s)
        for s in 1:n_s
            Q = [R[s,a] + γ * sum(P[s,a,sp]*V[sp] for sp in 1:n_s) for a in 1:n_a]
            _, pol_new[s] = findmax(Q)
        end
        n_iter = iter
        if pol_new == pol; converged = true; break; end
        pol = pol_new
    end

    MDPResult(V, pol, n_s, n_a, n_iter, converged, γ)
end

"""
    mdp_simulate(result, init_state, P; n_steps, rng) -> NamedTuple

Simulate the MDP under the optimal policy.
Returns trajectory of (states, actions, rewards).
"""
function mdp_simulate(result::MDPResult, init_state::Int, R::AbstractMatrix,
                       P::AbstractArray; n_steps::Int=50, rng=Random.default_rng())
    states  = Int[init_state]
    actions = Int[]
    rewards = Float64[]

    s = init_state
    for _ in 1:n_steps
        a  = result.policy[s]
        r  = R[s, a]
        # Transition
        sp = _sample_next_state(P[s,a,:], rng)
        push!(actions, a); push!(rewards, r); push!(states, sp)
        s  = sp
    end
    (states=states, actions=actions, rewards=rewards,
     total_reward=sum(rewards),
     discounted_reward=sum(result.discount^(t-1)*rewards[t] for t in 1:n_steps))
end

function _sample_next_state(probs, rng)
    u  = rand(rng)
    cs = cumsum(probs)
    findfirst(cs .>= u - 1e-10)
end

# ── Healthcare-specific MDP helpers ───────────────────────────────────────────

"""
    health_resource_mdp(n_states, n_actions; reward_fn, transition_fn) -> (R, P)

Build R and P arrays for a healthcare resource allocation MDP.
States: resource level (0..n_states-1); Actions: allocation level (0..n_actions-1).
"""
function health_resource_mdp(n_states::Int=10, n_actions::Int=5;
                              rng=Random.default_rng())
    # States: patient backlog level (0 = none, n_states-1 = very high)
    # Actions: staffing level (0 = minimal, n_actions-1 = maximum)
    R = zeros(n_states, n_actions)
    P = zeros(n_states, n_actions, n_states)

    for s in 1:n_states, a in 1:n_actions
        staffing  = (a - 1) / max(n_actions - 1, 1)
        backlog   = (s - 1) / max(n_states - 1, 1)
        # Reward: patient outcomes - staffing cost
        R[s,a] = -2.0*backlog - 0.5*staffing + 1.5*staffing*(1-backlog)
        # Transition: higher staffing reduces backlog
        p_reduce = clamp(staffing - 0.1*backlog, 0.0, 0.8)
        p_increase = clamp(0.3 - 0.2*staffing, 0.0, 0.5)
        p_stay = 1.0 - p_reduce - p_increase

        for sp in 1:n_states
            if sp == max(s-1, 1) && s > 1
                P[s,a,sp] = p_reduce
            elseif sp == min(s+1, n_states) && s < n_states
                P[s,a,sp] = p_increase
            elseif sp == s
                P[s,a,sp] += p_stay
                # Absorb boundary probability
                s == 1   && (P[s,a,sp] += p_reduce)
                s == n_states && (P[s,a,sp] += p_increase)
            end
        end
        # Normalise
        P[s,a,:] ./= sum(P[s,a,:])
    end
    R, P
end
