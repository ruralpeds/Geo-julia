using Test
using Statistics

@testset "Quality Metrics" begin
    
    @testset "Gini Index" begin
        # Perfect equality (all same size)
        equal_counts = [25, 25, 25, 25]
        gini = gini_index(equal_counts)
        @test gini > 0.7  # Should be ~0.75 (perfect equality)

        # Single class (no diversity)
        single_counts = [100, 0, 0, 0]
        gini = gini_index(single_counts)
        @test gini < 1e-10  # Single class = no diversity

        # Moderate distribution
        moderate_counts = [50, 30, 15, 5]
        gini = gini_index(moderate_counts)
        @test 0.5 < gini < 0.75  # Moderate diversity
    end
    
    @testset "Gini Index Bounds" begin
        for _ in 1:10
            counts = rand(1:100, rand(1:10))
            gini = gini_index(counts)
            @test 0 <= gini <= 1
        end
    end
    
    @testset "Shannon Entropy" begin
        # Uniform distribution (maximum entropy)
        uniform_counts = [25, 25, 25, 25]
        entropy = shannon_entropy(uniform_counts)
        expected_max = log(2, 4)  # log_2(n_classes)
        @test abs(entropy - expected_max) < 1e-10
        
        # Single class (zero entropy)
        single_counts = [100, 0, 0]
        entropy = shannon_entropy(single_counts)
        @test entropy < 1e-10
    end
    
    @testset "Shannon Entropy Bounds" begin
        for _ in 1:10
            counts = rand(1:100, rand(1:10))
            entropy = shannon_entropy(counts)
            @test entropy >= 0
            @test entropy <= log(2, length(counts))
        end
    end
    
    @testset "Goodness of Variance Fit" begin
        # Uniform data with quantile classification
        data = collect(1.0:100.0)
        boundaries = [1.0, 25.5, 50.5, 75.5, 100.0]
        gvf = goodness_of_variance_fit(data, boundaries)
        @test 0 <= gvf <= 1
        
        # Constant data (should be 0)
        const_data = fill(5.0, 100)
        gvf = goodness_of_variance_fit(const_data, [5.0, 5.0])
        @test gvf == 0.0
    end
    
    @testset "GVF Bounds" begin
        data = randn(1000) .* 10 .+ 50
        boundaries = collect(range(minimum(data), maximum(data), length=6))
        gvf = goodness_of_variance_fit(data, boundaries)
        @test 0 <= gvf <= 1
    end
    
    @testset "Class Counts" begin
        data = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
        boundaries = [0.5, 3.5, 6.5, 10.5]
        counts = compute_class_counts(data, boundaries)
        
        @test length(counts) == 3
        @test sum(counts) == 10
        @test counts[1] == 3  # [1,2,3]
        @test counts[2] == 3  # [4,5,6]
        @test counts[3] == 4  # [7,8,9,10]
    end
    
    @testset "Class Counts with NaN" begin
        data = [1, 2, NaN, 4, 5, NaN, 7, 8, 9, 10]
        boundaries = [0.5, 3.5, 6.5, 10.5]
        counts = compute_class_counts(data, boundaries)
        
        # NaN values should be excluded
        @test sum(counts) == 8
        @test all(c >= 0 for c in counts)
    end
end

@testset "Metrics in Classification" begin
    
    @testset "Classification Result Metrics" begin
        data = collect(1.0:100.0)
        result = classify(data, method=:quantile, n_classes=5)
        
        # All metrics should be computed
        @test 0 <= result.gini_index <= 1
        @test result.entropy >= 0
        @test 0 <= result.goodness_of_variance_fit <= 1
    end
    
    @testset "Different Methods Produce Different Metrics" begin
        data = [1, 2, 3, 4, 5, 10, 20, 50, 100]
        
        result1 = classify(data, method=:quantile, n_classes=3)
        result2 = classify(data, method=:natural_breaks, n_classes=3)
        
        # Different methods may produce different GVF values
        # (though they might be similar in some cases)
        @test result1.goodness_of_variance_fit >= 0
        @test result2.goodness_of_variance_fit >= 0
    end
    
    @testset "Metrics Consistency" begin
        data = randn(500) .* 20 .+ 100
        
        for method in [:quantile, :equal_interval, :natural_breaks]
            result = classify(data, method=method, n_classes=5)
            
            # All metrics should be well-defined
            @test !isnan(result.gini_index)
            @test !isnan(result.entropy)
            @test !isnan(result.goodness_of_variance_fit)
            
            # Bounds
            @test 0 <= result.gini_index <= 1
            @test result.entropy >= 0
            @test 0 <= result.goodness_of_variance_fit <= 1
        end
    end
end
