# validation.jl — Cross-validation, hyperparameter tuning, calibration
# Chapter 35.5

"""
    cross_validate(model_fn, X, y; folds=5, metric=:rmse, shuffle=true, rng=GLOBAL_RNG)
                  -> NamedTuple

k-fold cross-validation for any AccessModel.

`model_fn` must be a zero-arg constructor: e.g. `() -> RandomForestAccess(n_trees=50)`

Returns:
  scores      — Vector of per-fold metric values
  mean_score  — mean across folds
  std_score   — std across folds
  oof_preds   — out-of-fold predictions (length n)
"""
function cross_validate(model_fn::Function,
                        X::AbstractMatrix,
                        y::AbstractVector;
                        folds::Int = 5,
                        metric::Symbol = :rmse,
                        shuffle::Bool = true,
                        rng::AbstractRNG = Random.GLOBAL_RNG)
    n        = length(y)
    indices  = shuffle ? randperm(rng, n) : collect(1:n)
    fold_sz  = cld(n, folds)
    scores   = zeros(folds)
    oof_pred = zeros(n)

    for k in 1:folds
        val_range  = (k-1)*fold_sz+1 : min(k*fold_sz, n)
        val_idx    = indices[val_range]
        train_idx  = indices[setdiff(1:n, val_range)]

        model = model_fn()
        fit!(model, X[train_idx, :], y[train_idx])
        ŷ_val            = predict(model, X[val_idx, :])
        oof_pred[val_idx] = ŷ_val
        scores[k]         = _score(ŷ_val, y[val_idx], metric)
    end

    (scores=scores, mean_score=mean(scores), std_score=std(scores),
     oof_predictions=oof_pred, metric=metric, folds=folds)
end

"""
    tune_hyperparameters(model_class, X, y, param_grid; folds=5, metric=:rmse)
                        -> NamedTuple

Grid search hyperparameter tuning.

`param_grid` is a Dict of param_name => [values...], e.g.:
  Dict(:n_trees => [50,100,200], :max_depth => [3,5,7])

Returns: best_params, best_score, all_results (DataFrame)
"""
function tune_hyperparameters(model_class,
                               X::AbstractMatrix,
                               y::AbstractVector,
                               param_grid::Dict;
                               folds::Int = 5,
                               metric::Symbol = :rmse,
                               rng::AbstractRNG = Random.GLOBAL_RNG)
    # Build all combinations
    keys_  = collect(keys(param_grid))
    vals_  = [param_grid[k] for k in keys_]
    combos = _cartesian_product(vals_)

    results = DataFrame(score_mean=Float64[], score_std=Float64[])
    for k in keys_
        results[!, k] = []
    end

    best_score  = metric ∈ (:r2,) ? -Inf : Inf
    best_params = Dict{Symbol,Any}()

    for combo in combos
        params = Dict(keys_[i] => combo[i] for i in eachindex(keys_))
        model_fn = () -> model_class(; params...)
        cv = cross_validate(model_fn, X, y; folds=folds, metric=metric, rng=rng)
        row = merge(params, Dict(:score_mean=>cv.mean_score, :score_std=>cv.std_score))
        push!(results, (row[:score_mean], row[:score_std], [row[k] for k in keys_]...))

        better = metric ∈ (:r2,) ? cv.mean_score > best_score :
                                    cv.mean_score < best_score
        if better
            best_score  = cv.mean_score
            best_params = params
        end
    end

    (best_params=best_params, best_score=best_score, all_results=results)
end

function _cartesian_product(arrays)
    result = [[]]
    for arr in arrays
        result = [vcat(r, [v]) for r in result for v in arr]
    end
    result
end

"""
    ModelComparison

Container for comparing multiple AccessModels.
"""
struct ModelComparison
    names   ::Vector{String}
    scores  ::Dict{String, Float64}
    oof_pred::Dict{String, Vector{Float64}}
end

"""
    compare_models(models_dict, X, y; folds=5, metric=:rmse) -> ModelComparison

Run cross-validation for all models in dict and compare performance.
"""
function compare_models(models_dict::Dict{String},
                         X::AbstractMatrix,
                         y::AbstractVector;
                         folds::Int = 5,
                         metric::Symbol = :rmse)
    names = collect(keys(models_dict))
    scores  = Dict{String,Float64}()
    oof_pred = Dict{String,Vector{Float64}}()

    for (name, model_fn) in models_dict
        cv = cross_validate(model_fn, X, y; folds=folds, metric=metric)
        scores[name]   = cv.mean_score
        oof_pred[name] = cv.oof_predictions
    end
    ModelComparison(names, scores, oof_pred)
end

"""
    calibration_curve(probs, y_binary; n_bins=10) -> DataFrame

Reliability diagram data: compare predicted probabilities to actual frequencies.
Returns DataFrame with columns: prob_mean, fraction_positive, count.
"""
function calibration_curve(probs::AbstractVector,
                            y_binary::AbstractVector;
                            n_bins::Int = 10)
    edges    = range(0.0, 1.0; length=n_bins+1)
    p_mean   = Float64[]
    frac_pos = Float64[]
    counts   = Int[]
    for k in 1:n_bins
        lo, hi = edges[k], edges[k+1]
        mask   = probs .>= lo .&& probs .< hi
        sum(mask) == 0 && continue
        push!(p_mean,   mean(probs[mask]))
        push!(frac_pos, mean(Float64.(y_binary[mask])))
        push!(counts,   sum(mask))
    end
    DataFrame(prob_mean=p_mean, fraction_positive=frac_pos, count=counts)
end

"""
    brier_score(probs, y_binary) -> Float64

Brier score: mean squared difference between predicted probabilities and outcomes.
Perfect calibration → 0. Random → ~0.25.
"""
brier_score(probs, y_binary) = mean((probs .- Float64.(y_binary)).^2)
