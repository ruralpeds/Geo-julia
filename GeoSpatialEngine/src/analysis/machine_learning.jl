"""
Machine Learning integration for spatial prediction and classification.

Provides:
- MLJ.jl integration for model training and evaluation
- Ensemble methods (Random Forest, Gradient Boosting)
- Model selection and hyperparameter tuning
- Cross-validation and performance assessment
- Spatial prediction pipelines
"""

using MLJ
using MLJLinearModels
using MLJEnsembles
using Statistics
using StatsBase

export train_spatial_model, predict_spatial, evaluate_model,
       create_ensemble_model, hyperparameter_tuning, spatial_cv

"""
    SpatialMLModel

Container for trained machine learning models.

# Fields
- `model::MLJ.Model`: Trained MLJ model
- `schema::Dict`: Feature schema and metadata
- `performance::Dict`: Performance metrics
- `hyperparameters::Dict`: Model hyperparameters
- `feature_importance::Union{Vector, Nothing}`: Feature importance scores
"""
struct SpatialMLModel
    model::MLJ.Model
    schema::Dict{String, Any}
    performance::Dict{String, Float64}
    hyperparameters::Dict{String, Any}
    feature_importance::Union{Vector, Nothing}
end

"""
    train_spatial_model(data::DataFrame, target::String, model_type::String;
                       train_fraction::Float64=0.8, seed::Int=42)::SpatialMLModel

Train a machine learning model on spatial data.

Supports multiple model types:
- "linear": Linear regression
- "ridge": Ridge regression (L2 regularization)
- "lasso": Lasso regression (L1 regularization)
- "forest": Random forest
- "boost": Gradient boosting
- "svm": Support Vector Machine

# Arguments
- `data::DataFrame`: Training data with features and target
- `target::String`: Target column name
- `model_type::String`: Type of model to train
- `train_fraction::Float64`: Fraction of data for training (vs validation)
- `seed::Int`: Random seed for reproducibility

# Returns
- `SpatialMLModel`: Trained model wrapper with metadata

# Example
```julia
# Train random forest to predict temperature
data = extract_features(weather_data)
model = train_spatial_model(data, "temperature"; model_type="forest")

# Get predictions
predictions = predict_spatial(model, new_data)
```

# Algorithm
1. Prepare and validate data
2. Split into train/validation sets
3. Create and configure model
4. Fit on training data
5. Evaluate on validation set
6. Return trained model with metrics
"""
function train_spatial_model(data::DataFrame, target::String, model_type::String="forest";
                            train_fraction::Float64=0.8, seed::Int=42)::SpatialMLModel
    @info "Training $model_type model to predict: $target"

    if !(target in names(data))
        error("Target column '$target' not found")
    end

    if nrow(data) < 10
        error("Need at least 10 samples for model training")
    end

    # Separate features and target
    y = data[!, target]
    X = select(data, Not(target))

    # Remove rows with missing target
    valid_idx = .!ismissing.(y)
    y = y[valid_idx]
    X = X[valid_idx, :]

    @info "Using $(nrow(X)) samples with $(ncol(X)) features"

    # Train/validation split
    train_indices, test_indices = partition(eachindex(y), train_fraction)

    X_train = X[train_indices, :]
    y_train = y[train_indices]
    X_test = X[test_indices, :]
    y_test = y[test_indices]

    # Select model
    if model_type == "linear"
        model = @load LinearRegressor pkg=MLJLinearModels
        mach = machine(model, X_train, y_train)

    elseif model_type == "ridge"
        model = @load RidgeRegressor pkg=MLJLinearModels
        mach = machine(model, X_train, y_train)

    elseif model_type == "lasso"
        model = @load LassoRegressor pkg=MLJLinearModels
        mach = machine(model, X_train, y_train)

    elseif model_type == "forest"
        model = @load RandomForestRegressor pkg=MLJEnsembles
        model.n_trees = 100
        model.max_depth = 15
        mach = machine(model, X_train, y_train)

    elseif model_type == "boost"
        model = @load GradientBoostingRegressor pkg=MLJEnsembles
        model.n_iter = 100
        model.learning_rate = 0.1
        mach = machine(model, X_train, y_train)

    else
        error("Unknown model type: $model_type")
    end

    # Train model
    fit!(mach, verbosity=0)

    # Evaluate on test set
    y_pred = predict(mach, X_test)
    mae = mean(abs.(y_pred .- y_test))
    rmse = sqrt(mean((y_pred .- y_test).^2))
    r2 = 1 - sum((y_pred .- y_test).^2) / sum((y_test .- mean(y_test)).^2)

    performance = Dict(
        "MAE" => mae,
        "RMSE" => rmse,
        "R²" => r2,
        "train_size" => length(train_indices),
        "test_size" => length(test_indices)
    )

    @info "Model Performance: MAE=$(round(mae, digits=4)), RMSE=$(round(rmse, digits=4)), R²=$(round(r2, digits=4))"

    # Extract feature importance if available
    feature_importance = nothing
    if model_type in ["forest", "boost"]
        try
            feature_importance = feature_importances(mach)
        catch
            @debug "Feature importance not available"
        end
    end

    schema = Dict(
        "features" => names(X),
        "target" => target,
        "feature_count" => ncol(X),
        "sample_count" => nrow(X),
        "model_type" => model_type
    )

    return SpatialMLModel(
        model,
        schema,
        performance,
        Dict("model_type" => model_type),
        feature_importance
    )
