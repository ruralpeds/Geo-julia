# model_comparison.jl — Bayesian model comparison for BayesianHealth
# Chapter 46 — Open-Source Healthcare GIS Textbook in Julia

# ── WAIC ─────────────────────────────────────────────────────────────────────

"""
    WAICResult

Watanabe-Akaike Information Criterion (Watanabe 2010).
Lower WAIC = better predictive accuracy.
"""
struct WAICResult
    waic      :: Float64   # -2·(lppd - p_waic)
    lppd      :: Float64   # log pointwise predictive density
    p_waic    :: Float64   # effective number of parameters
    se        :: Float64   # standard error of WAIC
    pointwise :: Vector{Float64}
end

"""
    waic(log_lik_matrix) -> WAICResult

Compute WAIC from a matrix of log-likelihoods.
- `log_lik_matrix`: S × N matrix; S samples, N observations
  log_lik_matrix[s, i] = log p(y_i | θ^s)

WAIC = -2 · (lppd - p_WAIC)
lppd = Σᵢ log(mean_s exp(log_lik[s,i]))
p_WAIC = Σᵢ var_s(log_lik[s,i])
"""
function waic(log_lik_matrix::AbstractMatrix)
    S, N = size(log_lik_matrix)

    # lppd via log-sum-exp for numerical stability
    pointwise_lppd = Float64[begin
        lk = log_lik_matrix[:, i]
        m = maximum(lk)
        log(mean(exp.(lk .- m))) + m
    end for i in 1:N]

    lppd_val = sum(pointwise_lppd)

    # Effective parameters via variance of log-likelihood
    p_waic_i = Float64[var(log_lik_matrix[:, i]) for i in 1:N]
    p_waic_val = sum(p_waic_i)

    # Pointwise contribution to WAIC (for SE calculation)
    pw_waic = -2 .* (pointwise_lppd .- p_waic_i)
    waic_val = sum(pw_waic)

    # Standard error over observations
    se = sqrt(N * var(pw_waic))

    WAICResult(waic_val, lppd_val, p_waic_val, se, pw_waic)
end

# ── LOO-IC (PSIS-LOO) ─────────────────────────────────────────────────────────

"""
    LOOResult

Leave-one-out information criterion via Pareto-smoothed importance sampling
(Vehtari, Gelman & Gabry 2017).
"""
struct LOOResult
    loo_ic      :: Float64
    lppd_loo    :: Float64
    p_loo       :: Float64
    se          :: Float64
    pareto_k    :: Vector{Float64}   # per-observation Pareto k̂
    n_bad_k     :: Int               # observations with k̂ > 0.7
    pointwise   :: Vector{Float64}
end

"""
    loo_ic(log_lik_matrix; r_eff) -> LOOResult

PSIS-LOO: approximate leave-one-out cross-validation.
Uses Pareto-smoothed importance weights.
r_eff: relative efficiency (ESS / n_samples); default = 1.
"""
function loo_ic(log_lik_matrix::AbstractMatrix; r_eff::Float64=1.0)
    S, N = size(log_lik_matrix)

    # Raw importance weights: log w_is ∝ -log p(y_i | θ_s)
    # = log p(y_i | θ_s) subtracted from total (leave-i-out)
    # Simplified: unnormalised log weights = -log_lik_matrix[s,i]
    log_weights = -log_lik_matrix

    pareto_k   = zeros(N)
    loo_scores = zeros(N)

    for i in 1:N
        lw = log_weights[:, i]
        # Centre for numerical stability
        lw_max = maximum(lw)
        w = exp.(lw .- lw_max)

        # Fit Pareto distribution to upper 20% of weights
        tail_n = max(3, round(Int, 0.2 * S))
        tail_w = sort(w; rev=true)[1:tail_n]

        # Pareto k̂: simple estimator via generalised Pareto fit
        # Using moment estimator (Zhang & Stephens 2009 simplified)
        if length(tail_w) >= 5
            sorted_tail = sort(tail_w)
            m = length(sorted_tail)
            u_threshold = sorted_tail[max(1, div(m,4))]  # threshold
            exceedances = tail_w[tail_w .> u_threshold] .- u_threshold
            if !isempty(exceedances) && mean(exceedances) > 0
                μ_e = mean(exceedances)
                σ_e = var(exceedances)
                if σ_e > 0
                    pareto_k[i] = 0.5 * (1.0 - μ_e^2 / σ_e)
                end
            end
        end

        # Cap weights at Pareto-smoothed level
        k̂ = pareto_k[i]
        if k̂ < 0.5
            # Good: standard IS
            w_norm = w ./ sum(w)
        elseif k̂ < 1.0
            # Acceptable: truncate at n^(min(1,k̂))
            cap = S^min(1.0, k̂) * mean(w)
            w_trunc = min.(w, cap)
            w_norm = w_trunc ./ sum(w_trunc)
        else
            # Bad (k̂ > 1): fall back to posterior mean
            w_norm = fill(1.0/S, S)
        end

        lk = log_lik_matrix[:, i]
        loo_scores[i] = log(sum(w_norm .* exp.(lk)))
    end

    lppd_loo = sum(loo_scores)
    # Compare to full-data lppd via WAIC formula
    pw_lppd = Float64[begin
        lk = log_lik_matrix[:, i]; m = maximum(lk)
        log(mean(exp.(lk .- m))) + m
    end for i in 1:N]
    lppd_full = sum(pw_lppd)
    p_loo = lppd_full - lppd_loo

    pw_loo_ic = -2 .* loo_scores
    se = sqrt(N * var(pw_loo_ic))
    n_bad = sum(pareto_k .> 0.7)

    LOOResult(-2*lppd_loo, lppd_loo, p_loo, se, pareto_k, n_bad, pw_loo_ic)
