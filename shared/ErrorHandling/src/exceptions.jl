# exceptions.jl — GeoJulia exception hierarchy
#
# All errors in the Geo-Julia textbook packages derive from GeoJuliaError.
# This lets callers catch the whole family with a single rescue clause while
# still branching on specific subtypes when needed.

"""
    GeoJuliaError <: Exception

Root type for every domain-specific error raised by the Geo-Julia packages.
Catch this type to handle any library error; catch subtypes for finer control.
"""
abstract type GeoJuliaError <: Exception end

# ─── Input / argument errors ─────────────────────────────────────────────────

"""
    InputValidationError(msg, field, value)

Raised when a function argument fails a precondition check (wrong dimensions,
out-of-range value, empty collection, etc.).

Fields:
- `msg`   — human-readable description of the violation
- `field` — name of the offending parameter
- `value` — the actual value that was passed (any type)
"""
struct InputValidationError <: GeoJuliaError
    msg::String
    field::String
    value::Any
end

InputValidationError(msg::String) = InputValidationError(msg, "", nothing)
InputValidationError(msg::String, field::String) = InputValidationError(msg, field, nothing)

Base.showerror(io::IO, e::InputValidationError) = begin
    print(io, "InputValidationError")
    isempty(e.field) || print(io, " [", e.field, "]")
    print(io, ": ", e.msg)
    isnothing(e.value) || print(io, " (got: ", repr(e.value), ")")
end

# ─── Dimension / shape errors ────────────────────────────────────────────────

"""
    DimensionMismatchError(msg, expected, got)

Raised when array shapes are incompatible with the algorithm requirements.
`expected` and `got` are tuples of dimension sizes or shapes.
"""
struct DimensionMismatchError <: GeoJuliaError
    msg::String
    expected::Any    # Tuple or string describing required shape
    got::Any         # Tuple or string describing actual shape
end

DimensionMismatchError(msg::String) = DimensionMismatchError(msg, nothing, nothing)

Base.showerror(io::IO, e::DimensionMismatchError) = begin
    print(io, "DimensionMismatchError: ", e.msg)
    isnothing(e.expected) || print(io, "\n  expected: ", e.expected)
    isnothing(e.got)      || print(io, "\n  got:      ", e.got)
end

# ─── Numerical / floating-point errors ───────────────────────────────────────

"""
    NumericalInstabilityError(msg, operation, details)

Raised when a numerical computation produces NaN, Inf, or an ill-conditioned
matrix that would silently corrupt downstream results.

Fields:
- `msg`       — description
- `operation` — name of the operation where instability was detected
- `details`   — diagnostic (e.g. condition number, residual magnitude)
"""
struct NumericalInstabilityError <: GeoJuliaError
    msg::String
    operation::String
    details::String
end

NumericalInstabilityError(msg::String) =
    NumericalInstabilityError(msg, "unknown", "")
NumericalInstabilityError(msg::String, op::String) =
    NumericalInstabilityError(msg, op, "")

Base.showerror(io::IO, e::NumericalInstabilityError) = begin
    print(io, "NumericalInstabilityError [", e.operation, "]: ", e.msg)
    isempty(e.details) || print(io, "\n  details: ", e.details)
end

# ─── Convergence errors ───────────────────────────────────────────────────────

"""
    ConvergenceError(msg, iterations, tolerance, final_residual)

Raised when an iterative algorithm (Newton-Raphson, value iteration, etc.)
exhausts its iteration budget without reaching the convergence criterion.
"""
struct ConvergenceError <: GeoJuliaError
    msg::String
    iterations::Int
    tolerance::Float64
    final_residual::Float64
end

ConvergenceError(msg::String) = ConvergenceError(msg, -1, NaN, NaN)

Base.showerror(io::IO, e::ConvergenceError) = begin
    print(io, "ConvergenceError: ", e.msg)
    e.iterations > 0 && print(io, " (after ", e.iterations, " iterations)")
    isnan(e.final_residual) || print(io,
        "; residual=", round(e.final_residual; sigdigits=4),
        " > tol=", e.tolerance)
end

# ─── Infeasibility errors ─────────────────────────────────────────────────────

"""
    InfeasibilityError(msg, context)

Raised when an optimisation or constraint satisfaction problem has no
feasible solution under the supplied parameters.
"""
struct InfeasibilityError <: GeoJuliaError
    msg::String
    context::String
end

InfeasibilityError(msg::String) = InfeasibilityError(msg, "")

Base.showerror(io::IO, e::InfeasibilityError) = begin
    print(io, "InfeasibilityError: ", e.msg)
    isempty(e.context) || print(io, "\n  context: ", e.context)
end

# ─── Configuration errors ─────────────────────────────────────────────────────

"""
    ConfigurationError(msg, parameter, valid_range)

Raised when a keyword parameter falls outside its valid domain (e.g.,
negative probability, p > number of candidates, etc.).
"""
struct ConfigurationError <: GeoJuliaError
    msg::String
    parameter::String
    valid_range::String
end

ConfigurationError(msg::String) = ConfigurationError(msg, "", "")
ConfigurationError(msg::String, p::String) = ConfigurationError(msg, p, "")

Base.showerror(io::IO, e::ConfigurationError) = begin
    print(io, "ConfigurationError")
    isempty(e.parameter) || print(io, " [", e.parameter, "]")
    print(io, ": ", e.msg)
    isempty(e.valid_range) || print(io, " (valid: ", e.valid_range, ")")
end

# ─── Context wrapper ──────────────────────────────────────────────────────────

"""
    ContextError(inner, context)

Wraps any GeoJuliaError with additional context about *which* outer function
triggered the error. Useful in cross-package pipelines.

    try
        p_median(...)
    catch e
        throw(ContextError(e, "p_median called from facility_pipeline"))
    end
"""
struct ContextError <: GeoJuliaError
    inner::GeoJuliaError
    context::String
end

Base.showerror(io::IO, e::ContextError) = begin
    print(io, "ContextError in \"", e.context, "\":\n  ")
    showerror(io, e.inner)
end
