#!/usr/bin/env julia
# scripts/rcall_bridge.jl
#
# RCall bridge: call R spatial statistics packages from Julia.
# Enables comparison with R's spdep, spatialreg, and CARBayes.
#
# Prerequisites:
#   R packages: spdep, spatialreg, CARBayes, sf, sp
#   julia> using Pkg; Pkg.add("RCall")
#
# Vol 3 — Julia Package Engineering, Chapter 23.3

using RCall
using DataFrames
using SparseArrays

# ── Initialise R packages ─────────────────────────────────────────────────────

"""
    init_r_spatial()

Load required R packages: spdep, spatialreg, CARBayes.
Called automatically by bridge functions.
"""
function init_r_spatial()
    R"""
    required_pkgs <- c("spdep", "spatialreg", "Matrix")
    missing_pkgs  <- required_pkgs[!sapply(required_pkgs, requireNamespace, quietly=TRUE)]
    if (length(missing_pkgs) > 0) {
        install.packages(missing_pkgs, repos="https://cloud.r-project.org", quiet=TRUE)
    }
    suppressPackageStartupMessages({
        library(spdep)
        library(spatialreg)
        library(Matrix)
    })
    cat("R spatial packages loaded\n")
    """
end

# ── to_r_listw — convert Julia SpatialWeights to R listw ─────────────────────

"""
    to_r_listw(sw) -> RObject

Convert a Julia `SpatialWeights` to an R `listw` object (spdep format).
"""
function to_r_listw(sw)
    n = sw.n
    W = sw.W

    # Build R-side nb and weights lists
    nb_lists = Vector{Vector{Int}}()
    wt_lists = Vector{Vector{Float64}}()

    for i in 1:n
        row = W[i, :]
        idx, vals = SparseArrays.findnz(row)
        push!(nb_lists, Int.(idx))       # 1-indexed (Julia and R both 1-indexed)
        push!(wt_lists, Float64.(vals))
    end

    @rput nb_lists wt_lists n

    R"""
    # Build nb object
    nb_obj <- vector("list", n)
    for (i in seq_len(n)) {
        nb_obj[[i]] <- as.integer(nb_lists[[i]])
    }
    class(nb_obj) <- "nb"
    attr(nb_obj, "region.id") <- as.character(seq_len(n))

    # Build listw
    listw_obj <- nb2listw(nb_obj, glist=wt_lists, style="W", zero.policy=TRUE)
    listw_obj
    """
end

# ── r_moran — Global Moran's I via spdep ─────────────────────────────────────

"""
    r_moran(y, sw; alternative="two.sided", permutations=999) -> NamedTuple

Compute Moran's I using R spdep::moran.mc (permutation test).
"""
function r_moran(y::AbstractVector{<:Real}, sw;
                  alternative  :: String = "two.sided",
                  permutations :: Int    = 999)

    init_r_spatial()
    listw = to_r_listw(sw)

    y_r = Float64.(y)
    @rput y_r permutations

    R"""
    mc_result <- moran.mc(y_r, listw_obj, nsim=permutations,
                           alternative=alternative, zero.policy=TRUE)
    list(
        I     = mc_result$statistic,
        p_sim = mc_result$p.value,
        EI    = moran(y_r, listw_obj, n=length(y_r), S0=Szero(listw_obj),
                      zero.policy=TRUE)$`E(I)`
    )
    """
    r_res = RCall.rcopy(R"mc_result")

    (
        I          = Float64(r_res[:statistic]),
        p_sim      = Float64(r_res[:p_value]),
        expected_I = -1.0 / (length(y) - 1),
        method     = :spdep,
    )
end

# ── r_lisa — Local Moran via spdep ────────────────────────────────────────────

"""
    r_lisa(y, sw; alpha=0.05) -> DataFrame

Compute LISA using R spdep::localmoran.
Returns DataFrame with: I_local, E_Ii, Var_Ii, z_score, p_value.
"""
function r_lisa(y::AbstractVector{<:Real}, sw; alpha::Float64 = 0.05)::DataFrame
    init_r_spatial()
    to_r_listw(sw)

    y_r = Float64.(y)
    @rput y_r alpha

    lm = R"""
    lm_result <- localmoran(y_r, listw_obj, zero.policy=TRUE, alternative="two.sided")
    as.data.frame(lm_result)
    """

    df = rcopy(DataFrame, lm)
    rename!(df, names(df) .=> ["I_local", "E_Ii", "Var_Ii", "z_score", "p_value"])
    df.significant = df.p_value .< alpha
    df
end

# ── r_slm — Spatial Lag Model via spatialreg ──────────────────────────────────

