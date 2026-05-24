# geo_iv.jl — Geographic instrumental variables and 2SLS using GLM.jl

struct GeoIVResult
    β_2sls::Vector{Float64}     # 2SLS coefficients (treatment + controls)
    se_2sls::Vector{Float64}    # 2SLS SE
    β_first::Vector{Float64}    # first-stage coefficients
    se_first::Vector{Float64}
    f_stat::Float64             # first-stage F-statistic for weak instrument
    r2_first::Float64           # first-stage R-squared
    n::Int
    feature_names::Vector{String}
    instrument_name::String
end

"""
    geo_iv_2sls(y, D, Z, X; feature_names, instrument_name) -> GeoIVResult

Two-stage least squares with geographic instrument Z (e.g., distance to
nearest facility). Endogenous variable D (treatment intensity or access).

First stage:  D = Z*gamma + X*delta + nu  (fitted via GLM.jl)
Second stage: y = D_hat*tau + X*beta + eps (fitted via GLM.jl)

Standard 2SLS SE via sandwich formula.
"""
function geo_iv_2sls(y::AbstractVector, D::AbstractVector,
                     Z::AbstractVector, X::AbstractMatrix;
                     feature_names=["x$i" for i in 1:size(X,2)],
                     instrument_name::String="distance_IV")
    n, p = size(X)

    # -- First stage via GLM.jl ------------------------------------------------
    col_names_1st = vcat([:instrument], [Symbol("x$i") for i in 1:p])
    df_1st = DataFrame(hcat(Z, X), col_names_1st)
    df_1st.D = Float64.(D)

    rhs_1st = foldl(+, [Term(s) for s in col_names_1st])
    f_1st = FormulaTerm(Term(:D), rhs_1st)
    model_1st = lm(f_1st, df_1st)

    β1   = coef(model_1st)
    se_1st = stderror(model_1st)
    D̂    = predict(model_1st)
    r2_1 = r2(model_1st)

    # F-statistic for instrument (test gamma=0): compare with restricted model
    col_names_r = [Symbol("x$i") for i in 1:p]
    df_r = DataFrame(X, col_names_r)
    df_r.D = Float64.(D)
    rhs_r = p == 0 ? ConstantTerm(1) : foldl(+, [Term(s) for s in col_names_r])
    f_r = FormulaTerm(Term(:D), rhs_r)
    model_r = lm(f_r, df_r)

    rss_r = deviance(model_r)
    rss_u = deviance(model_1st)
    k_1st = length(β1)
    σ²1   = rss_u / max(n - k_1st, 1)
    f_stat = (rss_r - rss_u) / max(σ²1, 1e-10)

    # -- Second stage via GLM.jl -----------------------------------------------
    # Replace D with D_hat in second stage
    col_names_2nd = vcat([:D_hat], [Symbol("x$i") for i in 1:p])
    df_2nd = DataFrame(hcat(D̂, X), col_names_2nd)
    df_2nd.y = Float64.(y)

    rhs_2nd = foldl(+, [Term(s) for s in col_names_2nd])
    f_2nd = FormulaTerm(Term(:y), rhs_2nd)
    model_2nd = lm(f_2nd, df_2nd)

    β2 = coef(model_2nd)

    # 2SLS SE: use residuals from actual D (not D_hat)
    Xd_2nd   = hcat(ones(n), D, X)
    Xd_2nd_iv = hcat(ones(n), D̂, X)
    ε̂2       = y .- Xd_2nd * β2  # residuals using actual D
    σ²2      = dot(ε̂2, ε̂2) / max(n - size(Xd_2nd,2), 1)
    V2       = σ²2 .* inv(Xd_2nd_iv'Xd_2nd_iv + 1e-10*I)
    se_2nd   = sqrt.(diag(V2))

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
        p  = 2*(1 - cdf(Normal(), abs(t)))
        println("    $(lpad(nm,20)): beta=$(round(r.β_2sls[j],digits=4))  SE=$(round(r.se_2sls[j],digits=4))  p=$(round(p,digits=4))")
    end
    println()
    println("  First Stage: R2=$(round(r.r2_first,digits=3))  F=$(round(r.f_stat,digits=2))")
    r.f_stat < 10 && println("  Warning: Weak instrument (F < 10)")
end

function weak_instrument_test(r::GeoIVResult)
    (f_stat=r.f_stat, r2_first=r.r2_first,
     weak=r.f_stat < 10.0,
     very_weak=r.f_stat < 5.0)
end
