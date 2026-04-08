# validation.jl — Input validation guards and macros
#
# Usage in package source files:
#   include("path/to/validation.jl")  # or `using ErrorHandling`
#
# The macros are syntactic sugar over explicit `if/throw` patterns, designed
# so that the overhead is zero when the condition is satisfied.

# ─── Low-level guard functions ────────────────────────────────────────────────

"""
    check_2d_coords(arr, name) -> nothing

Throw `DimensionMismatchError` unless `arr` is a 2-column matrix.
"""
function check_2d_coords(arr::AbstractMatrix, name::String="coords")
    if size(arr, 2) != 2
        throw(DimensionMismatchError(
            "coordinate matrix must have exactly 2 columns (x, y)",
            "n × 2",
            "$(size(arr,1)) × $(size(arr,2))"))
    end
    if size(arr, 1) == 0
        throw(InputValidationError(
            "coordinate matrix must contain at least one point",
            name, size(arr)))
    end
end

"""
    check_weights(w, n, name) -> nothing

Throw `InputValidationError` unless `w` has length `n` and all entries ≥ 0.
"""
function check_weights(w::AbstractVector, n::Int, name::String="weights")
    length(w) != n && throw(DimensionMismatchError(
        "weight vector length does not match number of demand points",
        n, length(w)))
    any(w .< 0) && throw(InputValidationError(
        "all weights must be non-negative",
        name, minimum(w)))
    all(iszero, w) && throw(InputValidationError(
        "at least one weight must be positive",
        name, w))
end

"""
    check_positive(x, name) -> nothing

Throw `InputValidationError` if `x ≤ 0`.
"""
function check_positive(x::Real, name::String="parameter")
    x <= 0 && throw(InputValidationError(
        "must be strictly positive",
        name, x))
end

"""
    check_nonneg(x, name) -> nothing

Throw `InputValidationError` if `x < 0`.
"""
function check_nonneg(x::Real, name::String="parameter")
    x < 0 && throw(InputValidationError(
        "must be non-negative",
        name, x))
end

"""
    check_probability(p, name) -> nothing

Throw `InputValidationError` unless 0 ≤ p ≤ 1.
"""
function check_probability(p::Real, name::String="probability")
    (p < 0 || p > 1) && throw(InputValidationError(
        "must be in [0, 1]",
        name, p))
end

"""
    check_probability_vector(v, name) -> nothing

Throw `InputValidationError` unless all entries ∈ [0,1] and sum ≈ 1.
"""
function check_probability_vector(v::AbstractVector, name::String="probability vector")
    any(v .< 0) || any(v .> 1) && throw(InputValidationError(
        "all probabilities must be in [0, 1]",
        name, (minimum(v), maximum(v))))
    abs(sum(v) - 1.0) > 1e-8 && throw(InputValidationError(
        "probabilities must sum to 1.0 (got $(round(sum(v); sigdigits=6)))",
        name, sum(v)))
end

"""
    check_in_range(x, lo, hi, name) -> nothing

Throw `ConfigurationError` unless `lo ≤ x ≤ hi`.
"""
function check_in_range(x::Real, lo::Real, hi::Real, name::String="parameter")
    (x < lo || x > hi) && throw(ConfigurationError(
        "$(name) = $(x) is out of bounds",
        name,
        "[$lo, $hi]"))
end

"""
    check_p_le_m(p, m) -> nothing

Throw `ConfigurationError` if the number of requested facilities `p` exceeds
the number of candidates `m`.
"""
function check_p_le_m(p::Int, m::Int)
    p < 1 && throw(ConfigurationError(
        "p must be ≥ 1", "p", "1..$(m)"))
    p > m && throw(ConfigurationError(
        "p ($p) exceeds the number of candidate locations ($m)",
        "p", "1..$(m)"))
end

"""
    check_finite(x, name) -> nothing

Throw `NumericalInstabilityError` if any element of `x` is NaN or Inf.
"""
function check_finite(x, name::String="value", op::String="input check")
    if !all(isfinite, x)
        n_nan = count(isnan, x)
        n_inf = count(isinf, x)
        throw(NumericalInstabilityError(
            "$(name) contains non-finite values (NaN=$(n_nan), Inf=$(n_inf))",
            op,
            "Array size: $(size(x))"))
    end
end

"""
    check_square(A, name) -> nothing

Throw `DimensionMismatchError` unless `A` is square.
"""
function check_square(A::AbstractMatrix, name::String="matrix")
    m, n = size(A)
    m != n && throw(DimensionMismatchError(
        "$(name) must be square", "n × n", "$(m) × $(n)"))
end

"""
    check_conformable(A, b, name_A, name_b) -> nothing

Throw `DimensionMismatchError` unless `A` has as many columns as `b` has rows.
"""
function check_conformable(A::AbstractMatrix, b::AbstractVector,
                            name_A::String="A", name_b::String="b")
    size(A, 2) != length(b) && throw(DimensionMismatchError(
        "$(name_A) ($(size(A,1))×$(size(A,2))) is not conformable with $(name_b) ($(length(b)))",
        "A rows = b length",
        "$(size(A,2)) ≠ $(length(b))"))
end

"""
    check_same_length(a, b, name_a, name_b) -> nothing

Throw `DimensionMismatchError` unless `a` and `b` have the same length.
"""
function check_same_length(a::AbstractVector, b::AbstractVector,
                            name_a::String="a", name_b::String="b")
    length(a) != length(b) && throw(DimensionMismatchError(
        "$(name_a) and $(name_b) must have the same length",
        length(a), length(b)))
end

# ─── Macros (zero-overhead syntactic sugar) ───────────────────────────────────

"""
    @validate_dims expr msg

Example:
    @validate_dims size(X, 2) == 2  "X must be n×2"
"""
macro validate_dims(cond, msg)
    quote
        $(esc(cond)) || throw(DimensionMismatchError($(esc(msg))))
    end
end

"""
    @validate_finite arr name op

Example:
    @validate_finite X "X" "matrix_solve"
"""
macro validate_finite(arr, name, op)
    quote
        check_finite($(esc(arr)), $(esc(name)), $(esc(op)))
    end
end

"""
    @validate_positive x name

Example:
    @validate_positive λ "arrival_rate"
"""
macro validate_positive(x, name)
    quote
        check_positive($(esc(x)), $(esc(name)))
    end
end

"""
    @validate_prob p name

Example:
    @validate_prob busy_fraction "busy_fraction"
"""
macro validate_prob(p, name)
    quote
        check_probability($(esc(p)), $(esc(name)))
    end
end

"""
    @validate_in_range x lo hi name

Example:
    @validate_in_range γ 0 1 "discount"
"""
macro validate_in_range(x, lo, hi, name)
    quote
        check_in_range($(esc(x)), $(esc(lo)), $(esc(hi)), $(esc(name)))
    end
end
