using Test
using DataFrames, LinearAlgebra, Statistics, Random

# Load the package under test
using HealthcareGeo

Random.seed!(42)

# ──────────────────────────────────────────────────────────────────────────────
# haversine
# ──────────────────────────────────────────────────────────────────────────────
@testset "haversine" begin
    # New York City → Los Angeles: approximately 3,944 km
    nyc = (40.7128, -74.0060)
    lax = (34.0522, -118.2437)
    d   = haversine(nyc, lax)
    @test isapprox(d, 3944.0; atol = 20.0)   # within 20 km

    # Same point → 0
    @test haversine(nyc, nyc) ≈ 0.0 atol = 1e-6

    # Near-poles sanity check (symmetric)
    p1 = (0.0,   0.0)
    p2 = (0.0, 180.0)
    @test haversine(p1, p2) ≈ haversine(p2, p1)
end

# ──────────────────────────────────────────────────────────────────────────────
# compute_morans_i
# ──────────────────────────────────────────────────────────────────────────────
@testset "compute_morans_i" begin
    # Perfect positive spatial autocorrelation: identical neighbours
    # Build a 1-D chain: 1 2 3 4 1 2 3 4 — strong clustering
    n   = 8
    val = Float64[1, 1, 1, 1, 9, 9, 9, 9]     # two blocks → high I
    W   = zeros(n, n)
    for i in 1:n
        if i > 1; W[i, i-1] = 1.0; end
        if i < n; W[i, i+1] = 1.0; end
    end
    # Row-standardise
    rs = sum(W; dims = 2)
    W  = W ./ (rs .+ 1e-12)

    res = compute_morans_i(val, W; permutations = 199)
    @test res.I > 0.5                           # strong positive autocorrelation
    @test res.p_value < 0.1

    # Uniform values → I should be ~0 (or trivially 0)
    val_flat = fill(5.0, n)
    res2 = compute_morans_i(val_flat, W; permutations = 99)
    @test res2.I ≈ 0.0 atol = 1e-6
end

# ──────────────────────────────────────────────────────────────────────────────
# classify_rural_forhp
# ──────────────────────────────────────────────────────────────────────────────
@testset "classify_rural_forhp" begin
    tracts = DataFrame(
        fips               = ["38001000100", "38001000200", "38001000300",
                              "38001000400", "38001000500"],
        ruca_code          = [1, 5, 2, 3, 3],
        rrs_code           = [1, 1, 1, 5, 5],
        omb_metro_type     = ["nonmetro", "metro", "metro", "metro", "metro"],
        area_sq_mi         = [100.0, 50.0, 500.0, 10.0, 30.0],
        population_density = [20.0, 100.0, 30.0, 50.0, 20.0],
    )

    result = classify_rural_forhp(tracts)

    @test result.is_rural_forhp[1] == true    # Rule 1: nonmetro
    @test result.is_rural_forhp[2] == true    # Rule 2: RUCA 5 in metro
    @test result.is_rural_forhp[3] == true    # Rule 3: RUCA 2, area 500, density 30
    @test result.is_rural_forhp[4] == false   # RUCA 3 but area < 20
    @test result.is_rural_forhp[5] == true    # Rule 4: RUCA 3, RRS=5, area 30 >= 20
end

# ──────────────────────────────────────────────────────────────────────────────
# two_step_fca
# ──────────────────────────────────────────────────────────────────────────────
@testset "two_step_fca" begin
    # 3 providers, 5 population locations within 200 km of each other
    providers = DataFrame(
        lat    = [46.5, 47.0, 46.8],
        lon    = [-97.0, -98.5, -96.5],
        supply = [2.0, 1.0, 3.0],
    )
    pop_locs = DataFrame(
        id         = ["A", "B", "C", "D", "E"],
        lat        = [46.5, 46.9, 47.1, 46.3, 47.3],
        lon        = [-97.0, -98.0, -97.5, -96.8, -98.2],
        population = [1000.0, 2000.0, 500.0, 1500.0, 800.0],
    )

    result = two_step_fca(providers, pop_locs, 200.0)

    @test nrow(result) == 5
    @test all(result.accessibility .>= 0.0)
    @test "accessibility" in names(result)
    @test "id" in names(result)