end

# ── Bayes Factor ──────────────────────────────────────────────────────────────

"""
    BayesFactorResult

Bayes factor comparison between two models.
BF₁₀ > 10: substantial evidence for M₁
BF₁₀ > 100: decisive evidence for M₁
"""
struct BayesFactorResult
    log_bf      :: Float64
    bf          :: Float64
    interpretation :: String
    log_ml_1    :: Float64
    log_ml_2    :: Float64
end

"""
    bayes_factor(log_lik_1, log_lik_2) -> BayesFactorResult

Approximate Bayes factor via harmonic mean estimator of marginal likelihood.
log p(y|M) ≈ -log(mean(1/p(y|θ, M)))  (Newton & Raftery 1994)
Note: harmonic mean is known to be unstable; use LOO-IC difference for robust comparison.
"""
function bayes_factor(
    log_lik_1 :: AbstractMatrix,
    log_lik_2 :: AbstractMatrix,
)
    function harmonic_mean_log_ml(ll::AbstractMatrix)
        S, N = size(ll)
        log_obs = Float64[begin
            lk = ll[:, i]
            m = minimum(lk)       # use min for -log(harmonic mean)
            -(log(S) - log(sum(exp.(-lk .+ m))) - m)
        end for i in 1:N]
        sum(log_obs)
    end

    lml1 = harmonic_mean_log_ml(log_lik_1)
    lml2 = harmonic_mean_log_ml(log_lik_2)
    log_bf = lml1 - lml2
    bf = exp(clamp(log_bf, -500.0, 500.0))

    interpretation = if log_bf > log(100)
        "Decisive evidence for M₁ (BF > 100)"
    elseif log_bf > log(10)
        "Strong evidence for M₁ (BF > 10)"
    elseif log_bf > log(3)
        "Moderate evidence for M₁ (BF > 3)"
    elseif log_bf > -log(3)
        "Inconclusive (1/3 < BF < 3)"
    elseif log_bf > -log(10)
        "Moderate evidence for M₂"
    elseif log_bf > -log(100)
        "Strong evidence for M₂"
    else
        "Decisive evidence for M₂"
    end

    BayesFactorResult(log_bf, bf, interpretation, lml1, lml2)
end

# ── Multi-model comparison ────────────────────────────────────────────────────

"""
    ModelComparison

Comparison of multiple models by WAIC and LOO-IC.
"""
struct ModelComparison
    table       :: DataFrame
    best_model  :: String
    criterion   :: Symbol
end

"""
    compare_models_bayes(models_log_lik; criterion) -> ModelComparison

Compare models using WAIC or LOO-IC.
`models_log_lik`: Dict(model_name => S×N log-likelihood matrix)
"""
function compare_models_bayes(
    models_log_lik :: Dict{String, <:AbstractMatrix};
    criterion      :: Symbol = :loo,
)
    rows = []
    for (name, ll) in models_log_lik
        if criterion == :loo
            r = loo_ic(ll)
            push!(rows, (model=name, ic=r.loo_ic, se=r.se, p_eff=r.p_loo, n_bad_k=r.n_bad_k))
        else
            r = waic(ll)
            push!(rows, (model=name, ic=r.waic, se=r.se, p_eff=r.p_waic, n_bad_k=0))
        end
    end

    df = DataFrame(rows)
    sort!(df, :ic)

    # Add ΔWAIC / ΔLOO columns
    df[!, :delta_ic] = df.ic .- df.ic[1]
    df[!, :weight]   = let
        w = exp.(-0.5 .* df.delta_ic)
        w ./ sum(w)
    end

    ModelComparison(df, df.model[1], criterion)
end

function Base.show(io::IO, mc::ModelComparison)
    println(io, "Model Comparison ($(mc.criterion))")
    println(io, "Best: $(mc.best_model)")
    show(io, mc.table; allrows=true)
end
