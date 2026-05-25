# numerical.jl — Numerical stability utilities
#
# These functions wrap common numerical operations with safety checks and
# stable fallbacks, using the GeoJulia exception types.

using LinearAlgebra, Statistics

# ─── Safe scalar operations ───────────────────────────────────────────────────

"""
    safe_log(x; name, op) -> Float64

Compute `log(x)` with a domain guard.
Raises `NumericalInstabilityError` if `x ≤ 0`.
"""
function safe_log(x::Real; name::String="argument", op::String="log")
    x <= 0 && throw(NumericalInstabilityError(
        "log requires a positive argument (got $(x))", op,
        "argument name: $(name)"))
    log(x)
end

"""
    safe_sqrt(x; name, op) -> Float64

Compute `sqrt(x)` with a domain guard.
Raises `NumericalInstabilityError` if `x < 0`.
"""
function safe_sqrt(x::Real; name::String="argument", op::String="sqrt")
    x < 0 && throw(NumericalInstabilityError(
        "sqrt requires a non-negative argument (got $(x))", op,
        "argument name: $(name)"))
    sqrt(x)
end

"""
    safe_divide(a, b; name_b, op, eps) -> Float64

Compute `a / b` guarded against division by zero.
Returns a clamped result when |b| < eps rather than ±Inf.
"""
function safe_divide(a::Real, b::Real;
                     name_b::String="denominator",
                     op::String="division",
                     eps::Float64=1e-12)
    abs(b) < eps && throw(NumericalInstabilityError(
        "near-zero $(name_b) in division (|b|=$(abs(b)) < $(eps))", op,
        "numerator=$(a), denominator=$(b)"))
    a / b
end

# ─── Matrix safety ────────────────────────────────────────────────────────────

"""
    regularize!(A; λ) -> A

Add `λ * I` to the diagonal of `A` in-place to improve conditioning.
Logs a diagnostic but does not raise; callers that need to enforce a
condition-number limit should call `check_conditioning` afterwards.
"""
function regularize!(A::AbstractMatrix{Float64}; λ::Float64=1e-8)
    n = size(A, 1)
    @inbounds for i in 1:n
        A[i, i] += λ
    end
    A
end

"""
    condition_number(A) -> Float64

Estimate the 2-norm condition number of `A` via `svdvals`.
Returns `Inf` for singular or nearly-singular matrices.
"""
function condition_number(A::AbstractMatrix)
    sv = svdvals(A)
    sv[end] < 1e-300 && return Inf
    sv[1] / sv[end]
end

"""
    check_conditioning(A; threshold, op) -> nothing

Raise `NumericalInstabilityError` if the condition number of `A` exceeds
`threshold` (default 1e12, roughly at the edge of double-precision accuracy).
"""
function check_conditioning(A::AbstractMatrix;
                             threshold::Float64=1e12,
                             op::String="matrix operation")
    κ = condition_number(A)
    κ > threshold && throw(NumericalInstabilityError(
        "matrix is ill-conditioned (κ ≈ $(round(κ; sigdigits=3)))",
        op,
        "threshold = $(threshold); consider regularization"))
    return nothing
end

"""
    safe_cholesky(A; op, λ_init, λ_max) -> Cholesky

Attempt Cholesky factorisation of `A`, falling back to progressively larger
diagonal regularisation (λ_init → λ_max) before raising an error.
"""
function safe_cholesky(A::AbstractMatrix;
                       op::String="Cholesky",
                       λ_init::Float64=1e-10,
                       λ_max::Float64=1e-2)
    Ac = copy(A)
    λ  = λ_init
    while λ <= λ_max
        try
            return cholesky(Symmetric(Ac))
        catch
            regularize!(Ac; λ=λ)
            λ *= 10.0
        end
    end
    throw(NumericalInstabilityError(
        "Cholesky factorisation failed even after regularisation (λ up to $(λ_max))",
        op,
        "matrix size: $(size(A))"))
end

"""
    safe_solve(A, b; op) -> Vector{Float64}

Solve `A x = b` with a fallback to the pseudo-inverse for rank-deficient `A`.
Raises `NumericalInstabilityError` if the residual ‖Ax - b‖₂ > 1e-6.
"""
function safe_solve(A::AbstractMatrix, b::AbstractVector;
                    op::String="linear solve")
    check_finite(A, "A", op)
    check_finite(b, "b", op)
    x = try
        A \ b
    catch
        pinv(A) * b
    end
    res = norm(A * x .- b)
    res > 1e-6 && throw(NumericalInstabilityError(
        "linear solve residual ‖Ax-b‖₂ = $(round(res; sigdigits=4)) > 1e-6",
        op,
        "A size: $(size(A)), b length: $(length(b))"))
    x
end

# ─── Convergence checking ─────────────────────────────────────────────────────

"""
    check_convergence(residual, tol, iter, max_iter, name) -> nothing

Raise `ConvergenceError` if `residual > tol` and `iter == max_iter`.
No-op otherwise (allows intermediate calls inside loops).
"""
function check_convergence(residual::Float64, tol::Float64,
                            iter::Int, max_iter::Int,
                            name::String="algorithm")
    (iter >= max_iter && residual > tol) && throw(ConvergenceError(
        "$(name) did not converge within $(max_iter) iterations",
        iter, tol, residual))
    return nothing
end

# ─── Safe statistical helpers ─────────────────────────────────────────────────

"""
    safe_mean(x; name) -> Float64

Return the mean of `x`, raising `NumericalInstabilityError` if `x` is empty
or contains non-finite values.
"""
function safe_mean(x::AbstractVector; name::String="vector")
    isempty(x) && throw(InputValidationError(
        "cannot compute mean of empty vector", name))
    check_finite(x, name, "mean")
    mean(x)
end

"""
    safe_std(x; name, corrected) -> Float64

Return the standard deviation of `x`, guarded against zero-variance input
(returns a small ε rather than NaN so downstream computations remain stable).
"""
function safe_std(x::AbstractVector; name::String="vector", corrected::Bool=true)
    isempty(x) && throw(InputValidationError(
        "cannot compute std of empty vector", name))
    s = std(x; corrected=corrected)
    isnan(s) || isinf(s) ? 1e-12 : max(s, 1e-12)
end

"""
    clamp_logspace(logval; lo, hi) -> Float64

Clamp a log-domain value to the range [log(lo), log(hi)], which corresponds
to clamping the underlying probability to [lo, hi] in the natural domain.
Avoids underflow/overflow in Erlang-C and similar log-space computations.
"""
function clamp_logspace(logval::Float64;
                         lo::Float64=log(1e-300),
                         hi::Float64=0.0)
    clamp(logval, lo, hi)
end
