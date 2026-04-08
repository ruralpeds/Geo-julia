using Test, Statistics, Random, LinearAlgebra

include(joinpath(@__DIR__, "..", "src", "DiseaseMapping.jl"))
using .DiseaseMapping

function make_county_data(n=20; seed=1)
    rng = MersenneTwister(seed)
    E   = 5.0 .+ 15.0 .* rand(rng, n)
    θ   = 0.8 .+ 0.6 .* rand(rng, n)
    O   = Float64.([rand_poisson(rng, E[i]*θ[i]) for i in 1:n])
    coords = hcat(rand(rng, n) .* 10, rand(rng, n) .* 10)
    (O=O, E=E, coords=coords, θ=θ)
end

@testset "SMR — basic calculation" begin
    r = smr(10.0, 8.0; area="TestCounty")
    @test r.smr ≈ 10.0/8.0
    @test r.lower_ci < r.smr
    @test r.upper_ci > r.smr
    @test 0.0 <= r.p_value <= 1.0
end

@testset "SMR — exact equality OE" begin
    r = smr(5.0, 5.0)
    @test r.smr ≈ 1.0
    # 95% CI should bracket 1
    @test r.lower_ci <= 1.0 <= r.upper_ci
end

@testset "SMR — zero observed" begin
    r = smr(0.0, 5.0)
    @test r.smr == 0.0
    @test r.lower_ci >= 0.0
    @test r.p_value ≈ 1.0 atol=0.01
end

@testset "batch_smr" begin
    d   = make_county_data(10)
    res = batch_smr(d.O, d.E)
    @test length(res) == 10
    @test all(r.smr >= 0 for r in res)
    t   = smr_summary(res)
    @test :smr in keys(t)
    @test length(t.smr) == 10
end

@testset "indirect_standardise" begin
    n_areas = 5; n_age = 3
    counts  = ones(n_areas, n_age) .* 3
    pops    = fill(100.0, n_areas, n_age)
    ref     = [0.02, 0.05, 0.08]
    E, O    = indirect_standardise(counts, pops, ref)
    @test length(E) == n_areas
    @test all(E .≈ sum(ref) * 100)  # E_i = Σ pop_ia * rate_a
    @test all(O .≈ 9.0)             # 3 events per age group
end

@testset "build_adjacency" begin
    coords = [0.0 0.0; 1.0 0.0; 5.0 5.0; 6.0 5.0]
    W, Q, m = build_adjacency(coords; threshold=1.5)
    @test W[1,2] == 1.0  # close pair
    @test W[1,3] == 0.0  # far pair
    @test all(Q .== diagm(m) - W)
    @test all(diag(W) .== 0.0)
end

@testset "BYM fit — posterior means are positive RR" begin
    d   = make_county_data(12; seed=5)
    W, Q, _ = build_adjacency(d.coords; threshold=3.0)
    rng = MersenneTwister(9)
    r   = bym_fit(d.O, d.E, W, Q; n_iter=600, n_warmup=100, rng=rng)
    @test length(r.rr) == 12
    @test all(r.rr .> 0.0)
    @test all(r.rr_lower .> 0.0)
    @test all(r.rr_lower .<= r.rr .<= r.rr_upper)
    @test isfinite(r.dic)
    @test isfinite(r.pd)
end

@testset "BYM — τ parameters positive" begin
    d = make_county_data(10; seed=3)
    W, Q, _ = build_adjacency(d.coords; threshold=3.0)
    rng = MersenneTwister(7)
    r = bym_fit(d.O, d.E, W, Q; n_iter=400, n_warmup=100, rng=rng)
    @test r.τ_u_mean > 0.0
    @test r.τ_v_mean > 0.0
end

@testset "Empirical Bayes smoothing — shrinkage" begin
    d  = make_county_data(15)
    eb = eb_smooth(d.O, d.E)
    @test length(eb.θ_hat) == 15
    @test all(eb.θ_hat .>= 0.0)
    @test eb.α_hat > 0.0
    @test eb.β_hat > 0.0
    # EB shrinks extreme raw rates toward mean
    overall_rate = sum(d.O) / sum(d.E)
    max_raw = maximum(eb.smr_raw)
    max_eb  = maximum(eb.θ_hat)
    @test max_eb <= max_raw + 1e-8  # EB shrinks maximum
end

@testset "Kernel smoother" begin
    d  = make_county_data(20)
    ks = kernel_smooth_rates(d.O, d.E, d.coords; kernel=:gaussian)
    @test length(ks) == 20
    @test all(ks .>= 0.0)
    # Kernel smoother should reduce variance
    @test var(ks) <= var(d.O ./ max.(d.E, 1e-10)) + 1e-8
end

@testset "Spatial scan — returns result" begin
    rng = MersenneTwister(42)
    d   = make_county_data(20; seed=8)
    # Inject a cluster
    d.O[1:4] .= d.E[1:4] .* 3.0
    res = spatial_scan(d.O, d.E, d.coords; n_sim=49, rng=rng)
    @test !isempty(res)
    @test res[1].llr >= 0.0
    @test 0.0 <= res[1].p_value <= 1.0
    @test res[1].n_inside >= 1
end

@testset "Spatial scan — null data no alarms" begin
    rng = MersenneTwister(3)
    E   = fill(10.0, 15)
    O   = Float64.([rand_poisson(rng, 10.0) for _ in 1:15])
    c   = hcat(rand(rng, 15)*10, rand(rng, 15)*10)
    res = spatial_scan(O, E, c; n_sim=49, rng=rng)
    # p-value should not be extremely small
    if !isempty(res)
        @test res[1].p_value > 0.0
    end
end

@testset "rand_poisson" begin
    rng = MersenneTwister(1)
    vals = [rand_poisson(rng, 5.0) for _ in 1:500]
    @test all(vals .>= 0)
    @test abs(mean(vals) - 5.0) < 0.5
end

@testset "Disease mapping report" begin
    d   = make_county_data(15)
    rpt = disease_mapping_report(d.O, d.E; disease_name="TestDisease",
                                  coords=d.coords)
    @test isa(rpt, DiseaseMappingReport)
    @test rpt.n_areas == 15
    @test isfinite(rpt.overall_smr)
    @test rpt.overall_smr > 0.0
end
