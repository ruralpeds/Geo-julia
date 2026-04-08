using Test, Random, Statistics
using PointPatterns

Random.seed!(42)
const W = RectWindow(0.0, 100.0, 0.0, 100.0)

# ── Helper: generate clustered pattern ────────────────────────────────────────
function clustered_pp(n_clusters=5, n_per_cluster=20; rng=MersenneTwister(1))
    xs = Float64[]; ys = Float64[]
    for _ in 1:n_clusters
        cx = 10.0 + rand(rng) * 80.0
        cy = 10.0 + rand(rng) * 80.0
        for _ in 1:n_per_cluster
            push!(xs, clamp(cx + randn(rng)*5, 0, 100))
            push!(ys, clamp(cy + randn(rng)*5, 0, 100))
        end
    end
    PointPattern(xs, ys, W)
end

function csr_pp(n=100; rng=MersenneTwister(2))
    PointPattern(rand(rng, n) .* 100, rand(rng, n) .* 100, W)
end

# ── Types ─────────────────────────────────────────────────────────────────────
@testset "PointPattern construction" begin
    pp = PointPattern([1.0,2.0,3.0], [4.0,5.0,6.0], W)
    @test pp.n == 3
    @test pp.x == [1.0, 2.0, 3.0]
    @test intensity(pp) > 0.0

    @test_throws DimensionMismatch PointPattern([1.0,2.0], [3.0], W)
end

@testset "RectWindow" begin
    w = RectWindow(0.0, 10.0, 0.0, 10.0)
    @test area(w) ≈ 100.0
    @test perimeter(w) ≈ 40.0
    @test inside((5.0, 5.0), w)
    @test !inside((15.0, 5.0), w)
    @test_throws ErrorException RectWindow(10.0, 5.0, 0.0, 10.0)
end

@testset "simulate_csr" begin
    pp = simulate_csr(0.01, W)  # λ=0.01, A=10000, E[n]=100
    @test pp.n > 0
    @test all(inside.(zip(pp.x, pp.y), Ref(W)))
end

# ── CSR Tests ─────────────────────────────────────────────────────────────────
@testset "quadrat_test CSR data" begin
    pp = csr_pp(500)
    r = quadrat_test(pp; nx=5, ny=5)
    @test r.chi2 >= 0.0
    @test 0.0 <= r.p_value <= 1.0
    @test r.n_quadrats == 25
    # CSR should not be rejected at α=0.001
    @test r.p_value > 0.001
end

@testset "quadrat_test clustered data" begin
    pp = clustered_pp(3, 30)
    r = quadrat_test(pp)
    @test r.chi2 >= 0.0
end

@testset "clarkevans_test CSR" begin
    pp = csr_pp(200)
    r = clarkevans_test(pp)
    @test 0.0 <= r.p_value <= 1.0
    @test r.d_observed > 0
    # CSR: R should be ≈ 1
    @test 0.3 <= r.R <= 2.0
end

@testset "clarkevans_test clustered" begin
    pp = clustered_pp(4, 25)
    r = clarkevans_test(pp)
    @test r.R < 1.0   # clustered → R < 1
end

# ── K-function ────────────────────────────────────────────────────────────────
@testset "Kfunction CSR" begin
    pp = csr_pp(200)
    df = Kfunction(pp; correction=:ripley)
    @test "r" ∈ names(df) && "K" ∈ names(df) && "L" ∈ names(df)
    @test all(df.K .>= 0.0)
    @test all(df.L .>= 0.0)
    @test all(df.K_csr .>= 0.0)
    # For CSR, K ≈ πr²; allow 3× tolerance due to variance
    mid_idx = div(nrow(df), 2)
    @test df.K[mid_idx] < 4 * df.K_csr[mid_idx] + 1.0
end

@testset "Kfunction clustered > CSR envelope" begin
    pp = clustered_pp(5, 20)
    df = Kfunction(pp)
    # Clustered pattern: K should exceed K_csr at some r values
    @test any(df.K .> df.K_csr)
end