"""
    r_slm(y, X, sw; coef_names) -> NamedTuple

Fit Spatial Lag Model using R spatialreg::lagsarlm (ML).
"""
function r_slm(y::AbstractVector{<:Real},
                X::AbstractMatrix{<:Real},
                sw;
                coef_names :: Union{Nothing, Vector{String}} = nothing)

    init_r_spatial()
    to_r_listw(sw)

    y_r = Float64.(y)
    X_r = Float64.(X)
    k   = size(X, 2)
    names_r = coef_names === nothing ? ["x$(i)" for i in 1:k] : coef_names
    @rput y_r X_r names_r

    R"""
    df_r <- as.data.frame(X_r)
    colnames(df_r) <- names_r
    formula_str <- paste("y_r ~", paste(names_r, collapse=" + "), "- 1")
    slm_result <- spatialreg::lagsarlm(as.formula(formula_str), data=df_r,
                                        listw=listw_obj, zero.policy=TRUE)
    summary_r <- summary(slm_result)
    list(
        coefficients  = coef(slm_result),
        rho           = slm_result$rho,
        log_likelihood= logLik(slm_result),
        AIC           = AIC(slm_result)
    )
    """
    r_res = rcopy(R"list(coefficients=coef(slm_result), rho=slm_result$rho,
                          ll=as.numeric(logLik(slm_result)), aic=AIC(slm_result))")

    (
        coefficients  = Float64.(r_res[:coefficients]),
        rho           = Float64(r_res[:rho]),
        log_likelihood = Float64(r_res[:ll]),
        AIC           = Float64(r_res[:aic]),
        method        = :spatialreg,
    )
end

# ── r_sem — Spatial Error Model via spatialreg ────────────────────────────────

"""
    r_sem(y, X, sw; coef_names) -> NamedTuple

Fit Spatial Error Model using R spatialreg::errorsarlm (ML).
"""
function r_sem(y::AbstractVector{<:Real},
                X::AbstractMatrix{<:Real},
                sw;
                coef_names :: Union{Nothing, Vector{String}} = nothing)

    init_r_spatial()
    to_r_listw(sw)

    y_r = Float64.(y)
    X_r = Float64.(X)
    k   = size(X, 2)
    names_r = coef_names === nothing ? ["x$(i)" for i in 1:k] : coef_names
    @rput y_r X_r names_r

    R"""
    df_r <- as.data.frame(X_r)
    colnames(df_r) <- names_r
    formula_str <- paste("y_r ~", paste(names_r, collapse=" + "), "- 1")
    sem_result <- spatialreg::errorsarlm(as.formula(formula_str), data=df_r,
                                          listw=listw_obj, zero.policy=TRUE)
    list(
        coefficients  = coef(sem_result),
        lambda        = sem_result$lambda,
        log_likelihood= as.numeric(logLik(sem_result)),
        AIC           = AIC(sem_result)
    )
    """
    r_res = rcopy(R"list(coefficients=coef(sem_result), lambda=sem_result$lambda,
                          ll=as.numeric(logLik(sem_result)), aic=AIC(sem_result))")

    (
        coefficients  = Float64.(r_res[:coefficients]),
        lambda        = Float64(r_res[:lambda]),
        log_likelihood = Float64(r_res[:ll]),
        AIC           = Float64(r_res[:aic]),
        method        = :spatialreg,
    )
end

# ── r_rook_weights — True rook weights ───────────────────────────────────────

"""
    r_rook_weights(shp_path::String) -> SpatialWeights (or raw listw RObject)

Build true rook contiguity weights from a shapefile using R spdep::poly2nb.
Returns the R listw object (use with r_moran, r_slm, etc.).

This bridges the Julia limitation where GeoInterface doesn't expose edge topology.
"""
function r_rook_weights(shp_path::String)
    init_r_spatial()
    @rput shp_path

    R"""
    library(sf)
    sf_obj  <- sf::st_read(shp_path, quiet=TRUE)
    nb_rook <- spdep::poly2nb(sf_obj, queen=FALSE)
    listw_obj <<- spdep::nb2listw(nb_rook, style="W", zero.policy=TRUE)
    cat("Rook weights built:", length(nb_rook), "observations\n")
    """
    @info "Rook weights built via R spdep"
    R"listw_obj"
end

# ── r_spatial_workflow — Full spatial workflow in R ───────────────────────────

"""
    r_spatial_workflow(y, X, sw; run_models=[:ols, :slm, :sem]) -> Dict

Run a full spatial workflow in R:
1. OLS with LM tests (spdep::lm.LMtests)
2. Spatial Lag Model (spatialreg::lagsarlm)
3. Spatial Error Model (spatialreg::errorsarlm)

Returns a Dict with results for each model.
"""
function r_spatial_workflow(y::AbstractVector{<:Real},
                              X::AbstractMatrix{<:Real},
                              sw;
                              run_models = [:ols, :slm, :sem])::Dict

    init_r_spatial()
    to_r_listw(sw)

    y_r = Float64.(y)
    X_r = Float64.(X[:, 2:end])  # remove intercept; R's lm adds it
    @rput y_r X_r

    results = Dict{Symbol, Any}()

    if :ols ∈ run_models
        R"""
        df_r  <- as.data.frame(X_r)
        ols_m <- lm(y_r ~ ., data=df_r)
        lm_tests <- spdep::lm.LMtests(ols_m, listw_obj,
                                        test=c("LMlag","LMerr","RLMlag","RLMerr"),
                                        zero.policy=TRUE)
        ols_result <- list(
            r_squared = summary(ols_m)$r.squared,
            aic       = AIC(ols_m),
            lm_lag    = lm_tests$LMlag$statistic,
            lm_lag_p  = lm_tests$LMlag$p.value,
            lm_err    = lm_tests$LMerr$statistic,
            lm_err_p  = lm_tests$LMerr$p.value
        )
        """
        results[:ols] = rcopy(R"ols_result")
    end

    :slm ∈ run_models && (results[:slm] = r_slm(y, X, sw))
    :sem ∈ run_models && (results[:sem] = r_sem(y, X, sw))

    results
end
