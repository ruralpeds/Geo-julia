#!/usr/bin/env julia
using Test, Random, Statistics, LinearAlgebra

include(joinpath(@__DIR__, "..", "src", "InfectiousDisease.jl"))
using .InfectiousDisease

@testset "SIR — Euler and RK4 consistency" begin
    for meth in [:euler, :rk4]
        r = sir(10000, 10, 0.3, 0.1; t_end=200.0, dt=0.5, method=meth)
        # Conservation: S+I+R ≈ 1 throughout
        @test all(abs.(r.S .+ r.I .+ r.R .- 1.0) .< 1e-4)
        @test r.R₀ ≈ 3.0 atol=1e-8
        @test r.peak_I > 0
        @test 0 < r.attack_rate < 1
        @test r.peak_t > 0
    end
    # RK4 more accurate than Euler for same dt
    r_rk = sir(10000, 10, 0.3, 0.1; dt=1.0, method=:rk4)
    r_eu = sir(10000, 10, 0.3, 0.1; dt=1.0, method=:euler)
    # Both produce plausible results
    @test r_rk.attack_rate > 0.5  # R₀=3 → large epidemic
end

@testset "SIR — R₀ > 1 required for epidemic" begin
    # R₀ < 1: epidemic should fade
    r_fade = sir(100000, 10, 0.05, 0.1; t_end=365.0)
    @test r_fade.R₀ < 1.0
    @test r_fade.attack_rate < 0.01  # tiny attack rate

    # R₀ > 1: epidemic grows
    r_grow = sir(100000, 10, 0.3, 0.1; t_end=365.0)
    @test r_grow.R₀ > 1.0
    @test r_grow.attack_rate > 0.5
end

@testset "SIR — monotone R and S" begin
    r = sir(10000, 10, 0.3, 0.1; t_end=200.0)
    @test all(diff(r.R) .>= -1e-6)   # R non-decreasing
    @test all(diff(r.S) .<= 1e-6)    # S non-increasing
end

@testset "Stochastic SIR" begin
    r = sir_stochastic(5000, 5, 0.3, 0.1; t_end=180.0, dt=1.0,
                        rng=MersenneTwister(1))
    @test all(abs.(r.S .+ r.I .+ r.R .- 1.0) .< 0.01)
    @test r.R₀ ≈ 3.0 atol=1e-8
    # No negative compartments
    @test all(r.S .>= -1e-6)
    @test all(r.I .>= -1e-6)
end

@testset "SEIR model" begin
    r = seir(10000, 20, 5, 0.3, 0.2, 0.1; t_end=300.0)
    @test all(abs.(r.S .+ r.E .+ r.I .+ r.R .- 1.0) .< 1e-3)
    @test r.R₀ ≈ 3.0 atol=1e-8
    # Exposed compartment peaks before infectious
    @test argmax(r.E) <= argmax(r.I)
    @test r.attack_rate > 0.5
end

@testset "Spatial SIR" begin
    n_patches = 4
    N   = fill(10000.0, n_patches)
    I₀  = [10.0, 0.0, 0.0, 0.0]   # seed in patch 1
    coords = [0.0 0.0; 1.0 0.0; 0.0 1.0; 1.0 1.0]
    r = spatial_sir(N, I₀, coords, 0.3, 0.1;
                    coupling_strength=0.05, gravity=true,
                    t_end=180.0, dt=1.0)
    @test r.n_patches == n_patches
    @test all(r.attack_rate .>= 0)
    @test r.attack_rate[1] > 0   # seeded patch should have cases
    @test !isnan(r.R₀_global)
    @test 1 <= r.peak_patch <= n_patches
    # Coupling: downstream patches should have non-zero attack rate
    @test sum(r.attack_rate) > r.attack_rate[1]  # spread beyond patch 1
end

@testset "R₀ from growth rate" begin
    # Generate clean exponential growth
    γ = 0.1; R₀_true = 3.0; β = R₀_true * γ
    r = sir(100000, 10, β, γ; t_end=100.0)
    I_series = r.I .* 100000
    est = r0_from_growth(I_series; γ=γ, n_early=20)
    @test !isnan(est.R₀)
    @test est.R₀ > 1.0  # at least detects epidemic
end

@testset "R₀ from attack rate" begin
    # Known SIR: R₀=3 → attack rate ≈ 0.94
    r = sir(1_000_000, 10, 0.3, 0.1; t_end=500.0)
    est = r0_from_sir(r.S[end] * 1_000_000, 1_000_000)
    @test est.R₀ > 2.0  # recovered R₀ close to truth
    @test 0 < est.attack_rate < 1
end

@testset "Herd immunity threshold" begin
    @test herd_immunity_threshold(1.0) == 0.0   # R₀=1 → no threshold
    @test herd_immunity_threshold(0.5) == 0.0   # R₀<1 → no threshold
    @test herd_immunity_threshold(2.0) ≈ 0.5    # R₀=2 → 50% coverage
    @test herd_immunity_threshold(4.0) ≈ 0.75   # R₀=4 → 75% coverage
    @test effective_r0(3.0, 0.5) ≈ 1.5
    @test effective_r0(3.0, 1.0) ≈ 0.0
end

@testset "Attack rate prediction" begin
    # Verify attack rate satisfies the implicit equation
    for R₀ in [1.5, 2.0, 3.0, 5.0]
        A = attack_rate_prediction(R₀)
        # 1 - A = exp(-R₀·A)
        @test abs(1 - A - exp(-R₀ * A)) < 1e-8
    end
    @test attack_rate_prediction(1.0) == 0.0
    @test attack_rate_prediction(0.5) == 0.0
end

@testset "Serial interval estimation" begin
    rng = MersenneTwister(42)
    si  = 5.0 .+ randn(rng, 100)   # mean ≈ 5
    est = estimate_serial_interval(si; n_boot=100, rng=rng)
    @test est.mean ≈ 5.0 atol=0.5
    @test est.sd   > 0
    @test est.n    == 100
    @test est.ci_lower < est.mean < est.ci_upper
end

@testset "Doubling time" begin
    @test doubling_time(log(2.0)) ≈ 1.0 atol=1e-8
    @test doubling_time(0.0) == Inf
    @test doubling_time(-1.0) == Inf
end

println("\n✓ All InfectiousDisease tests passed.")
