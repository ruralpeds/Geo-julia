"""
    TestUtils

Shared testing utilities for the Geo-Julia open healthcare textbook.

## Sub-modules / components

- **Generators** — reproducible test-data factories
  (`gen_uniform_pts`, `gen_clustered_pts`, `gen_nd_scenario`, …)
- **Metrics** — result collection and failure categorisation
  (`ResultStore`, `TestOutcome`, `summary`, `categorise_failure`, …)

## Quick start

    using TestUtils

    sc = gen_nd_scenario(; rng=MersenneTwister(1), n_demand=20, n_cand=15)
    # sc.demand_pts, sc.cand_pts, sc.weights, sc.depot

    store = ResultStore()
    push!(store, TestOutcome("my_test", "runtests.jl", 10, 0, 0, 0.05))
    println(summary(store))
"""
module TestUtils

using Random, Statistics, Test, LinearAlgebra

include("generators.jl")
include("metrics.jl")

export
    # Generators
    gen_uniform_pts,
    gen_clustered_pts,
    gen_grid_pts,
    gen_weights,
    gen_unit_weights,
    gen_nd_scenario,
    gen_resource_problem,
    gen_mdp,
    gen_tsp_tour,

    # Metrics / result store
    TestOutcome,
    ResultStore,
    summary,
    failed_outcomes,
    passed_outcomes,
    status,
    categorise_failure,
    categorise_outcome,
    detect_regressions,
    @timed_testset

end # module
