# risk_scoring.jl — Risk stratification, composite health index, risk-adjusted outcomes

using Statistics, LinearAlgebra

# ─── Composite risk scoring ───────────────────────────────────────────────────

struct RiskScoreResult
    scores::Vector{Float64}      # composite z-score per unit
    quantile_band::Vector{Int}   # 1=low, 2=moderate, 3=high, 4=very high
    weights::Vector{Float64}     # applied domain weights
    domain_scores::Matrix{Float64}  # standardised domain scores (n × d)
    n::Int; n_domains::Int
end

"""
    composite_risk_score(X; weights, n_bands) -> RiskScoreResult

Compute a composite health risk score from `d` domain indicators.

`X` is n × d (rows = units, columns = domains). Higher scores = worse health.
Each domain is z-standardised then weighted. Final score = Σ wⱼ·zᵢⱼ.
Units are binned into `n_bands` risk strata using quantiles.
"""
function composite_risk_score(X::AbstractMatrix;
                                weights::AbstractVector=ones(size(X,2)),
                                n_bands::Int=4)
    n, d = size(X)
    n < 2 && error("need at least 2 units")
    d == length(weights) || error("weights length must match number of domains")
    any(weights .< 0) && error("all weights must be non-negative")

    # Standardise each domain using StatsBase
    Z = zeros(n, d)
    for j in 1:d
        col = Float64.(X[:, j])
        μ_j = mean(col)
        σ_j = max(std(col; corrected=true), 1e-12)
        Z[:, j] = (col .- μ_j) ./ σ_j
    end

    w = weights ./ max(sum(weights), 1e-12)
    scores = Z * w  # n-vector

    # Quantile bands
    q_cuts = quantile(scores, (1:n_bands-1) ./ n_bands)
    bands  = [searchsortedfirst(q_cuts, s) + 1 for s in scores]

    RiskScoreResult(scores, bands, w, Z, n, d)
end

# ─── Health Needs Index ────────────────────────────────────────────────────────

struct HealthNeedsIndex
    index::Vector{Float64}       # composite HNI per unit (0-100 scale)
    access_score::Vector{Float64}
    deprivation_score::Vector{Float64}
    burden_score::Vector{Float64}
    rank::Vector{Int}            # rank 1 = highest need
    quantile_band::Vector{Int}
    n::Int
end

"""
    health_needs_index(access, deprivation, disease_burden;
                       w_access, w_deprivation, w_burden) -> HealthNeedsIndex

Construct a Health Needs Index (HNI) from three domain indicators:

- `access`        — travel/access barriers (higher = worse access)
- `deprivation`   — socioeconomic deprivation composite
- `disease_burden` — standardised mortality/morbidity ratio

Domains are z-standardised, combined with weights, rescaled to [0, 100].
"""
function health_needs_index(access::AbstractVector,
                              deprivation::AbstractVector,
                              disease_burden::AbstractVector;
                              w_access::Float64=0.3,
                              w_deprivation::Float64=0.4,
                              w_burden::Float64=0.3)
    length(access) == length(deprivation) == length(disease_burden) ||
        error("all domain vectors must have the same length")
    n = length(access)

    z(v) = begin
        vf = Float64.(v)
        zscore(vf)
    end

    za = z(access); zd = z(deprivation); zb = z(disease_burden)
    composite = w_access*za .+ w_deprivation*zd .+ w_burden*zb

    # Rescale to [0, 100]
    lo, hi = minimum(composite), maximum(composite)
    scaled  = (composite .- lo) ./ max(hi - lo, 1e-12) .* 100

    rank = sortperm(sortperm(.-scaled))  # rank 1 = highest HNI
    bands = [clamp(ceil(Int, 4*scaled[i]/101), 1, 4) for i in 1:n]

    HealthNeedsIndex(scaled, za.*50.+50, zd.*50.+50, zb.*50.+50,
                     rank, bands, n)
end

# ─── Risk-adjusted outcome analysis ──────────────────────────────────────────

"""
    risk_adjusted_outcomes(observed, expected; label) -> NamedTuple

Compute risk-adjusted performance metrics (AHRQ-style SMR approach):

- Standardised Mortality/Morbidity Ratio: SMR = Σobs / Σexp
- 95% CI via Byar's approximation (exact Poisson CI for small counts)
- Flag units as high outliers (SMR 95% CI lower > 1) or low outliers (upper < 1)

`observed` — observed event counts per unit
`expected` — expected event counts per unit (from risk model)
"""
function risk_adjusted_outcomes(observed::AbstractVector{<:Real},
                                  expected::AbstractVector{<:Real};
                                  label::String="Outcomes")
    length(observed) == length(expected) ||
        error("observed and expected must have the same length")
    n = length(observed)
    smr    = sum(observed) / max(sum(expected), 1e-9)
    # Unit-level SMR with Byar CI
    unit_smr = Float64.(observed) ./ max.(Float64.(expected), 1e-9)
    ci_lo    = [_byar_lower(observed[i], expected[i]) for i in 1:n]
    ci_hi    = [_byar_upper(observed[i], expected[i]) for i in 1:n]
    high_out = ci_lo .> 1.0
    low_out  = ci_hi .< 1.0

    (smr_global=smr, unit_smr=unit_smr,
     ci_lower=ci_lo, ci_upper=ci_hi,
     high_outliers=findall(high_out), low_outliers=findall(low_out),
     n_high=sum(high_out), n_low=sum(low_out), label=label)
end

# Poisson CI on O/E ratio using Distributions.jl
# Byar's approximation is standard for SMR CIs; we keep it for consistency
# but use Distributions.Poisson quantiles for small counts
function _byar_lower(o::Real, e::Real)
    o == 0 && return 0.0
    o_f = Float64(o); e_f = max(Float64(e), 1e-12)
    # For small counts, use exact Poisson quantile
    if o_f < 20
        lo = Distributions.quantile(Distributions.Poisson(o_f), 0.025)
        return lo / e_f
    end
    (o_f * (1 - 1/(9o_f) - 1.645/sqrt(o_f))^3) / e_f
end
function _byar_upper(o::Real, e::Real)
    o_f = Float64(o); e_f = max(Float64(e), 1e-12)
    if o_f < 20
        hi = Distributions.quantile(Distributions.Poisson(o_f + 1), 0.975)
        return hi / e_f
    end
    ((o_f+1) * (1 - 1/(9*(o_f+1)) + 1.645/sqrt(o_f+1))^3) / e_f
end
