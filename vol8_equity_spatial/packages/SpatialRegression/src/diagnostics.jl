# diagnostics.jl — Spatial regression diagnostics for SpatialRegression
# Chapter 49 — Open-Source Healthcare GIS Textbook in Julia

"""
    moran_residuals(e, W; permutations) -> NamedTuple

Moran's I test on regression residuals for spatial autocorrelation.
H₀: residuals are spatially random (no remaining autocorrelation).
I = (n / S₀) · (e'We) / (e'e)   where S₀ = Σᵢⱼ wᵢⱼ

P-value via permutation test.
"""
function moran_residuals(
    e    :: AbstractVector,
    W    :: AbstractMatrix;
    permutations :: Int = 999,
    rng           = Random.GLOBAL_RNG,
)
    n   = length(e)
    S₀  = sum(W)
    S₀ < 1e-12 && return (I=0.0, z=0.0, p=1.0, expected=-1/(n-1))

    I_obs = (n / S₀) * dot(e, W * e) / max(dot(e, e), 1e-12)

    # Permutation distribution
    I_perm = Float64[begin
        e_perm = e[randperm(rng, n)]
        (n / S₀) * dot(e_perm, W * e_perm) / max(dot(e_perm, e_perm), 1e-12)
    end for _ in 1:permutations]

    p_val = mean(I_perm .>= I_obs)
    z     = (I_obs - mean(I_perm)) / max(std(I_perm), 1e-12)

    (I=I_obs, z=z, p=p_val, expected=-1/(n-1),
     perm_mean=mean(I_perm), perm_std=std(I_perm))
end

# ── Lagrange Multiplier tests ─────────────────────────────────────────────────