@testset "envelope" begin
    pp = csr_pp(100)
    env = envelope(pp, Kfunction; nsim=19)
    @test "K_obs" ∈ names(env)
    @test "K_lo"  ∈ names(env)
    @test "K_hi"  ∈ names(env)
    @test all(env.K_lo .<= env.K_hi)
end

# ── G/F/J functions ───────────────────────────────────────────────────────────
@testset "Gfunction" begin
    pp = csr_pp(150)
    df = Gfunction(pp)
    @test "G" ∈ names(df)
    @test all(0.0 .<= df.G .<= 1.0)
    @test issorted(df.G)  # CDF is monotone non-decreasing
end

@testset "Ffunction" begin
    pp = csr_pp(100)
    df = Ffunction(pp; n_ref=200)
    @test "F" ∈ names(df)
    @test all(0.0 .<= df.F .<= 1.0)
end

@testset "Jfunction" begin
    pp = csr_pp(100)
    df = Jfunction(pp; n_ref=200)
    @test "J" ∈ names(df)
    # CSR: J ≈ 1 at most r values
    mid = df.J[div(nrow(df), 2)]
    @test 0.0 <= mid <= 5.0
end

# ── Intensity estimation ──────────────────────────────────────────────────────
@testset "kernel_intensity" begin
    pp = csr_pp(200)
    ki = kernel_intensity(pp; grid_n=20)
    @test size(ki.lambda) == (20, 20)
    @test all(ki.lambda .>= 0.0)
    @test ki.bandwidth > 0.0
end

@testset "adaptive_intensity" begin
    pp = csr_pp(100)
    ai = adaptive_intensity(pp; k=5)
    @test length(ai.lambda_at_events) == 100
    @test all(ai.bandwidths .> 0)
end

# ── Nearest neighbour statistics ─────────────────────────────────────────────
@testset "nndist" begin
    pp = PointPattern([0.0, 1.0, 3.0], [0.0, 0.0, 0.0], W)
    d = nndist(pp)
    @test length(d) == 3
    @test d[1] ≈ 1.0
    @test d[2] ≈ 1.0
    @test d[3] ≈ 2.0
end

@testset "nnwhich" begin
    pp = PointPattern([0.0, 1.0, 5.0], [0.0, 0.0, 0.0], W)
    w = nnwhich(pp)
    @test length(w) == 3
    @test w[1] == 2  # nearest to point 1 is point 2
    @test w[2] == 1  # nearest to point 2 is point 1
end

@testset "pairdist" begin
    pp = PointPattern([0.0, 3.0, 4.0], [0.0, 4.0, 0.0], W)
    D = pairdist(pp)
    @test size(D) == (3, 3)
    @test all(diag(D) .≈ 0.0)
    @test D ≈ D'  # symmetric
    @test D[1,2] ≈ 5.0  # 3-4-5 triangle
end

# ── Kulldorff scan statistic ─────────────────────────────────────────────────
@testset "scan_statistic detects injected cluster" begin
    n = 53   # North Dakota county count
    pop  = 1000 .+ rand(MersenneTwister(7), n) .* 5000
    # Null: cases ∝ population (no cluster)
    expected_rates = fill(0.01, n)
    cases = round.(Int, pop .* expected_rates)

    # Inject a cluster in areas 10-15: 3× elevated rate
    for i in 10:15
        cases[i] = round(Int, pop[i] * 0.03)
    end

    coords = hcat(rand(MersenneTwister(8), n) .* 400, rand(MersenneTwister(9), n) .* 300)

    result = scan_statistic(cases, Float64.(pop), coords;
                             max_pop_fraction=0.3, nsim=99, rng=MersenneTwister(10))

    @test result.llr > 0.0
    @test 0.0 <= result.p_value <= 1.0
    @test length(result.included_areas) >= 1
    # The injected cluster should have elevated relative risk
    @test result.relative_risk > 1.0
end

@testset "scan_statistic null data" begin
    n = 30
    pop   = fill(1000.0, n)
    cases = fill(10, n)  # uniform rate, no cluster
    coords = hcat(rand(n) .* 100, rand(n) .* 100)

    result = scan_statistic(cases, pop, coords; nsim=49)
    @test 0.0 <= result.p_value <= 1.0
end
