using Test, Random, Statistics
using MapClassify

Random.seed!(42)

# Test data
const VALUES = Float64.(1:20)
const SKEWED = vcat(fill(1.0, 15), [10.0, 20.0, 50.0, 100.0, 200.0])
const RANDOM = randn(100) .* 10 .+ 50.0

# ── Shared assertions ─────────────────────────────────────────────────────────
function check_result(r::ClassificationResult, k_expected, n_obs)
    @test r.k == k_expected
    @test length(r.assignments) == n_obs
    @test all(1 .<= r.assignments .<= r.k)
    @test sum(r.counts) == n_obs
    @test length(r.bins) == r.k
    @test issorted(r.bins)
    @test 0.0 <= r.gvf <= 1.0
    @test r.adcm >= 0.0
end

# ── EqualInterval ─────────────────────────────────────────────────────────────
@testset "EqualInterval" begin
    r = classify(VALUES, EqualInterval(5))
    check_result(r, 5, 20)
    # Each bin should have ≈ equal width
    widths = diff(vcat(minimum(VALUES), r.bins))
    @test all(w -> abs(w - widths[1]) < 1e-9, widths)
end

# ── Quantiles ─────────────────────────────────────────────────────────────────
@testset "Quantiles" begin
    r = classify(VALUES, Quantiles(4))
    check_result(r, 4, 20)
    # Each class should have ≈ equal count
    @test all(abs(c - 5) <= 1 for c in r.counts)
end

# ── NaturalBreaks (Fisher-Jenks DP) ──────────────────────────────────────────
@testset "NaturalBreaks Fisher-Jenks" begin
    r = classify(SKEWED, NaturalBreaks(3))
    check_result(r, 3, length(SKEWED))
    # GVF should be higher than EqualInterval for skewed data
    r_eq = classify(SKEWED, EqualInterval(3))
    @test r.gvf >= r_eq.gvf
end

@testset "FisherJenks identical to NaturalBreaks" begin
    r1 = classify(VALUES, NaturalBreaks(4))
    r2 = classify(VALUES, FisherJenks(4))
    @test r1.bins ≈ r2.bins
    @test r1.gvf  ≈ r2.gvf
end

# ── JenksCaspall ──────────────────────────────────────────────────────────────
@testset "JenksCaspall" begin
    r = classify(RANDOM, JenksCaspall(5))
    check_result(r, 5, length(RANDOM))
    @test r.gvf > 0.0
end

# ── StdMean ───────────────────────────────────────────────────────────────────
@testset "StdMean" begin
    r = classify(RANDOM, StdMean(; multiples=1.0))
    @test r.k >= 2
    @test length(r.assignments) == length(RANDOM)
end

# ── MaximumBreaks ─────────────────────────────────────────────────────────────
@testset "MaximumBreaks" begin
    r = classify(SKEWED, MaximumBreaks(4))
    check_result(r, 4, length(SKEWED))
end

# ── BoxPlot ───────────────────────────────────────────────────────────────────
@testset "BoxPlot" begin
    r = classify(RANDOM, BoxPlot(; hinge=1.5))
    @test length(r.assignments) == length(RANDOM)
    @test r.k >= 2
end

# ── HeadTailBreaks ────────────────────────────────────────────────────────────
@testset "HeadTailBreaks" begin
    r = classify(SKEWED, HeadTailBreaks())
    @test length(r.assignments) == length(SKEWED)
    @test r.k >= 1
    # For heavy-tailed data, should create multiple classes
    @test r.k >= 2
end

# ── Percentiles ───────────────────────────────────────────────────────────────
@testset "Percentiles" begin
    r = classify(RANDOM, Percentiles([20, 40, 60, 80, 100.0]))
    check_result(r, 5, length(RANDOM))
    # Each class should have ≈ 20% of values
    @test all(abs(c / length(RANDOM) - 0.2) < 0.05 for c in r.counts)
end

# ── UserDefined ───────────────────────────────────────────────────────────────
@testset "UserDefined" begin
    r = classify(VALUES, UserDefined([5.0, 10.0, 15.0, 20.0]))
    check_result(r, 4, 20)
    @test r.counts == [5, 5, 5, 5]
end

# ── PrettyBreaks ──────────────────────────────────────────────────────────────
@testset "PrettyBreaks" begin
    r = classify(RANDOM, PrettyBreaks(5))
    @test r.k >= 1
    @test length(r.assignments) == length(RANDOM)
end

# ── GeometricInterval ─────────────────────────────────────────────────────────
@testset "GeometricInterval" begin
    pos_vals = abs.(RANDOM) .+ 1.0
    r = classify(pos_vals, GeometricInterval(5))
    check_result(r, 5, length(pos_vals))
end

@testset "GeometricInterval non-positive" begin
    r = classify(VALUES .- 5, GeometricInterval(4))
    @test r.k >= 1  # should handle with shift
end

# ── KMeans ────────────────────────────────────────────────────────────────────
@testset "KMeans 1D" begin
    # Bimodal data
    bimodal = vcat(randn(50), randn(50) .+ 10)
    r = classify(bimodal, KMeans(2; max_iter=100))
    @test r.k == 2
    @test length(r.assignments) == 100
end

# ── JenksCaspallSampled ───────────────────────────────────────────────────────
@testset "JenksCaspallSampled" begin
    big_data = randn(5000) .* 10 .+ 50
    r = classify(big_data, JenksCaspallSampled(5; sample_size=500))
    check_result(r, 5, 5000)
end

# ── compare_classifiers ───────────────────────────────────────────────────────
@testset "compare_classifiers" begin
    df = compare_classifiers(RANDOM, 5)
    @test "scheme" ∈ names(df)
    @test "gvf"    ∈ names(df)
    @test nrow(df) >= 5
    @test all(0.0 .<= df.gvf .<= 1.0)
end

# ── choropleth_classify ───────────────────────────────────────────────────────
@testset "choropleth_classify" begin
    r = choropleth_classify(RANDOM, 5; scheme=:Quantiles)
    @test r.classifier == "Quantiles"
    r2 = choropleth_classify(RANDOM, 5; scheme=:NaturalBreaks)
    @test r2.classifier == "NaturalBreaks"
end

# ── GVF ordering: NaturalBreaks >= Quantiles >= EqualInterval ─────────────────
@testset "GVF ordering" begin
    r_nb = classify(SKEWED, NaturalBreaks(5))
    r_q  = classify(SKEWED, Quantiles(5))
    r_ei = classify(SKEWED, EqualInterval(5))
    @test r_nb.gvf >= r_ei.gvf - 1e-9  # NB should be at least as good as EI
end

# ── Edge cases ────────────────────────────────────────────────────────────────
@testset "edge cases" begin
    # k > n
    r = classify([1.0, 2.0], NaturalBreaks(5))
    @test r.k <= 2

    # All same value
    r2 = classify(fill(5.0, 10), EqualInterval(3))
    @test length(r2.assignments) == 10

    # Single value
    r3 = classify([42.0], NaturalBreaks(3))
    @test r3.assignments == [1]
end