"""
    lm_lag_test(e, X, W) -> NamedTuple

Lagrange Multiplier test for omitted spatial lag.
LM_lag = [(e'Wy)/s²]² / T₁    where T₁ = tr[(W+W')WW] + (W'Xβ̂)'Mx(WXβ̂)/s²
Anselin (1988). Under H₀, LM_lag ~ χ²(1).
"""
function lm_lag_test(e::AbstractVector, X::AbstractMatrix, W::AbstractMatrix)
    n  = length(e)
    s² = sum(e.^2) / n
    s² < 1e-12 && return (stat=0.0, p=1.0, df=1)

    X_aug = hcat(ones(n), X)
    Px    = X_aug * ((X_aug'X_aug + 1e-8I) \ X_aug')   # projection
    Mx    = I(n) .- Px                                  # annihilator

    Wy    = W * (X_aug * ((X_aug'X_aug + 1e-8I) \ (X_aug' * (e .+ X_aug * ((X_aug'X_aug + 1e-8I) \ X_aug' * e)))))
    # Simplified: numerator = (e'Wy)²/s⁴
    Wy_e  = W * e
    numer = dot(e, Wy_e)^2 / s²^2

    # Denominator T₁ = tr[(W+W')W/n] + norm²/s²
    T₁ = tr((W + W') * W) / n + norm(Mx * W * e)^2 / s²
    T₁ < 1e-12 && return (stat=0.0, p=1.0, df=1)

    stat = numer / T₁
    p    = 1 - cdf_chi2(stat, 1)
    (stat=stat, p=p, df=1)
end

"""
    lm_error_test(e, X, W) -> NamedTuple

Lagrange Multiplier test for spatial error autocorrelation.
LM_err = [(e'We)/s²]² / T₂    where T₂ = tr(W + W')W
Anselin (1988). Under H₀, LM_err ~ χ²(1).
"""
function lm_error_test(e::AbstractVector, X::AbstractMatrix, W::AbstractMatrix)
    n  = length(e)
    s² = sum(e.^2) / n
    s² < 1e-12 && return (stat=0.0, p=1.0, df=1)

    We    = W * e
    numer = dot(e, We)^2 / s²^2
    T₂    = tr((W + W') * W)
    T₂ < 1e-12 && return (stat=0.0, p=1.0, df=1)

    stat = numer / T₂
    p    = 1 - cdf_chi2(stat, 1)
    (stat=stat, p=p, df=1)
end

# χ²(k) CDF via regularised incomplete gamma function
function cdf_chi2(x::Real, k::Int)
    x < 0 && return 0.0
    regularised_gamma(k/2, x/2)
end

function regularised_gamma(a::Real, x::Real)
    # Series expansion for incomplete gamma
    x <= 0 && return 0.0
    t = 0.0; term = 1.0/a; t = term
    for i in 1:200
        term *= x / (a + i)
        t += term
        abs(term) < 1e-10 * t && break
    end
    exp(-x + a*log(x) - lgamma(a)) * t
end

"""
    spatial_breusch_pagan(e, X, W) -> NamedTuple

Breusch-Pagan test for spatial heteroskedasticity.
Regresses e²/s² on spatial-lag of X to detect if variance is spatially structured.
"""
function spatial_breusch_pagan(e::AbstractVector, X::AbstractMatrix, W::AbstractMatrix)
    n  = length(e)
    s² = sum(e.^2) / n

    # Spatially lagged X as auxiliary regressors
    X_aug = hcat(ones(n), X)
    WX    = W * X_aug

    # Regress e²/s² on WX
    y_bp = e.^2 ./ s² .- 1
    β_bp = (WX'WX + 1e-8I) \ (WX' * y_bp)
    ê_bp = y_bp .- WX * β_bp

    # LM statistic: n·R² from auxiliary regression
    r2_bp = 1 - sum(ê_bp.^2) / max(sum(y_bp.^2), 1e-12)
    stat  = n * max(r2_bp, 0.0)
    df    = size(WX, 2)
    p     = 1 - cdf_chi2(stat, df)
    (stat=stat, p=p, df=df)
end

# ── Summary diagnostic struct ─────────────────────────────────────────────────

"""
    SpatialDiagnostics

Collection of spatial model diagnostics.
"""
struct SpatialDiagnostics
    moran           :: NamedTuple
    lm_lag          :: NamedTuple
    lm_error        :: NamedTuple
    breusch_pagan   :: NamedTuple
    recommend_lag   :: Bool
    recommend_error :: Bool
end

"""
    run_diagnostics(e, X, W; permutations) -> SpatialDiagnostics

Run all spatial diagnostics on OLS residuals.
"""
function run_diagnostics(
    e    :: AbstractVector,
    X    :: AbstractMatrix,
    W    :: AbstractMatrix;
    permutations :: Int = 499,
    rng           = Random.GLOBAL_RNG,
)
    mi  = moran_residuals(e, W; permutations=permutations, rng=rng)
    lml = lm_lag_test(e, X, W)
    lme = lm_error_test(e, X, W)
    bp  = spatial_breusch_pagan(e, X, W)

    # Decision rule: Anselin (1988) robust LM procedure
    rec_lag   = lml.p < 0.05 && lml.p < lme.p
    rec_error = lme.p < 0.05 && !rec_lag

    SpatialDiagnostics(mi, lml, lme, bp, rec_lag, rec_error)
end

function Base.show(io::IO, d::SpatialDiagnostics)
    println(io, "SpatialDiagnostics")
    println(io, "  Moran's I: $(round(d.moran.I;digits=4)) (p=$(round(d.moran.p;digits=4)))")
    println(io, "  LM-lag:    stat=$(round(d.lm_lag.stat;digits=3)) (p=$(round(d.lm_lag.p;digits=4)))")
    println(io, "  LM-error:  stat=$(round(d.lm_error.stat;digits=3)) (p=$(round(d.lm_error.p;digits=4)))")
    println(io, "  BP-spatial: stat=$(round(d.breusch_pagan.stat;digits=3)) (p=$(round(d.breusch_pagan.p;digits=4)))")
    if d.recommend_lag
        println(io, "  → Recommendation: Use Spatial Lag model (spatial dependence in outcome)")
    elseif d.recommend_error
        println(io, "  → Recommendation: Use Spatial Error model (spatially correlated errors)")
    else
        println(io, "  → Recommendation: OLS appears adequate (no strong spatial dependence)")
    end
end