end

# ──────────────────────────────────────────────────────────────────────────────
# Spatial weights matrices
# ──────────────────────────────────────────────────────────────────────────────
@testset "build_knn_weights" begin
    coords = Float64[
        46.0 -97.0;
        46.5 -97.0;
        47.0 -97.0;
        47.5 -97.0;
        48.0 -97.0;
    ]
    W = build_knn_weights(coords, 2)
    @test size(W) == (5, 5)
    @test all(W .>= 0.0)
    row_sums = sum(W; dims = 2)
    # Each row with at least one neighbour should sum to 1
    @test all(isapprox.(row_sums, 1.0; atol = 1e-9) .| isapprox.(row_sums, 0.0; atol = 1e-9))
end

@testset "build_distance_band_weights" begin
    coords = Float64[
        46.0 -97.0;
        46.1 -97.0;
        50.0 -110.0;   # far away
    ]
    W = build_distance_band_weights(coords; bandwidth_km = 20.0)
    @test W[1, 2] > 0.0    # close pair → neighbours
    @test W[1, 3] ≈ 0.0    # distant pair → not neighbours
end

# ──────────────────────────────────────────────────────────────────────────────
# e2sfca decay functions
# ──────────────────────────────────────────────────────────────────────────────
@testset "e2sfca decay variants" begin
    providers = DataFrame(lat=[46.5], lon=[-97.0], supply=[10.0])
    pop_locs  = DataFrame(
        id         = ["A"],
        lat        = [46.5],
        lon        = [-97.0],
        population = [1000.0],
    )
    for decay in (:gaussian, :linear, :inverse, :kernel)
        res = e2sfca(providers, pop_locs, 100.0; decay = decay)
        @test res.accessibility[1] >= 0.0
    end
end

# ──────────────────────────────────────────────────────────────────────────────
# gravity_accessibility
# ──────────────────────────────────────────────────────────────────────────────
@testset "gravity_accessibility" begin
    providers = DataFrame(lat=[46.5, 47.0], lon=[-97.0, -98.0], supply=[5.0, 3.0])
    pop_locs  = DataFrame(
        id         = ["X", "Y"],
        lat        = [46.5, 47.0],
        lon        = [-97.0, -98.0],
        population = [1000.0, 500.0],
    )
    res = gravity_accessibility(providers, pop_locs; beta = 2.0)
    @test nrow(res) == 2
    @test all(res.accessibility .>= 0.0)
end

# ──────────────────────────────────────────────────────────────────────────────
# lisa_clusters
# ──────────────────────────────────────────────────────────────────────────────
@testset "lisa_clusters" begin
    n   = 6
    val = Float64[10, 10, 10, 1, 1, 1]   # two clear blocks
    W   = zeros(n, n)
    for i in 1:n, j in 1:n
        i == j && continue
        W[i, j] = abs(i - j) == 1 ? 1.0 : 0.0
    end
    rs = sum(W; dims = 2); W = W ./ (rs .+ 1e-12)

    clusters = lisa_clusters(val, W; permutations = 199, alpha = 0.05)
    @test length(clusters) == n
    @test all(c in ("HH", "LL", "HL", "LH", "NS") for c in clusters)
end

# ──────────────────────────────────────────────────────────────────────────────
# gwr — basic smoke test
# ──────────────────────────────────────────────────────────────────────────────
@testset "gwr" begin
    n      = 20
    rng    = MersenneTwister(1)
    coords = hcat(46.0 .+ rand(rng, n), -97.0 .+ rand(rng, n))
    X      = hcat(ones(n), rand(rng, n, 2))
    β_true = [1.0, 2.0, -1.5]
    y      = X * β_true .+ 0.1 .* randn(rng, n)

    df = gwr(y, X, coords; bandwidth_km = 200.0, kernel = :bisquare)
    @test nrow(df) == n
    @test "beta_1" in names(df)
    @test "local_r2" in names(df)
    @test all(df.local_r2 .>= -0.1)   # allow small numerical slack
end
