#!/usr/bin/env julia
# scripts/resource_allocation.jl
# Healthcare budget allocation under uncertainty and dynamic staffing decisions

using Statistics, Random, LinearAlgebra

include(joinpath(@__DIR__, "..", "packages", "ResourceAllocation", "src", "ResourceAllocation.jl"))
using .ResourceAllocation

println("=" ^ 65)
println("  Vol 12 — Resource Allocation: ND Healthcare Budget")
println("  Knapsack · Stochastic Programming · MDP")
println("=" ^ 65)

# ── Section 1: 0/1 Knapsack Budget Allocation ────────────────────────────────

println("\n[1] Budget Allocation (0/1 Knapsack)")
# 10 healthcare programmes with value (QALY per $1M) and cost ($M)
programmes = ["Rural telehealth", "Mobile clinic", "Maternal care",
              "Mental health", "Diabetes mgmt", "Cancer screening",
              "EMS upgrade", "Nurse training", "Lab equipment", "IT systems"]
values  = [3.2, 2.8, 4.1, 3.7, 2.5, 3.0, 2.1, 1.8, 1.5, 1.2]
weights = [2.0, 3.0, 4.0, 3.5, 2.5, 3.5, 4.0, 2.0, 2.5, 1.5]
budget  = 12.0

println("  Budget: \$$(budget)M  $(length(programmes)) programmes")
res = knapsack_01(values, weights, budget; max_nodes=5000)
selected = findall(==(1), res.x)
println("  Optimal selection: $(programmes[selected])")
println("  Total QALY value: $(round(res.objective,digits=2))")
println("  Total cost: \$$(round(dot(res.x, weights),digits=1))M")
println("  Budget utilisation: $(round(100*dot(res.x,weights)/budget,digits=1))%")

# Sensitivity: vary budget
println("\n  Budget sensitivity:")
for bud in [8.0, 10.0, 12.0, 15.0, 18.0]
    r = knapsack_01(values, weights, bud)
    println("    \$$(bud)M budget: $(round(r.objective,digits=2)) QALY  $(sum(r.x)) programmes")
end

# ── Section 2: Stochastic Programming ────────────────────────────────────────

println("\n[2] Two-Stage Stochastic Programming (demand uncertainty)")
# First stage: procure ambulances now (cost per unit = 1.5)
# Second stage: rent additional units if demand exceeds supply (cost = 4.0)
rng2  = MersenneTwister(2)
n_s   = 5
c1    = [1.5, 1.5]     # buy 2 types of equipment now
c2    = [4.0, 4.0]     # rent if insufficient
A1    = [1.0 1.0; 1.0 0.0; 0.0 1.0]
b1    = [10.0, 7.0, 7.0]
A2    = diagm(ones(2))
# Demand scenarios (5): low, medium-low, medium, medium-high, high
demands = hcat([3.0,2.0],[4.5,3.5],[6.0,5.0],[7.5,6.0],[9.0,8.0])
probs   = [0.1, 0.2, 0.4, 0.2, 0.1]

res_sp = two_stage_sp(c1, c2, A1, A2, b1, demands, probs; sense=:min)
println("  First-stage procurement: $(round.(res_sp.x_first,digits=2))")
println("  Expected total cost:     $(round(res_sp.obj_expected,digits=4))")
println("  VSS (value of stochastic solution): $(round(res_sp.vss,digits=4))")
println("  EVPI (expected value of perfect info): $(round(res_sp.obj_evpi,digits=4))")
println("  Recourse by scenario:")
for s in 1:n_s
    println("    Scenario $s (p=$(probs[s])): recourse=$(round.(res_sp.x_second[:,s],digits=2))")
end

# ── Section 3: Markov Decision Process ───────────────────────────────────────

println("\n[3] MDP: Dynamic Staffing Policy")
println("  States: ED patient backlog (0=none, 9=severe)")
println("  Actions: staffing level (1=minimal, 5=maximum)")
R, P = health_resource_mdp(10, 5)
vi   = value_iteration(R, P; γ=0.95)
pi_r = policy_iteration(R, P; γ=0.95)

println("  Value iteration: converged=$(vi.converged) in $(vi.n_iter) iterations")
println("  Policy iteration: converged=$(pi_r.converged) in $(pi_r.n_iter) iterations")
println()
println("  Optimal policy (state → action):")
for s in 1:10
    backlog = (s-1)/9
    println("    Backlog $(round(backlog*100,digits=0))%: staff level $(vi.policy[s])  V=$(round(vi.V[s],digits=3))")
end

# ── Section 4: MDP Simulation ─────────────────────────────────────────────────

println("\n[4] MDP Policy Simulation")
rng4 = MersenneTwister(4)
sim  = mdp_simulate(vi, 5, R, P; n_steps=30, rng=rng4)
println("  Initial state: 5 (50% backlog)")
println("  Simulated steps: 30")
println("  Final state: $(sim.states[end])")
println("  Total reward: $(round(sim.total_reward,digits=3))")
println("  Discounted reward: $(round(sim.discounted_reward,digits=3))")
println("  Action distribution: $(sort(collect(pairs(Dict(a=>count(==(a),sim.actions) for a in 1:5)))))")

# ── Section 5: Budget → Programme → Coverage ─────────────────────────────────

println("\n[5] Joint Allocation: Budget, Access, and Quality")
println("  Multi-criteria: maximise QALY per dollar while achieving ≥60% rural coverage")
# Phase 1: select programmes with knapsack
# Phase 2: verify rural coverage (proxy: weighted sum of rural-relevant programmes)
rural_rel = [1,1,1,1,1,0,1,0,0,0]   # rural-relevant flag
for budget_m in [10.0, 14.0, 18.0]
    r  = knapsack_01(values .* (1 .+ 0.5 .* rural_rel), weights, budget_m)
    sel = r.x
    rl = dot(sel, rural_rel .* values) / max(dot(sel, values), 1e-10)
    println("  \$$(budget_m)M: QALY=$(round(r.objective,digits=2))  " *
            "rural share=$(round(rl*100,digits=1))%")
end

# ── Section 6: Full report ────────────────────────────────────────────────────

println("\n[6] Allocation Report")
R, P = health_resource_mdp(5, 3)
rpt  = allocation_report(study_name="ND Health Budget";
                          values=values[1:5], weights=weights[1:5], capacity=10.0,
                          R=R, P=P, γ=0.95,
                          c1=c1, c2=c2, A1=A1[1:2,:], A2=A2,
                          b1=b1[1:2], b_scen=demands, probs=probs)
print_allocation_report(rpt)

println("\n✓ Resource allocation pipeline complete.")
