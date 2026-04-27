using Geostatistics
using Test
using Random

@testset "Geostatistics.jl — Days 6-12: Kriging & Variography" begin

    @testset "Days 6-7: Empirical Variogram & Model Fitting" begin
        include("test_variography.jl")
    end

    @testset "Days 8-10: Ordinary Kriging" begin
        include("test_ordinary_kriging.jl")
    end

    @testset "Days 11-12: Validation & Diagnostics" begin
        include("test_validation.jl")
    end

    @testset "Phase 2 Optimization: Batch Kriging" begin
        include("test_batch_kriging.jl")
    end

    @testset "Phase 2 Optimization: Vectorized Distance Computation" begin
        include("test_vectorized_distances.jl")
    end

end
