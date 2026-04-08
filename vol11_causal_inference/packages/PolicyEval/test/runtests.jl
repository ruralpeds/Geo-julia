using Test, Statistics, Random, LinearAlgebra

include(joinpath(@__DIR__, "..", "src", "PolicyEval.jl"))
using .PolicyEval

function make_panel(n_units=30, n_periods=8; seed=2, true_att=3.0, treat_frac=0.4)
    rng      = MersenneTwister(seed)
    treat_id = randperm(rng, n_units)[1:round(Int, n_units*treat_frac)]
    treat    = zeros(Bool, n_units)
    treat[treat_id] .= true
    treat_t  = 5  # treatment starts period 5

    y = Float64[]; D = Bool[]; P = Bool[]; U = Int[]; T = Int[]
    for u in 1:n_units, t in 1:n_periods
        unit_fe = 0.5 * u / n_units
        time_fe = 0.1 * t
        post    = t >= treat_t
        is_tr   = treat[u]
        effect  = is_tr && post ? true_att : 0.0
        push!(y, unit_fe + time_fe + effect + 0.3*randn(rng))
        push!(D, is_tr); push!(P, post); push!(U, u); push!(T, t)
    end
    (y=y, treat=D, post=P, unit_ids=U, time=T, treat_t=treat_t, n_units=n_units)
end

function make_synth_data(T_pre=10, T_post=5, n_donors=8; seed=3, true_effect=2.0)
    rng    = MersenneTwister(seed)
    donors = randn(rng, T_pre + T_post, n_donors)
    # Treated = weighted sum of donors + noise (pre); + effect (post)
    w_true = abs.(randn(rng, n_donors)); w_true ./= sum(w_true)
    y      = donors * w_true .+ 0.1 .* randn(rng, T_pre + T_post)
    y[T_pre+1:end] .+= true_effect
    (Y_treated_pre=y[1:T_pre], Y_treated_post=y[T_pre+1:end],
     Y_donors_pre=donors[1:T_pre,:], Y_donors_post=donors[T_pre+1:end,:],
     true_effect=true_effect)
end

function make_rdd_data(n=300; seed=4, true_tau=5.0, cutoff=0.0)
    rng = MersenneTwister(seed)
    x   = randn(rng, n)
    y   = 2.0 .* x .+ true_tau .* (x .>= cutoff) .+ randn(rng, n)
    (y=y, x=x, cutoff=cutoff, true_tau=true_tau)
end

@testset "DiD 2×2" begin
    d   = make_panel()
    rng = MersenneTwister(20)
    res = did_2x2(d.y, d.treat, d.post; unit_ids=d.unit_ids, n_boot=50, rng=rng)
    @test isfinite(res.β_did)
    @test res.se > 0.0
    @test res.ci_lower < res.β_did < res.ci_upper
    # ATT should be close to true 3.0
    @test abs(res.β_did - 3.0) < 2.0
end

@testset "Event study" begin
    d   = make_panel()
    rng = MersenneTwister(21)
    es  = event_study(d.y, d.treat, d.time;
                      treat_time=d.treat_t, unit_ids=d.unit_ids, n_boot=50, rng=rng)
    @test length(es.β) == length(es.rel_periods)
    @test all(isfinite.(es.β))
    @test all(es.se .>= 0.0)
    @test all(es.β_lower .<= es.β)
end

@testset "Parallel trends test" begin
    d   = make_panel()
    rng = MersenneTwister(22)
    pt  = parallel_trends_test(d.y, d.treat, d.time;
                                treat_time=d.treat_t, unit_ids=d.unit_ids,
                                n_boot=50, rng=rng)
    @test isfinite(pt.chi2)
    @test 0.0 <= pt.p_value <= 1.0
end

@testset "Staggered DiD" begin
    rng   = MersenneTwister(23)
    n_u   = 20; n_t = 6
    cohort = fill(Inf, n_u)
    cohort[1:8]  .= 3.0  # cohort 3
    cohort[9:14] .= 5.0  # cohort 5
    y_s    = Float64[]; tc = Float64[]; times = Int[]
    for u in 1:n_u, t in 1:n_t
        post = t >= cohort[u]
        push!(y_s, post && isfinite(cohort[u]) ? 2.0 + randn(rng)*0.3 : randn(rng)*0.3)
        push!(tc, cohort[u]); push!(times, t)
    end
    sd = staggered_did(y_s, tc, times; n_boot=30, rng=rng)
    @test isfinite(sd.att_agg)
    @test sd.n_cohorts == 2
end

@testset "Synthetic control" begin
    d   = make_synth_data()
    res = synth_control(d.Y_treated_pre, d.Y_donors_pre,
                        d.Y_treated_post, d.Y_donors_post)
    @test length(res.weights) == size(d.Y_donors_pre, 2)
    @test abs(sum(res.weights) - 1.0) < 1e-6
    @test all(res.weights .>= -1e-8)
    @test res.rmspe_pre >= 0.0
    @test res.rmspe_post >= 0.0
    # ratio should be > 1 (effect present)
    @test res.ratio > 1.0
end

@testset "Synth gaps and placebo" begin
    d   = make_synth_data()
    res = synth_control(d.Y_treated_pre, d.Y_donors_pre,
                        d.Y_treated_post, d.Y_donors_post; n_placebo_iter=4)
    gaps = synth_gaps(d.Y_treated_post, d.Y_donors_post, res.weights)
    @test length(gaps) == length(d.Y_treated_post)
    pl   = synth_placebo(res)
    @test 0.0 <= pl.p_value <= 1.0
    @test isfinite(pl.ratio)
end

@testset "RDD basic" begin
    d   = make_rdd_data(; true_tau=5.0)
    rng = MersenneTwister(30)
    res = rdd_fit(d.y, d.x; cutoff=d.cutoff, n_boot=50, rng=rng)
    @test isfinite(res.τ)
    @test res.se > 0.0
    @test res.n_left > 0
    @test res.n_right > 0
    # Should detect effect close to true 5.0
    @test abs(res.τ - 5.0) < 3 * res.se + 1.0
end

@testset "RDD bandwidth and polynomial" begin
    d   = make_rdd_data(n=200)
    rng = MersenneTwister(31)
    r1  = rdd_fit(d.y, d.x; cutoff=d.cutoff, poly_order=1, n_boot=30, rng=rng)
    r2  = rdd_fit(d.y, d.x; cutoff=d.cutoff, poly_order=2, n_boot=30, rng=rng)
    @test r1.bandwidth > 0.0
    @test r2.bandwidth > 0.0
    @test isfinite(r2.τ)
end

@testset "McCrary density test" begin
    d  = make_rdd_data()
    mt = mccrary_test(d.x; cutoff=d.cutoff)
    @test 0.0 <= mt.p_value <= 1.0
    @test mt.n_left > 0
    @test mt.n_right > 0
    # No sorting so should not reject
    @test mt.p_value > 0.01
end

@testset "Policy report" begin
    d    = make_panel()
    rng  = MersenneTwister(99)
    dr   = did_2x2(d.y, d.treat, d.post; unit_ids=d.unit_ids, n_boot=30, rng=rng)
    sd   = make_synth_data()
    sr   = synth_control(sd.Y_treated_pre, sd.Y_donors_pre,
                         sd.Y_treated_post, sd.Y_donors_post; n_placebo_iter=3)
    rpt  = policy_report(study_name="Test"; did_result=dr, synth_result=sr)
    @test rpt.method in (:did, :combined)
    @test isfinite(rpt.did_att)
end
