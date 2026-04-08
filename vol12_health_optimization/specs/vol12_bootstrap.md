# Vol 12 Bootstrap Specification
## Healthcare Facility Location, Routing, and Resource Allocation

### Overview

Volume 12 applies operations research methods to healthcare planning problems
in North Dakota: where to site clinics, how to route EMS vehicles, and how to
allocate constrained budgets under uncertainty.

---

### Package 1: FacilityLocation.jl

**Scope**: p-Median, Set Cover, MCLP, Capacitated FLP, Voronoi catchments

#### p-Median (Hakimi 1964)
- Minimise total weighted travel distance
- Greedy initialisation: open facility with maximum marginal gain
- 2-opt facility swap until no improvement
- Distance matrix pre-computed; supports `n_restarts`

#### Set Cover (Toregas et al. 1971)
- Greedy: open facility covering most uncovered weighted demand
- Repeat until all demand covered (or infeasible if impossible)
- Coverage matrix `A[i,j] = 1(dist(i,j) ≤ r)`

#### MCLP (Church & ReVelle 1974)
- Maximise covered demand with exactly `p` facilities
- Greedy + random restarts + 1-opt improvement
- Returns `coverage_fraction` and `open_facilities`

#### Capacitated FLP
- Same objective as p-median but respects facility capacity `Q_j`
- Exchange heuristic with feasibility check
- Returns `feasible` flag and `capacity_used` per facility

#### Voronoi Catchments
- Assign each demand point to nearest open facility
- Returns `catchment_pop`, `mean_access`, `gini` coefficient

#### API Contract
```julia
p_median(demand_pts, cand_pts, p; weights, max_iter, rng) -> PMedianResult
p_median(pts, p; kw...)  # convenience: candidates = demand points
set_cover(demand_pts, cand_pts; coverage_radius, weights) -> SetCoverResult
mclp(demand_pts, cand_pts, p; coverage_radius, weights, n_restarts, rng) -> MCLPResult
cap_flp(demand_pts, cand_pts, p; weights, capacities, max_iter, rng) -> CapFLPResult
catchment_voronoi(demand_pts, facility_pts; weights) -> NamedTuple
```

---

### Package 2: HealthRouting.jl

**Scope**: TSP, VRP, MEXCLP, Dispatch, Erlang-C staffing

#### TSP Nearest-Neighbour
- O(n²) greedy; start at `start` node; return to depot
- `improvement = 0.0` (baseline)

#### TSP 2-opt
- Reverse sub-tour `[i+1..j]` when profitable
- Returns `improvement` (absolute reduction vs NN baseline)

#### VRP Clarke-Wright Savings
- Savings `S[i,j] = d(depot,i) + d(depot,j) - d(i,j)`
- Sort savings descending; merge if capacity permits and orientation correct
- Returns per-route distances and loads

#### MEXCLP (Daskin 1983)
- P(covered | k vehicles) = 1 - q^k, q = busy_fraction
- Greedy marginal gain: Δⱼ = Σᵢ wᵢ[(1-q^{cᵢ+1}) - (1-q^{cᵢ})]
- Supports uniform or weighted demand

#### Dispatch Assignment
- Assign each incident to nearest station with available units
- Returns assignment vector (station index per incident)

#### Erlang-C Staffing
- Formula computed in log-space (stable for large c)
- Returns `p_wait`, `mean_wait`, `mean_queue`, `min_servers`
- `min_servers`: minimum c s.t. P(wait) ≤ target_pw

#### API Contract
```julia
tsp_nn(pts; start, rng) -> TSPResult
tsp_two_opt(pts; init_tour, max_iter, rng) -> TSPResult
vrp_cw(customers, depot; demands, capacity) -> VRPResult
mexclp(demand_pts, cand_pts, p; weights, busy_fraction, coverage_radius, rng) -> EmergencyResult
dispatch_assignment(incidents, stations, available) -> Vector{Int}
erlang_c(λ, μ, c; target_pw) -> NamedTuple
routing_report(clients, depot; λ, μ, c_init, rng) -> NamedTuple
print_routing_report(rpt)
```

---

### Package 3: ResourceAllocation.jl

**Scope**: 0/1 Knapsack, Branch and Bound, Two-Stage SP, MDP

#### Branch and Bound (BIP)
- LP relaxation via greedy fractional upper bound
- Branch on most fractional variable
- Prune if LP bound ≤ best integer; `max_nodes` limit

#### 0/1 Knapsack
- Special case of BIP: A = [weights'], b = [capacity]
- Returns selected items and total value

#### Two-Stage Stochastic Programming
- Stage 1: `min c1'x + E[Q(x,ξ)]` s.t. A1 x ≤ b1
- Stage 2: `Q(x,ξ) = min c2'y` s.t. A2 x + y ≥ b(ξ)
- First stage via subgradient on expected recourse
- `VSS = EEV - z*_SP`, `EVPI = z*_SP - z*_PI`

#### Markov Decision Process
- Value iteration: Bellman operator until δ < tol
- Policy iteration: solve linear system + greedy improvement
- `health_resource_mdp`: states = backlog 0..9, actions = staffing 1..5
- Simulate: trajectory under optimal policy; discounted reward

#### API Contract
```julia
bip_branch_bound(c, A, b; sense, max_nodes) -> BIPResult
knapsack_01(values, weights, capacity; max_nodes) -> BIPResult
two_stage_sp(c1, c2, A1, A2, b1, b_scen, probs; sense) -> StochasticResult
value_iteration(R, P; γ, tol, max_iter) -> MDPResult
policy_iteration(R, P; γ, tol, max_iter) -> MDPResult
mdp_simulate(result, init_state, R, P; n_steps, rng) -> NamedTuple
health_resource_mdp(n_states, n_actions; rng) -> (R, P)
allocation_report(; study_name, values, weights, capacity, R, P, γ, c1, c2, A1, A2, b1, b_scen, probs) -> NamedTuple
print_allocation_report(rpt)
```

---

### Integration Test Requirements

1. **FacilityLocation ↔ HealthRouting**: p-median sites → VRP routes serve those sites
2. **FacilityLocation ↔ ResourceAllocation**: MCLP coverage → knapsack selects programmes achieving coverage
3. **HealthRouting ↔ ResourceAllocation**: Erlang-C staffing → MDP staffing policy agrees directionally
4. **End-to-end ND pipeline**: all three packages combined for a 53-county scenario

---

### Numerical Stability Requirements

- All computations in Float64
- Erlang-C: log-space computation to prevent factorial overflow for c > 20
- Branch and bound: LP relaxation never exceeds integer bound by >1e-6
- Two-stage SP: subgradient step size decays as 1/√k
- MDP value iteration: convergence criterion ‖V_{k+1} - V_k‖_∞ < tol

---

### ND Context

- **Demand points**: 53 county seats (proxy population weights)
- **Candidates**: rural intersections + county hospitals
- **Coverage radius**: 30 km primary care, 15 km emergency
- **Budget**: \$12M statewide health programmes
- **EMS**: 3.0 calls/hr, 0.5 hr service time, P(wait) ≤ 0.20 target