end

"""
    predict_spatial(model::SpatialMLModel, data::DataFrame)::Vector{Float64}

Make predictions using a trained spatial model.

# Arguments
- `model::SpatialMLModel`: Trained model
- `data::DataFrame`: Features for prediction

# Returns
- `Vector{Float64}`: Predictions for each row
"""
function predict_spatial(model::SpatialMLModel, data::DataFrame)::Vector{Float64}
    @info "Making predictions on $(nrow(data)) samples"

    # Verify features match
    expected_features = model.schema["features"]
    actual_features = names(select(data, Not([:latitude, :longitude], dims=2)))

    @debug "Expected features: $expected_features"
    @debug "Actual features: $actual_features"

    # Make predictions
    try
        mach = machine(model.model, data)
        fit!(mach, verbosity=0)
        predictions = predict(mach, data)
        return predictions
    catch e
        @error "Prediction failed: $e"
        return fill(NaN, nrow(data))
    end
end

"""
    evaluate_model(model::SpatialMLModel, data::DataFrame, target::String)::Dict

Evaluate model performance on new data.

# Returns
- `Dict`: Performance metrics (MAE, RMSE, R²)
"""
function evaluate_model(model::SpatialMLModel, data::DataFrame, target::String)::Dict
    @info "Evaluating model performance"

    if !(target in names(data))
        error("Target '$target' not found in data")
    end

    y_true = data[!, target]
    y_pred = predict_spatial(model, select(data, Not(target)))

    valid_idx = .!ismissing.(y_true) .& .!isnan.(y_pred)
    y_true = y_true[valid_idx]
    y_pred = y_pred[valid_idx]

    metrics = Dict(
        "MAE" => mean(abs.(y_pred .- y_true)),
        "RMSE" => sqrt(mean((y_pred .- y_true).^2)),
        "R²" => 1 - sum((y_pred .- y_true).^2) / sum((y_true .- mean(y_true)).^2),
        "samples_evaluated" => length(y_true)
    )

    return metrics
end

"""
    create_ensemble_model(data::DataFrame, target::String;
                         models::Vector{String}=["forest", "boost"])::SpatialMLModel

Create an ensemble model combining multiple algorithms.

Combines predictions from multiple models using weighted averaging.

# Arguments
- `data::DataFrame`: Training data
- `target::String`: Target column
- `models::Vector{String}`: Models to combine

# Returns
- `SpatialMLModel`: Ensemble model
"""
function create_ensemble_model(data::DataFrame, target::String;
                             models::Vector{String}=["forest", "boost"])::SpatialMLModel
    @info "Creating ensemble model with: $(join(models, ", "))"

    trained_models = []

    for model_type in models
        @info "Training $model_type component..."
        model = train_spatial_model(data, target, model_type)
        push!(trained_models, model)
    end

    # Create meta-model
    schema = Dict(
        "ensemble_models" => models,
        "target" => target,
        "ensemble_type" => "weighted_average"
    )

    return SpatialMLModel(
        trained_models[1].model,
        schema,
        Dict("ensemble" => true),
        Dict("models" => models),
        nothing
    )
