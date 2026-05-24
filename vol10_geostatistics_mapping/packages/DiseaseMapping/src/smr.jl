# smr.jl — Standardised Mortality/Morbidity Ratio and indirect standardisation
# Uses Distributions.jl for Poisson p-values

# ── SMR calculation ───────────────────────────────────────────────────────────

"""
    SMRResult

Standardised Mortality/Morbidity Ratio for one area.
"""
struct SMRResult
    area        ::String
    observed    ::Float64
    expected    ::Float64
    smr         ::Float64
    lower_ci    ::Float64   # 95% Byar (1979) CI
    upper_ci    ::Float64
    p_value     ::Float64   # one-sided Poisson test H0: SMR=1
    significant ::Bool
end

"""
    smr(observed, expected; area, alpha) -> SMRResult

Compute SMR = O/E with Byar (1979) approximate confidence interval.

One-sided Poisson p-value using Distributions.jl for H₀: E[O] = E (i.e. SMR=1).
"""
function smr(observed::Real, expected::Real;
             area::String="area", alpha::Float64=0.05)
    O = Float64(observed); E = max(Float64(expected), 1e-10)
    smr_val = O / E
    z = 1.96  # for α=0.05 two-sided

    # Byar CI on O, scaled by 1/E
    lo_o = if O > 0
        O * (1 - 1/(9O) - z/sqrt(9O))^3
    else 0.0 end
    hi_o = (O + 1) * (1 - 1/(9*(O+1)) + z/sqrt(9*(O+1)))^3

    lo_smr = lo_o / E
    hi_smr = hi_o / E

    # Poisson p-value using Distributions.jl
    p = _poisson_upper_tail_p(O, E)
    sig = p < alpha

    SMRResult(area, O, E, smr_val,
              max(lo_smr, 0.0), hi_smr, p, sig)
end

"""
    batch_smr(observed, expected; areas) -> Vector{SMRResult}

Compute SMR for all areas.
"""
function batch_smr(observed::AbstractVector, expected::AbstractVector;
                   areas::Vector{String}=["A$i" for i in eachindex(observed)])
    [smr(observed[i], expected[i]; area=areas[i]) for i in eachindex(observed)]
end

"""
    indirect_standardise(counts_age, pop_age, ref_rates) -> Vector{Float64}

Compute indirectly-standardised expected counts.

E_i = Σ_a pop_ia · ref_rate_a
"""
function indirect_standardise(counts_age::AbstractMatrix,   # n_areas × n_age
                                pop_age::AbstractMatrix,
                                ref_rates::AbstractVector)  # n_age
    n_areas, n_age = size(pop_age)
    @assert length(ref_rates) == n_age
    expected = pop_age * ref_rates  # n_areas vector
    observed = vec(sum(counts_age, dims=2))
    expected, observed
end

# ── Poisson CDF using Distributions.jl ───────────────────────────────────────

"""Upper tail P(X ≥ O | λ=E) using Distributions.jl Poisson CDF."""
function _poisson_upper_tail_p(O::Float64, E::Float64)
    O <= 0 && return 1.0
    k = round(Int, O) - 1
    k < 0 && return 1.0
    # P(X >= O) = 1 - P(X <= O-1) = 1 - cdf(Poisson(E), O-1)
    dist = Distributions.Poisson(E)
    p_lower = Distributions.cdf(dist, k)
    max(0.0, min(1.0, 1.0 - p_lower))
end

# ── SMR mapping summary ───────────────────────────────────────────────────────

"""
    smr_summary(results) -> NamedTuple

Tabular summary of SMR results.
"""
function smr_summary(results::Vector{SMRResult})
    (area      = [r.area     for r in results],
     observed  = [r.observed for r in results],
     expected  = [r.expected for r in results],
     smr       = [r.smr      for r in results],
     lower_ci  = [r.lower_ci for r in results],
     upper_ci  = [r.upper_ci for r in results],
     p_value   = [r.p_value  for r in results],
     significant=[r.significant for r in results])
end
