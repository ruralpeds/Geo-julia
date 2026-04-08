# report.jl — Reporting and analysis utilities for DeepHealth
# Chapter 45 — Open-Source Healthcare GIS Textbook in Julia

"""
    DeepHealthReport

Summary of a trained DeepHealth model including architecture, metrics,
training curves, and feature attribution.
"""
struct DeepHealthReport
    model_name     :: String
    n_params       :: Int
    task           :: Symbol
    train_metrics  :: NamedTuple
    val_metrics    :: Union{NamedTuple, Nothing}
    train_history  :: Union{TrainingHistory, Nothing}
    feature_names  :: Vector{String}
    importance     :: Vector{Float64}   # permutation importance scores
    timestamp      :: String
end

"""
    deep_health_report(net, X_train, y_train; X_val, y_val, feature_names, task, name)

Generate a comprehensive report for a trained MLP model.
"""
function deep_health_report(
    net          :: MLP,
    X_train      :: AbstractMatrix,
    y_train      :: AbstractVecOrMat;
    X_val        :: Union{AbstractMatrix, Nothing} = nothing,
    y_val        :: Union{AbstractVecOrMat, Nothing} = nothing,
    feature_names :: Vector{String} = String[],
    task         :: Symbol = :regression,
    name         :: String = "DeepHealth MLP",
    history      :: Union{TrainingHistory, Nothing} = nothing,
    n_perm       :: Int = 20,
    rng                  = Random.GLOBAL_RNG,
)
    n_p = n_params(net)

    if isempty(feature_names)
        feature_names = ["f$(i)" for i in 1:size(X_train, 1)]
    end

    train_m = evaluate_model(net, X_train,
                             y_train isa AbstractMatrix ? y_train : reshape(y_train, 1, :);
                             task=task)

    val_m = nothing
    if !isnothing(X_val) && !isnothing(y_val)
        yv = y_val isa AbstractMatrix ? y_val : reshape(y_val, 1, :)
        val_m = evaluate_model(net, X_val, yv; task=task)
    end

    # Permutation feature importance
    imp = permutation_importance_deep(net, X_train, y_train; task=task, n_perm=n_perm, rng=rng)

    ts = string(Dates.now())
    DeepHealthReport(name, n_p, task, train_m, val_m, history,
                     feature_names, imp, ts)
end

"""
    permutation_importance_deep(net, X, y; task, n_perm) -> Vector{Float64}

Compute permutation feature importance: for each feature j,
shuffle column j and compute the increase in loss.
"""
function permutation_importance_deep(
    net   :: MLP,
    X     :: AbstractMatrix,
    y     :: AbstractVecOrMat;
    task  :: Symbol = :regression,
    n_perm :: Int = 20,
    rng          = Random.GLOBAL_RNG,
)
    yv = y isa AbstractMatrix ? y : reshape(y, 1, :)
    loss_fn = task == :regression ? mse_loss : bce_loss

    baseline_loss = loss_fn(forward(net, X; training=false), yv)
    n_feat = size(X, 1)
    importances = zeros(n_feat)

    for j in 1:n_feat
        drop = 0.0
        for _ in 1:n_perm
            X_perm = copy(X)
            X_perm[j, :] = X_perm[j, randperm(rng, size(X, 2))]
            perm_loss = loss_fn(forward(net, X_perm; training=false), yv)
            drop += perm_loss - baseline_loss
        end
        importances[j] = drop / n_perm
    end

    # Normalise to [0,1]
    mn = minimum(importances)
    mx = maximum(importances)
    denom = mx - mn
    denom < 1e-12 ? fill(1.0/n_feat, n_feat) : (importances .- mn) ./ denom
end

"""
    training_summary(history) -> DataFrame

Convert a TrainingHistory to a tidy DataFrame for plotting.
"""
function training_summary(history::TrainingHistory)
    n = length(history.train_loss)
    df = DataFrame(
        epoch       = 1:n,
        train_loss  = history.train_loss,
    )
    if !isempty(history.val_loss)
        nv = length(history.val_loss)
        val_col = vcat(history.val_loss, fill(NaN, n - nv))
        df[!, :val_loss] = val_col
    end
    df
end

"""
    Base.show(io, r::DeepHealthReport)

Pretty-print a DeepHealthReport.
"""
function Base.show(io::IO, r::DeepHealthReport)
    println(io, "┌─ DeepHealthReport: $(r.model_name)")
    println(io, "│  Parameters:   $(r.n_params)")
    println(io, "│  Task:         $(r.task)")
    if r.task == :regression
        println(io, "│  Train RMSE:   $(round(r.train_metrics.rmse; digits=4))")
        println(io, "│  Train R²:     $(round(r.train_metrics.r2; digits=4))")
        if !isnothing(r.val_metrics)
            println(io, "│  Val RMSE:     $(round(r.val_metrics.rmse; digits=4))")
        end
    else
        println(io, "│  Train AUC:    $(round(r.train_metrics.auc; digits=4))")
        if !isnothing(r.val_metrics)
            println(io, "│  Val AUC:      $(round(r.val_metrics.auc; digits=4))")
        end
    end
    if !isnothing(r.train_history)
        println(io, "│  Epochs:       $(r.train_history.epochs) (best: $(r.train_history.best_epoch))")
    end
    println(io, "│  Top features:")
    order = sortperm(r.importance; rev=true)
    for i in 1:min(5, length(order))
        j = order[i]
        nm = j <= length(r.feature_names) ? r.feature_names[j] : "f$(j)"
        println(io, "│    $(lpad(i,2)). $(rpad(nm, 20)) $(round(r.importance[j]; digits=3))")
    end
    print(io,   "└─ Generated: $(r.timestamp)")
end