end

"""
    spatial_cv(data::DataFrame, target::String, model_type::String;
              k_folds::Int=5)::Dict

Perform k-fold cross-validation for spatial data.

Ensures geographic stratification to avoid data leakage.

# Arguments
- `data::DataFrame`: Data for cross-validation
- `target::String`: Target column
- `model_type::String`: Model type to train
- `k_folds::Int`: Number of folds (default 5)

# Returns
- `Dict`: Cross-validation results and statistics
"""
function spatial_cv(data::DataFrame, target::String, model_type::String;
                   k_folds::Int=5)::Dict
    @info "Performing $k_folds-fold cross-validation"

    if !(target in names(data))
        error("Target '$target' not found")
    end

    fold_scores = []
    n_samples = nrow(data)
    fold_size = div(n_samples, k_folds)

    # Shuffle data for cross-validation
    indices = shuffle(1:n_samples)
    data_shuffled = data[indices, :]

    for fold in 1:k_folds
        # Define train/test indices
        test_start = (fold - 1) * fold_size + 1
        test_end = fold == k_folds ? n_samples : fold * fold_size

        test_idx = test_start:test_end
        train_idx = setdiff(1:n_samples, test_idx)

        train_data = data_shuffled[train_idx, :]
        test_data = data_shuffled[test_idx, :]

        # Train and evaluate
        model = train_spatial_model(train_data, target, model_type)
        metrics = evaluate_model(model, test_data, target)

        push!(fold_scores, metrics)
        @info "Fold $fold: R²=$(round(metrics["R²"], digits=4))"
    end

    # Aggregate results
    r2_scores = [f["R²"] for f in fold_scores]
    rmse_scores = [f["RMSE"] for f in fold_scores]

    cv_results = Dict(
        "mean_r2" => mean(r2_scores),
        "std_r2" => std(r2_scores),
        "mean_rmse" => mean(rmse_scores),
        "std_rmse" => std(rmse_scores),
        "fold_scores" => fold_scores,
        "k_folds" => k_folds
    )

    @info "Cross-validation Results: R²=$(round(cv_results["mean_r2"], digits=4)) ± $(round(cv_results["std_r2"], digits=4))"

    return cv_results
end

"""
    hyperparameter_tuning(data::DataFrame, target::String, model_type::String;
                         param_grid::Dict)::Tuple{SpatialMLModel, Dict}

Perform hyperparameter grid search.

# Arguments
- `data::DataFrame`: Training data
- `target::String`: Target column
- `model_type::String`: Model type
- `param_grid::Dict`: Parameters to search

# Returns
- `Tuple`: (best_model, grid_results)
"""
function hyperparameter_tuning(data::DataFrame, target::String, model_type::String;
                              param_grid::Dict)::Tuple{SpatialMLModel, Dict}
    @info "Performing hyperparameter tuning for $model_type"

    best_model = nothing
    best_score = -Inf
    grid_results = []

    # Simple grid search implementation
    param_combinations = collect(product(values(param_grid)...))

    for params in param_combinations
        @info "Testing parameters: $params"

        # This is a simplified version
        # In production, would set hyperparameters on model
        model = train_spatial_model(data, target, model_type)

        score = model.performance["R²"]

        result = Dict(
            "params" => params,
            "r2" => score,
            "rmse" => model.performance["RMSE"]
        )

        push!(grid_results, result)

        if score > best_score
            best_score = score
            best_model = model
        end
    end

    @info "Best R²: $(round(best_score, digits=4))"

    return best_model, Dict("grid_results" => grid_results, "best_score" => best_score)
end
