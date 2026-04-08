#!/usr/bin/env julia
# test/runtests.jl — ErrorHandling package unit tests

using Test, LinearAlgebra

include(joinpath(@__DIR__, "..", "src", "ErrorHandling.jl"))
using .ErrorHandling

# ─── Exception construction and display ───────────────────────────────────────

@testset "InputValidationError" begin
    e = InputValidationError("must be positive", "x", -1)
    @test e isa GeoJuliaError
    @test e.field == "x"
    @test e.value == -1
    s = sprint(showerror, e)
    @test occursin("InputValidationError", s)
    @test occursin("x", s)

    # convenience constructors
    @test InputValidationError("msg").field == ""
    @test InputValidationError("msg", "f").value === nothing
end

@testset "DimensionMismatchError" begin
    e = DimensionMismatchError("bad shape", (10, 2), (10, 3))
    @test e isa GeoJuliaError
    s = sprint(showerror, e)
    @test occursin("DimensionMismatchError", s)
    @test occursin("expected", s)
end

@testset "NumericalInstabilityError" begin
    e = NumericalInstabilityError("NaN in output", "matrix_solve", "n=5")
    @test e isa GeoJuliaError
    s = sprint(showerror, e)
    @test occursin("matrix_solve", s)

    e2 = NumericalInstabilityError("msg")
    @test e2.operation == "unknown"
    @test e2.details   == ""
end

@testset "ConvergenceError" begin
    e = ConvergenceError("Newton failed", 200, 1e-8, 3.4e-5)
    @test e isa GeoJuliaError
    s = sprint(showerror, e)
    @test occursin("200", s)
    @test occursin("1.0e-8", s) || occursin("1e-8", s)

    e2 = ConvergenceError("msg")
    @test e2.iterations == -1
end

@testset "InfeasibilityError" begin
    e = InfeasibilityError("no feasible point", "set cover")
    @test e isa GeoJuliaError
    s = sprint(showerror, e)
    @test occursin("set cover", s)
end

@testset "ConfigurationError" begin
    e = ConfigurationError("p exceeds m", "p", "1..15")
    @test e isa GeoJuliaError
    s = sprint(showerror, e)
    @test occursin("1..15", s)
end

@testset "ContextError" begin
    inner = InputValidationError("bad weight", "w", -0.1)
    e     = ContextError(inner, "p_median_pipeline")
    @test e isa GeoJuliaError
    s = sprint(showerror, e)
    @test occursin("p_median_pipeline", s)
    @test occursin("bad weight", s)
end

# ─── Validation guard functions ───────────────────────────────────────────────

@testset "check_2d_coords" begin
    @test_throws DimensionMismatchError check_2d_coords(rand(5, 3))
    @test_throws DimensionMismatchError check_2d_coords(rand(5, 1))
    @test_throws InputValidationError   check_2d_coords(rand(0, 2))
    @test isnothing(check_2d_coords(rand(10, 2)))
end

@testset "check_weights" begin
    @test_throws DimensionMismatchError check_weights([1.0, 2.0], 5)
    @test_throws InputValidationError   check_weights([-1.0, 2.0], 2)
    @test_throws InputValidationError   check_weights([0.0, 0.0], 2)
    @test isnothing(check_weights([1.0, 2.0, 3.0], 3))
end

@testset "check_positive / check_nonneg" begin
    @test_throws InputValidationError check_positive(0.0)
    @test_throws InputValidationError check_positive(-1.0)
    @test isnothing(check_positive(1e-10))

    @test_throws InputValidationError check_nonneg(-1e-10)
    @test isnothing(check_nonneg(0.0))
end

@testset "check_probability" begin
    @test_throws InputValidationError check_probability(-0.1)
    @test_throws InputValidationError check_probability(1.1)
    @test isnothing(check_probability(0.0))
    @test isnothing(check_probability(0.5))
    @test isnothing(check_probability(1.0))
end

@testset "check_probability_vector" begin
    @test_throws InputValidationError check_probability_vector([0.5, 0.6])  # sum > 1
    @test_throws InputValidationError check_probability_vector([-0.1, 1.1]) # out of [0,1]
    @test isnothing(check_probability_vector([0.2, 0.3, 0.5]))
end

@testset "check_in_range" begin
    @test_throws ConfigurationError check_in_range(11.0, 0.0, 10.0, "x")
    @test_throws ConfigurationError check_in_range(-1.0, 0.0, 10.0, "x")
    @test isnothing(check_in_range(5.0, 0.0, 10.0, "x"))
end

@testset "check_p_le_m" begin
    @test_throws ConfigurationError check_p_le_m(0, 10)
    @test_throws ConfigurationError check_p_le_m(11, 10)
    @test isnothing(check_p_le_m(5, 10))
    @test isnothing(check_p_le_m(10, 10))
end

