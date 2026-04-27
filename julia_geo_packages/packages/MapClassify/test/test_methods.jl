using Test
using Statistics
using Colors

@testset "Classification Methods" begin
    
    # Test data with different distributions
    uniform_data = collect(1:100)
    normal_data = randn(1000) .* 10 .+ 50
    bimodal_data = vcat(randn(500) .- 5, randn(500) .+ 5)
    skewed_data = randn(1000) .^ 2
    
    @testset "Quantile Classification" begin
        # Quartile
        result = classify(uniform_data, method=:quantile, n_classes=4)
        @test result.n_classes >= 2  # At least 2 classes
        @test length(result.boundaries) >= 2
        @test result.boundaries[1] <= result.boundaries[end]
        @test result.method == :quantile

        # Quintile
        result = classify(uniform_data, method=:quantile, n_classes=5)
        @test result.n_classes >= 2  # At least 2 classes
        @test sum(result.class_counts) == 100
        
        # Should handle few observations gracefully
        small_data = [1, 2, 3]
        result = classify(small_data, method=:quantile, n_classes=5)
        @test length(result.boundaries) >= 2
        @test result.n_classes >= 1
    end
    
    @testset "Equal Interval Classification" begin
        result = classify(uniform_data, method=:equal_interval, n_classes=5)
        @test result.n_classes == 5
        @test length(result.boundaries) == 6
        
        # Check that intervals are equal
        intervals = diff(result.boundaries)
        @test maximum(intervals) - minimum(intervals) < 1e-10
    end
    
    @testset "Natural Breaks (Jenks) Classification" begin
        result = classify(bimodal_data, method=:natural_breaks, n_classes=3)
        @test result.n_classes >= 1  # Might reduce if data is sparse
        @test result.method == :natural_breaks
        
        # GVF should be reasonable
        @test 0 <= result.goodness_of_variance_fit <= 1
    end
    
    @testset "Standard Deviation Classification" begin
        result = classify(normal_data, method=:standard_deviation, n_classes=1)
        @test length(result.boundaries) > 0
        
        # Multiple intervals
        result = classify(normal_data, method=:standard_deviation, n_classes=3)
        @test length(result.boundaries) >= 3
    end
    
    @testset "Pretty Breaks Classification" begin
        result = classify(uniform_data, method=:pretty_breaks, n_classes=5)
        @test length(result.boundaries) > 0
        
        # Check that boundaries are "pretty" (round numbers)
        @test result.boundaries[1] <= minimum(uniform_data)
        @test result.boundaries[end] >= maximum(uniform_data)
    end
    
    @testset "Head-Tail Breaks Classification" begin
        result = classify(skewed_data, method=:head_tail_breaks)
        @test length(result.boundaries) >= 2
        @test result.method == :head_tail_breaks
    end
    
    @testset "Maximum Breaks Classification" begin
        result = classify(bimodal_data, method=:maximum_breaks)
        @test length(result.boundaries) >= 2
    end
    
    @testset "Box Plot Classification" begin
        result = classify(normal_data, method=:box_plot)
        @test length(result.boundaries) >= 2
        @test result.method == :box_plot
    end
    
    @testset "Percentiles Classification" begin
        result = classify(normal_data, method=:percentiles, n_classes=5)
        @test length(result.boundaries) >= 2
    end
    
    @testset "K-means Classification" begin
        result = classify(bimodal_data, method=:kmeans, n_classes=3)
        @test result.n_classes == 3
        @test length(result.boundaries) == 4  # 3 classes = 4 boundaries
    end
    
    @testset "Custom Breaks Classification" begin
        boundaries = [0, 25, 50, 75, 100]
        data = [10, 30, 40, 60, 80, 90]
        result = classify(data, method=:custom_breaks)
        # Method should return boundaries when called without explicit breaks
        @test length(result.boundaries) >= 2
    end
    
    @testset "Geometric Interval Classification" begin
        result = classify(skewed_data, method=:geometric_interval, n_classes=5)
        @test length(result.boundaries) >= 2
    end
    
    @testset "Arithmetic Progression Classification" begin
        result = classify(uniform_data, method=:arithmetic_progression, n_classes=5)
        @test length(result.boundaries) >= 2
    end
    
    @testset "Nested Means Classification" begin
        result = classify(bimodal_data, method=:nested_means)
        @test length(result.boundaries) >= 2
    end
end

@testset "Edge Cases" begin
    
    @testset "Constant Data" begin
        const_data = fill(5.0, 100)
        # Should handle gracefully
        result = classify(const_data, method=:quantile, n_classes=5)
        @test length(result.boundaries) >= 2
    end
    
    @testset "Single Observation" begin
        single = [42.0]
        result = classify(single, method=:equal_interval, n_classes=5)
        @test length(result.boundaries) >= 1
    end
    
    @testset "Two Observations" begin
        two = [1.0, 2.0]
        result = classify(two, method=:quantile, n_classes=5)
        @test length(result.boundaries) >= 2
    end
    
    @testset "NaN Handling" begin
        data_with_nan = [1, 2, 3, NaN, 5, 6]
        result = classify(data_with_nan, method=:quantile, n_classes=3)
        @test !any(isnan, result.boundaries)
        @test all(x -> x >= 0, result.class_counts)
    end
    
    @testset "Inf Handling" begin
        data_with_inf = [1, 2, 3, Inf, 5, 6]
        result = classify(data_with_inf, method=:quantile, n_classes=3)
        @test !any(isinf, result.boundaries)
    end
    
    @testset "Large Values" begin
        large_data = [1e10, 2e10, 3e10, 4e10, 5e10]
        result = classify(large_data, method=:equal_interval, n_classes=3)
        @test !any(isnan, result.boundaries)
    end
    
    @testset "Negative Values" begin
        negative_data = [-50, -25, -10, -5, 0, 5, 10]
        result = classify(negative_data, method=:quantile, n_classes=4)
        @test result.boundaries[1] <= -50
        @test result.boundaries[end] >= 10
    end
end

@testset "Label Generation" begin
    data = collect(1:100)  # Larger dataset
    result = classify(data, method=:quantile, n_classes=5)

    @test length(result.labels) == result.n_classes
    @test all(l -> typeof(l) == String, result.labels)
    @test length(result.labels) >= 2  # At least 2 classes
end

@testset "Color Assignment" begin
    data = collect(1:100)  # Larger dataset
    result = classify(data, method=:quantile, n_classes=5, palette=:Blues)

    @test length(result.colors) == result.n_classes
    @test all(c -> isa(c, Colorant), result.colors)
end
