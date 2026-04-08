# estimation.jl — R₀ estimation, herd immunity, serial interval, attack rate

using Statistics, LinearAlgebra

# ─── R₀ estimation methods ────────────────────────────────────────────────────

"""
    r0_from_growth(I_series; γ, dt, n_early) -> NamedTuple

Estimate R₀ from the early exponential growth rate of the epidemic.

Method: log-linear regression on the first n_early positive case counts.
r̂ estimated via OLS; R₀ = (γ + r̂) / γ.

Reference: Wallinga & Lipsitch (2007).
"""
function r0_from_growth(I_series::AbstractVector{<:Real};
                          γ::Float64,
                          dt::Float64=1.0,
                          n_early::Int=20)
    γ > 0 || error("γ must be positive")
    I_pos = Float64.(I_series[I_series .> 0])
    isempty(I_pos) && return (R₀=NaN, r=NaN, ci_lower=NaN, ci_upper=NaN, method=:growth)
    log_I = log.(I_pos[1:min(n_early, end)])
    n     = length(log_I)
    n < 3 && return (R₀=1.0, r=0.0, ci_lower=NaN, ci_upper=NaN, method=:growth)

    t  = Float64.(1:n) .* dt
    t̄, ȳ = mean(t), mean(log_I)
    Stt = sum((t .- t̄).^2)
    Sty = sum((t .- t̄) .* (log_I .- ȳ))
    r̂   = Sty / max(Stt, 1e-12)
    â   = ȳ - r̂ * t̄

    # SE of r̂
    ŷ   = â .+ r̂ .* t
    sse = sum((log_I .- ŷ).^2)
    se_r = sqrt(sse / max(n-2, 1) / Stt)
    ci_lo = (γ + (r̂ - 1.96*se_r)) / γ
    ci_hi = (γ + (r̂ + 1.96*se_r)) / γ

    (R₀=max((γ + r̂)/γ, 0.0), r=r̂, ci_lower=max(ci_lo,0.0),
     ci_upper=ci_hi, method=:growth)
end

"""
    r0_from_sir(S_end, N) -> NamedTuple

Back-calculate R₀ from the final attack rate A = (N - S_∞)/N.

Solves: 1 - A = exp(-R₀·A)  via Newton iteration.
Reference: Ma & Earn (2006).
"""
function r0_from_sir(S_end::Real, N::Real)
    N > 0   || error("N must be positive")
    S_end > N && error("S_end cannot exceed N")
    A = 1.0 - S_end / N   # final attack rate
    A < 1e-6 && return (R₀=1.0, attack_rate=A, method=:attack_rate)

    # Newton: f(R₀) = 1 - A - exp(-R₀·A) = 0
    R₀ = 1.5  # initial guess
    for _ in 1:50
        f  = 1.0 - A - exp(-R₀ * A)
        df = A * exp(-R₀ * A)
        Δ  = f / max(df, 1e-12)
        R₀ -= Δ
        R₀  = max(0.0, R₀)
        abs(Δ) < 1e-10 && break
    end
    (R₀=R₀, attack_rate=A, method=:attack_rate)
end

"""
    r0_from_params(β, γ; σ, model) -> Float64

Analytical R₀ from model parameters:
- SIR:  R₀ = β/γ
- SEIR: R₀ = β/γ  (same; σ only affects timing)
"""
r0_from_params(β::Real, γ::Real; σ::Real=Inf, model::Symbol=:sir) = β / γ

# ─── Herd immunity ────────────────────────────────────────────────────────────

"""
    herd_immunity_threshold(R₀) -> Float64

Minimum vaccination coverage p* to prevent epidemic spread:
  p* = 1 - 1/R₀

Returns 0.0 if R₀ ≤ 1 (no herd immunity required).
"""
function herd_immunity_threshold(R₀::Real)
    R₀ <= 1.0 && return 0.0
    1.0 - 1.0 / R₀
end

"""
    effective_r0(R₀, p_immune) -> Float64

Effective reproduction number given fraction `p_immune` already immune:
  Rₑ = R₀ · (1 - p_immune)
"""
effective_r0(R₀::Real, p_immune::Real) = R₀ * (1.0 - clamp(p_immune, 0.0, 1.0))

# ─── Serial interval and generation time ─────────────────────────────────────

"""
    estimate_serial_interval(onset_times; n_boot, rng) -> NamedTuple

Estimate the serial interval distribution from a vector of pairs
(infector_onset, infectee_onset) encoded as a vector of differences.

Returns mean, SD, and 95% CI via bootstrap.
"""
function estimate_serial_interval(si_samples::AbstractVector{<:Real};
                                   n_boot::Int=200,
                                   rng=Random.default_rng())
    isempty(si_samples) && return (mean=NaN, sd=NaN, median=NaN,
                                    ci_lower=NaN, ci_upper=NaN, n=0)
    μ̂   = mean(si_samples)
    σ̂   = std(si_samples; corrected=true)
    med  = median(si_samples)
    n    = length(si_samples)

    # Bootstrap CI for mean
    boot_means = [mean(si_samples[rand(rng, 1:n, n)]) for _ in 1:n_boot]
    sort!(boot_means)
    ci_lo = boot_means[max(1, round(Int, 0.025*n_boot))]
    ci_hi = boot_means[min(n_boot, round(Int, 0.975*n_boot))]

    (mean=μ̂, sd=σ̂, median=med, ci_lower=ci_lo, ci_upper=ci_hi, n=n)
end

# ─── Final attack rate ────────────────────────────────────────────────────────

"""
    attack_rate_prediction(R₀; tol) -> Float64

Predict the final epidemic attack rate A from R₀ by solving the implicit equation:
  1 - A = exp(-R₀ · A)

Returns the non-trivial root via bisection.
"""
function attack_rate_prediction(R₀::Real; tol::Float64=1e-10)
    R₀ <= 1.0 && return 0.0
    # Bisection on f(A) = 1 - A - exp(-R₀·A)
    lo, hi = 0.0, 1.0 - 1e-9
    for _ in 1:100
        mid = (lo + hi) / 2
        fmid = 1.0 - mid - exp(-R₀ * mid)
        fmid > 0 ? (lo = mid) : (hi = mid)
        hi - lo < tol && break
    end
    (lo + hi) / 2
end

# ─── Doubling time ────────────────────────────────────────────────────────────

"""
    doubling_time(r) -> Float64

Compute the epidemic doubling time from growth rate r: T₂ = log(2)/r.
Returns Inf if r ≤ 0.
"""
doubling_time(r::Real) = r > 0 ? log(2.0) / r : Inf
