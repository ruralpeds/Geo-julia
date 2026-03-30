# geo_iv.jl — Geographic instrumental variables and 2SLS

struct GeoIVResult
    β_2sls::Vector{Float64}     # 2SLS coefficients (treatment + controls)
    se_2sls::Vector{Float64}    # 2SLS SE
    β_first::Vector{Float64}    # first-stage coefficients
    se_first::Vector{Float64}
    f_stat::Float64             # first-stage F-statistic for weak instrument
    r2_first::Float64           # first-stage R²
    n::Int
    feature_names::Vector{String}
    instrument_name::String
end

"""
    geo_iv_2sls(y, D, Z, X; feature_names, instrument_name) -> GeoIVResult

Two-stage least squares with geographic instrument Z (e.g., distance to
nearest facility). Endogenous variable D (treatment intensity or access).

First stage:  D = Z·γ + X·δ + ν
Second stage: y = D̂·τ + X·β + ε

Standard 2SLS SE via sandwich formula.
"""
function geo_iv_2sls(y::AbstractVector, D::AbstractVector,
                     Z::AbstractVector, X::AbstractMatrix;
                     feature_names=["x$i" for i in 1:size(X,2)],
                     instrument_name::String="distance_IV")
    n, p = size(X)

    # Augmented matrices
    Xd_1st  = hcat(ones(n), Z, X)  # first stage design [1, Z, X]
    Xd_2nd  = hcat(ones(n), D, X)  # second stage design [1, D, X]

    # ── First stage ───────────────────────────────────────────────────────────
    β1   = (Xd_1st'Xd_1st + 1e-10*I) \ (Xd_1st' * D)
    D̂    = Xd_1st * β1
    ε̂1   = D .- D̂
    ss_res1 = dot(ε̂1, ε̂1)
    ss_tot1 = dot(D .- mean(D), D .- mean(D))
    r2_1    = 1.0 - ss_res1 / max(ss_tot1, 1e-10)

    # F-statistic for instrument (test γ=0): compare RSS with/without Z
    Xd_no_z = hcat(ones(n), X)
    β_no_z  = (Xd_no_z'Xd_no_z + 1e-10*I) \ (Xd_no_z' * D)
    ε_no_z  = D .- Xd_no_z * β_no_z
    rss_r   = dot(ε_no_z, ε_no_z)
    rss_u   = ss_res1
    σ²1     = ss_res1 / max(n - size(Xd_1st,2), 1)
    f_stat  = (rss_r - rss_u) / max(σ²1, 1e-10)

    # First-stage SE
    σ²1_v   = σ²1
    V1      = σ²1_v .* inv(Xd_1st'Xd_1st + 1e-10*I)
    se_1st  = sqrt.(diag(V1))

    # ── Second stage ──────────────────────────────────────────────────────────
    # Replace D with D̂ in second stage
    Xd_2nd_iv = hcat(ones(n), D̂, X)
    β2         = (Xd_2nd_iv'Xd_2nd_iv + 1e-10*I) \ (Xd_2nd_iv' * y)
    ε̂2         = y .- Xd_2nd * β2  # residuals using actual D (not D̂)

    # 2SLS sandwich SE: V = σ²·(X̃'X̃)⁻¹ where X̃ has D̂
    σ²2    = dot(ε̂2, ε̂2) / max(n - size(Xd_2nd,2), 1)
    V2     = σ²2 .* inv(Xd_2nd_iv'Xd_2nd_iv + 1e-10*I)
    se_2nd = sqrt.(diag(V2))

    all_names = vcat("(Intercept)", ["treatment"], feature_names)
    GeoIVResult(β2, se_2nd, β1, se_1st, f_stat, r2_1, n, all_names, instrument_name)
end

"""
    iv_summary(result) -> nothing

Print 2SLS regression results with weak instrument diagnostic.
"""
function iv_summary(r::GeoIVResult)
    println("=" ^ 60)
    println("  2SLS Geographic IV Results  (n=$(r.n))")
    println("  Instrument: $(r.instrument_name)")
    println("-" ^ 60)
    println("  Second Stage:")
    for j in 1:length(r.β_2sls)
        nm = get(r.feature_names, j, "$j")
        t  = r.β_2sls[j] / max(r.se_2sls[j], 1e-10)
        p  = 2*(1 - _norm_cdf_iv(abs(t)))
        println("    $(lpad(nm,20)): β=$(round(r.β_2sls[j],digits=4))  SE=$(round(r.se_2sls[j],digits=4))  p=$(round(p,digits=4))")
    end
    println()
    println("  First Stage: R²=$(round(r.r2_first,digits=3))  F=$(round(r.f_stat,digits=2))")
    r.f_stat < 10 && println("  ⚠ Weak instrument warning: F < 10")
end

function weak_instrument_test(r::GeoIVResult)
    (f_stat=r.f_stat, r2_first=r.r2_first,
     weak=r.f_stat < 10.0,
     very_weak=r.f_stat < 5.0)
end

_norm_cdf_iv(x) = 0.5*(1 + _erf_iv(x/sqrt(2)))
function _erf_iv(x::Float64)
    t = 1/(1+0.3275911*abs(x))
    y = 1 - (0.254829592t - 0.284496736t^2 + 1.421413741t^3 -
             1.453152027t^4 + 1.061405429t^5) * exp(-x^2)
    x >= 0 ? y : -y
end
