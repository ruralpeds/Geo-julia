# explainability.jl — SHAP values, permutation importance, partial dependence
# Chapter 35.4 — Interpretable ML for Healthcare Access

"""
    permutation_importance(model, X, y; n_repeats=10, metric=:rmse, rng=GLOBAL_RNG)
              -> DataFrame

Breiman (2001) permutation feature importance.
For each feature j:
  1. Permute column j randomly
  2. score_j = metric(model, X_permuted, y) - baseline_score
  3. Repeat n_repeats times, report mean ± std

Returns DataFrame with columns: feature_index, importance_mean, importance_std,
sorted descending by importance_mean.
"""
function permutation_importance(model::AccessModel,
                                 X::AbstractMatrix,
                                 y::AbstractVector;
                                 feature_names::Vector{String} = String[],
                                 n_repeats::Int = 10,
                                 metric::Symbol = :rmse,
                                 rng::AbstractRNG = Random.GLOBAL_RNG)
    n, p = size(X)
    fn = isempty(feature_names) ? ["x$i" for i in 1:p] : feature_names

    ŷ_base    = predict(model, X)
    base_score = _score(ŷ_base, y, metric)

    imps = zeros(p, n_repeats)
    X_perm = copy(X)
    for j in 1:p
        orig_col = copy(X[:, j])
        for rep in 1:n_repeats
            X_perm[:, j] = orig_col[randperm(rng, n)]
            ŷ_perm        = predict(model, X_perm)
            imps[j, rep]  = _score(ŷ_perm, y, metric) - base_score
        end
        X_perm[:, j] = orig_col
    end

    df = DataFrame(
        feature       = fn,
        importance_mean = vec(mean(imps; dims=2)),
        importance_std  = vec(std(imps; dims=2)),
    )
    sort!(df, :importance_mean; rev=true)
end

function _score(ŷ, y, metric)
    r = ŷ .- y
    metric == :rmse ? sqrt(mean(r.^2)) :
    metric == :mae  ? mean(abs.(r))    :
    metric == :r2   ? 1.0 - sum(r.^2)/max(sum((y .- mean(y)).^2), 1e-9) : sqrt(mean(r.^2))
end

"""
    partial_dependence(model, X, feature_j; grid_points=50) -> DataFrame

Compute the partial dependence plot (PDP) for feature j.
PDP(x_j) = (1/n) Σᵢ f(x_j, X_{-j,i})   [Friedman 2001]

Returns DataFrame with columns: value (grid), pdp (mean prediction).
"""
function partial_dependence(model::AccessModel,
                             X::AbstractMatrix,
                             feature_j::Int;
                             grid_points::Int = 50)
    n, p = size(X)
    grid = range(minimum(X[:, feature_j]), maximum(X[:, feature_j]); length=grid_points)
    pdp  = zeros(grid_points)
    X_copy = copy(X)
    for (k, val) in enumerate(grid)
        X_copy[:, feature_j] .= val
        pdp[k] = mean(predict(model, X_copy))
    end
    X_copy[:, feature_j] .= X[:, feature_j]  # restore
    DataFrame(value=collect(grid), pdp=pdp)
end

"""
    shap_values(model, X; n_samples=100, rng=GLOBAL_RNG) -> Matrix{Float64}

Approximate SHAP values via Kernel SHAP (Lundberg & Lee 2017).
Returns (n × p) matrix of SHAP values.

Algorithm:
  For each observation i:
    Sample coalition vectors z ∈ {0,1}^p (random feature inclusion)
    f(z) = E[model(X) | X_j = x_{i,j} if z_j=1, X_j ~ background if z_j=0]
    Fit weighted linear model φ on (z, f(z)) with kernel weights:
      w(z) = (p-1) / [C(p, |z|) · |z| · (p - |z|)]
    φ = SHAP values for observation i
"""
function shap_values(model::AccessModel,
                     X::AbstractMatrix;
                     background::Union{AbstractMatrix,Nothing} = nothing,
                     n_samples::Int = 100,
                     rng::AbstractRNG = Random.GLOBAL_RNG)
    n, p = size(X)
    bg = isnothing(background) ? X : background
    n_bg = size(bg, 1)

    shap_mat = zeros(n, p)

    for i in 1:n
        xi = X[i, :]

        # Sample coalition vectors
        coalitions = rand(rng, Bool, n_samples, p)
        # Always include all-zeros and all-ones
        coalitions[1, :] .= false
        coalitions[2, :] .= true

        f_vals = zeros(n_samples)
        for s in 1:n_samples
            z  = coalitions[s, :]
            # Marginalise over background where z_j = 0
            X_interp = copy(bg)
            for j in 1:p
                z[j] && (X_interp[:, j] .= xi[j])
            end
            f_vals[s] = mean(predict(model, X_interp))
        end

        # Kernel SHAP weights
        sizes = vec(sum(coalitions; dims=2))
        weights = zeros(n_samples)
        for s in 1:n_samples
            sz = sizes[s]
            (sz == 0 || sz == p) && (weights[s] = 1e6; continue)
            weights[s] = (p - 1) / max(_binomial(p, sz) * sz * (p - sz), 1e-9)
        end

        # Weighted linear regression: φ = (Z'WZ)⁻¹ Z'Wf
        Z = Float64.(coalitions)
        W = Diagonal(weights)
        ZWZ = Z' * W * Z + 1e-9 * I
        ZWf = Z' * W * f_vals
        φ = ZWZ \ ZWf
        shap_mat[i, :] = φ
    end
    shap_mat
end

function _binomial(n::Int, k::Int)
    k < 0 || k > n && return 0
    k == 0 || k == n && return 1
    k > n - k && (k = n - k)
    result = 1
    for i in 0:k-1
        result = result * (n - i) ÷ (i + 1)
    end
    result
end

using LinearAlgebra: Diagonal, I
