"""
    ErrorHandling

Shared error handling framework for the Geo-Julia open healthcare textbook.

## Exception hierarchy

    GeoJuliaError (abstract)
    ├── InputValidationError    — wrong type, out-of-range, empty
    ├── DimensionMismatchError  — incompatible array shapes
    ├── NumericalInstabilityError — NaN / Inf / ill-conditioning
    ├── ConvergenceError        — iteration budget exhausted
    ├── InfeasibilityError      — no feasible solution exists
    ├── ConfigurationError      — keyword parameter out of valid domain
    └── ContextError            — wraps another error with pipeline context

## Quick start

    using ErrorHandling

    function my_fn(pts, p)
        check_2d_coords(pts, "pts")      # or: @validate_dims size(pts,2)==2 "..."
        check_p_le_m(p, size(pts, 1))
        check_finite(pts, "pts", "my_fn")
        # … algorithm …
    end
"""
module ErrorHandling

using LinearAlgebra, Statistics

# Exception types
include("exceptions.jl")

# Validation guards and macros
include("validation.jl")

# Numerical stability helpers
include("numerical.jl")

export
    # Exception types
    GeoJuliaError,
    InputValidationError,
    DimensionMismatchError,
    NumericalInstabilityError,
    ConvergenceError,
    InfeasibilityError,
    ConfigurationError,
    ContextError,

    # Validation functions
    check_2d_coords,
    check_weights,
    check_positive,
    check_nonneg,
    check_probability,
    check_probability_vector,
    check_in_range,
    check_p_le_m,
    check_finite,
    check_square,
    check_conformable,
    check_same_length,

    # Validation macros
    @validate_dims,
    @validate_finite,
    @validate_positive,
    @validate_prob,
    @validate_in_range,

    # Numerical stability
    safe_log,
    safe_sqrt,
    safe_divide,
    regularize!,
    condition_number,
    check_conditioning,
    safe_cholesky,
    safe_solve,
    check_convergence,
    safe_mean,
    safe_std,
    clamp_logspace

end # module
