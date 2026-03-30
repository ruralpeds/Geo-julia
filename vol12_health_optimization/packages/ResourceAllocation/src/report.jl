# report.jl — Resource allocation summary report

struct AllocationReport
    study_name::String
    knapsack_obj::Float64
    knapsack_n_items::Int
    sp_obj::Float64
    sp_vss::Float64
    sp_evpi::Float64
    mdp_converged::Bool
    mdp_n_iter::Int
    mdp_mean_value::Float64
    timestamp::String
end

function allocation_report(;
        study_name="Allocation Study",
        values=Float64[], weights=Float64[], capacity=10.0,
        R=zeros(5,3), P=zeros(5,3,5), γ=0.9,
        c1=Float64[], c2=Float64[], A1=zeros(1,1), A2=zeros(1,1),
        b1=Float64[], b_scen=zeros(1,1), probs=Float64[],
        rng=Random.default_rng())

    ks  = knapsack_01(values, weights, capacity)
    mdp = value_iteration(R, P; γ=γ)
    sp  = isempty(c1) ? nothing :
          two_stage_sp(c1, c2, A1, A2, b1, b_scen, probs)

    AllocationReport(
        study_name,
        isempty(values) ? NaN : ks.objective, sum(isempty(values) ? Int[] : ks.x),
        isnothing(sp) ? NaN : sp.obj_expected,
        isnothing(sp) ? NaN : sp.vss,
        isnothing(sp) ? NaN : sp.obj_evpi,
        mdp.converged, mdp.n_iter, mean(mdp.V),
        "$(time_ns())")
end

function print_allocation_report(r::AllocationReport)
    println("=" ^ 55)
    println("  Resource Allocation: $(r.study_name)")
    println("-" ^ 55)
    isfinite(r.knapsack_obj) &&
        println("  Knapsack: obj=$(round(r.knapsack_obj,digits=2))  items=$(r.knapsack_n_items)")
    isfinite(r.sp_obj) &&
        println("  Stochastic prog: E[obj]=$(round(r.sp_obj,digits=4))")
    isfinite(r.sp_vss) &&
        println("    VSS=$(round(r.sp_vss,digits=4))  EVPI=$(round(r.sp_evpi,digits=4))")
    println("  MDP: converged=$(r.mdp_converged)  iters=$(r.mdp_n_iter)  E[V]=$(round(r.mdp_mean_value,digits=3))")
end