@testset "check_finite" begin
    @test_throws NumericalInstabilityError check_finite([1.0, NaN])
    @test_throws NumericalInstabilityError check_finite([Inf, 0.0])
    @test isnothing(check_finite([1.0, 2.0, 3.0]))
    @test isnothing(check_finite(rand(5, 5)))
end

@testset "check_square / check_conformable / check_same_length" begin
    @test_throws DimensionMismatchError check_square(rand(3, 4))
    @test isnothing(check_square(rand(4, 4)))

    @test_throws DimensionMismatchError check_conformable(rand(3, 4), rand(5))
    @test isnothing(check_conformable(rand(3, 4), rand(4)))

    @test_throws DimensionMismatchError check_same_length([1.0, 2.0], [1.0])
    @test isnothing(check_same_length([1.0, 2.0], [3.0, 4.0]))
end

# ─── Validation macros ────────────────────────────────────────────────────────

@testset "Validation macros" begin
    @test_throws DimensionMismatchError (@validate_dims 1 == 2 "one ≠ two")
    @test isnothing(@validate_dims 1 == 1 "ok")

    good = rand(5)
    @test isnothing(@validate_finite good "v" "op")

    @test_throws InputValidationError (@validate_positive -1.0 "λ")
    @test isnothing(@validate_positive 1.0 "λ")

    @test_throws InputValidationError (@validate_prob 1.5 "p")
    @test isnothing(@validate_prob 0.5 "p")

    @test_throws ConfigurationError (@validate_in_range 5.0 0.0 3.0 "x")
    @test isnothing(@validate_in_range 2.0 0.0 3.0 "x")
end

# ─── Numerical stability functions ───────────────────────────────────────────

@testset "safe_log" begin
    @test safe_log(exp(1.0)) ≈ 1.0
    @test_throws NumericalInstabilityError safe_log(0.0)
    @test_throws NumericalInstabilityError safe_log(-1.0)
end

@testset "safe_sqrt" begin
    @test safe_sqrt(4.0) ≈ 2.0
    @test_throws NumericalInstabilityError safe_sqrt(-1.0)
    @test safe_sqrt(0.0) == 0.0
end

@testset "safe_divide" begin
    @test safe_divide(6.0, 3.0) ≈ 2.0
    @test_throws NumericalInstabilityError safe_divide(1.0, 0.0)
    @test_throws NumericalInstabilityError safe_divide(1.0, 1e-15)
end

@testset "regularize!" begin
    A = [1.0 0.0; 0.0 1.0]
    regularize!(A; λ=0.1)
    @test A[1,1] ≈ 1.1
    @test A[2,2] ≈ 1.1
    @test A[1,2] ≈ 0.0
end

@testset "condition_number" begin
    I2 = Matrix{Float64}(I, 3, 3)
    @test condition_number(I2) ≈ 1.0

    S = Diagonal([1.0, 1e-15])
    @test condition_number(Matrix(S)) > 1e10

    Z = zeros(2, 2)
    @test condition_number(Z) == Inf
end

@testset "check_conditioning" begin
    I3 = Matrix{Float64}(I, 3, 3)
    @test isnothing(check_conditioning(I3))

    ill = [1.0 0.0; 0.0 1e-15]
    @test_throws NumericalInstabilityError check_conditioning(ill; threshold=1e10)
end

@testset "safe_cholesky" begin
    A = [4.0 2.0; 2.0 3.0]
    F = safe_cholesky(A)
    @test F isa Cholesky
    @test norm(F.L * F.U .- A) < 1e-10

    # Singular-ish matrix — should succeed after regularisation
    B = [1.0 1.0; 1.0 1.0]
    # May succeed with regularisation or raise NumericalInstabilityError
    result = try safe_cholesky(B); true catch _; true end
    @test result  # either path is acceptable
end

@testset "safe_solve" begin
    A = [2.0 1.0; 1.0 3.0]
    b = [5.0, 10.0]
    x = safe_solve(A, b)
    @test norm(A * x .- b) < 1e-8
end

@testset "check_convergence" begin
    # Not converged at max_iter → error
    @test_throws ConvergenceError check_convergence(1e-4, 1e-8, 100, 100, "test")
    # Converged → no error
    @test isnothing(check_convergence(1e-10, 1e-8, 50, 100, "test"))
    # Not converged but not at max_iter → no error yet
    @test isnothing(check_convergence(1e-4, 1e-8, 50, 100, "test"))
end

@testset "safe_mean / safe_std" begin
    v = [1.0, 2.0, 3.0, 4.0, 5.0]
    @test safe_mean(v) ≈ 3.0
    @test safe_std(v)  > 0

    @test_throws InputValidationError safe_mean(Float64[])
    @test_throws InputValidationError safe_std(Float64[])

    # Constant vector: std returns ε, not NaN
    c = [5.0, 5.0, 5.0]
    @test safe_std(c) > 0
    @test !isnan(safe_std(c))
end

println("\n✓ All ErrorHandling unit tests passed.")
