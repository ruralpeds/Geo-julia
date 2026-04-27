"""
test_kdtree_2sfca.jl

Test suite for kdtree_2sfca — KD-tree spatial indexing for 2SFCA accessibility.

Phase IV-V (Days 56-57): Performance optimization
- KD-tree spatial binning for 2SFCA
- Correctness validation vs naive implementation
- Scaling analysis
- Edge case handling
"""

using Test
using Random

Random.seed!(42)

# Naive reference implementation for validation
function naive_2sfca(providers::Matrix{Float64}, provider_capacity::Vector{Float64},
                     population::Matrix{Float64}, bandwidth_km::Float64)::Vector{Float64}
    n_providers = size(providers, 1)
    m_population = size(population, 1)
    accessibility = zeros(m_population)

    for i = 1:m_population
        for j = 1:n_providers
            lat_diff = (providers[j, 1] - population[i, 1]) * 111.0
            lon_diff = (providers[j, 2] - population[i, 2]) * 111.0
            dist = sqrt(lat_diff^2 + lon_diff^2)

            if dist <= bandwidth_km
                accessibility[i] += provider_capacity[j]
            end
        end
    end

    return accessibility
end

@testset "KD-Tree 2SFCA Optimization" begin

    # Test setup: small dataset
    n_providers = 100
    m_population = 500
    providers = rand(n_providers, 2) .* transpose([20, 30]) .+ transpose([30, 70])
    provider_supply = rand(n_providers) .* 100 .+ 10
    population = rand(m_population, 2) .* transpose([20, 30]) .+ transpose([30, 70])
    bandwidth_km = 60.0

    @testset "kdtree_2sfca — function executes" begin
        result = kdtree_2sfca(providers, provider_supply, population, bandwidth_km)
        @test !isnothing(result)
        @test length(result) == m_population
    end

    @testset "kdtree_2sfca — output shape and type" begin
        result = kdtree_2sfca(providers, provider_supply, population, bandwidth_km)
        @test isa(result, Vector{Float64})
        @test length(result) == m_population
    end

    @testset "kdtree_2sfca — accessibility non-negative" begin
        result = kdtree_2sfca(providers, provider_supply, population, bandwidth_km)
        @test all(result .>= 0)  # Accessibility scores should be non-negative
    end

    @testset "kdtree_2sfca — no NaN values" begin
        result = kdtree_2sfca(providers, provider_supply, population, bandwidth_km)
        @test !any(isnan.(result))
    end

    @testset "kdtree_2sfca — correctness vs naive implementation" begin
        # Small dataset for comprehensive comparison
        result_kdtree = kdtree_2sfca(providers, provider_supply, population, bandwidth_km)
        result_naive = naive_2sfca(providers, provider_supply, population, bandwidth_km)

        # Should match within floating-point tolerance
        @test isapprox(result_kdtree, result_naive; atol=1e-6)
    end

    @testset "kdtree_2sfca — max difference vs naive <1e-6" begin
        result_kdtree = kdtree_2sfca(providers, provider_supply, population, bandwidth_km)
        result_naive = naive_2sfca(providers, provider_supply, population, bandwidth_km)

        max_diff = maximum(abs.(result_kdtree .- result_naive))
        @test max_diff < 1e-6
    end

    @testset "kdtree_2sfca — mean values close" begin
        result_kdtree = kdtree_2sfca(providers, provider_supply, population, bandwidth_km)
        result_naive = naive_2sfca(providers, provider_supply, population, bandwidth_km)

        mean_kdtree = mean(result_kdtree)
        mean_naive = mean(result_naive)

        @test isapprox(mean_kdtree, mean_naive; rtol=1e-5)
    end

    @testset "kdtree_2sfca — single provider edge case" begin
        # Single provider, single population point
        providers_single = [40.0 -100.0]
        supply_single = [50.0]
        pop_single = [40.1 -100.0]

        result = kdtree_2sfca(providers_single, supply_single, pop_single, 20.0)

        @test length(result) == 1
        @test result[1] ≈ 50.0  # Single provider fully accessible
    end

    @testset "kdtree_2sfca — very small bandwidth" begin
        # Small bandwidth: most providers beyond reach
        result = kdtree_2sfca(providers, provider_supply, population, 0.1)

        @test all(result .>= 0)
        @test !any(isnan.(result))
        # Many zeros expected
        @test count(==(0), result) > m_population / 2
    end

    @testset "kdtree_2sfca — very large bandwidth" begin
        # Large bandwidth: all providers accessible
        result = kdtree_2sfca(providers, provider_supply, population, 10000.0)

        @test all(result .> 0)  # All should have some access
        # All should be ~same (sum of all supplies)
        total_supply = sum(provider_supply)
        @test all(isapprox.(result, total_supply; rtol=0.01))
    end

    @testset "kdtree_2sfca — scaling: medium dataset" begin
        # Medium dataset (1000 providers, 3000 pop)
        n_med = 1000
        m_med = 3000

        providers_med = rand(n_med, 2)
        supply_med = rand(n_med)
        pop_med = rand(m_med, 2)

        result = kdtree_2sfca(providers_med, supply_med, pop_med, 0.5)

        @test length(result) == m_med
        @test all(isfinite.(result))
    end

end  # @testset

# Include in main test suite
@testset "KD-Tree 2SFCA Optimization Suite" begin
    # Re-run main tests
    include("test_kdtree_2sfca.jl")
end
