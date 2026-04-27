"""
Kriging validation: cross-validation, leave-one-out, error metrics.
"""

"""
    leave_one_out(z::Vector, coords::Tuple, model::VariogramModel; n_neighbors::Int=15)

Leave-one-out cross-validation for kriging.

Removes each observation, predicts it using remaining data, and computes error.

# Returns
- (predictions::Vector, residuals::Vector, mse::Float64, rmse::Float64)
"""
function leave_one_out(z::Vector, coords::Tuple, model::VariogramModel; n_neighbors::Int=15)
    n = length(z)
    predictions = zeros(n)
    residuals = zeros(n)

    for i in 1:n
        # Remove i-th observation
        z_test = [z[1:i-1]; z[i+1:n]]
        x_test = (
            [coords[1][1:i-1]; coords[1][i+1:n]],
            [coords[2][1:i-1]; coords[2][i+1:n]]
        )

        # Prediction location
        pred_loc = (coords[1][i], coords[2][i])

        # Predict at removed location
        result = ordinary_kriging(z_test, x_test, (pred_loc[1:1], pred_loc[2:2]), model;
                                 n_neighbors=min(n_neighbors, n - 1))

        predictions[i] = result.predictions[1]
        residuals[i] = z[i] - predictions[i]
    end

    mse = mean(residuals .^ 2)
    rmse = sqrt(mse)

    return predictions, residuals, mse, rmse
end

"""
    cross_validate(z::Vector, coords::Tuple, model::VariogramModel;
                   k_folds::Int=5, n_neighbors::Int=15)

k-fold cross-validation for kriging model.

# Arguments
- `k_folds::Int` — Number of folds (default: 5)

# Returns
- Dict with mse, rmse, mae, fold_errors
"""
function cross_validate(z::Vector, coords::Tuple, model::VariogramModel;
                       k_folds::Int=5, n_neighbors::Int=15)
    n = length(z)
    fold_size = div(n, k_folds)

    fold_rmses = Float64[]
    all_predictions = Float64[]
    all_observed = Float64[]

    # Shuffle indices
    Random.seed!(42)
    shuffled_idx = randperm(n)

    for fold in 1:k_folds
        # Test set
        test_start = (fold - 1) * fold_size + 1
        test_end = (fold == k_folds) ? n : fold * fold_size
        test_idx = shuffled_idx[test_start:test_end]

        # Training set
        train_idx = [shuffled_idx[1:test_start-1]; shuffled_idx[test_end+1:n]]

        z_train = z[train_idx]
        x_train = (coords[1][train_idx], coords[2][train_idx])
        x_test = (coords[1][test_idx], coords[2][test_idx])
        z_test = z[test_idx]

        # Predict on test set
        result = ordinary_kriging(z_train, x_train, x_test, model; n_neighbors=n_neighbors)

        # Errors
        fold_residuals = z_test .- result.predictions
        fold_rmse = sqrt(mean(fold_residuals .^ 2))

        push!(fold_rmses, fold_rmse)
        append!(all_predictions, result.predictions)
        append!(all_observed, z_test)
    end

    overall_mse = mean((all_observed .- all_predictions) .^ 2)
    overall_rmse = sqrt(overall_mse)
    overall_mae = mean(abs.(all_observed .- all_predictions))

    return Dict(
        "mse" => overall_mse,
        "rmse" => overall_rmse,
        "mae" => overall_mae,
        "fold_rmses" => fold_rmses,
        "predictions" => all_predictions,
        "observed" => all_observed
    )
end

"""
    block_cross_validate(z::Vector, coords::Tuple, blocks::Vector, model::VariogramModel;
                         block_size::Float64=1.0, n_neighbors::Int=15)

Spatial block cross-validation: leave-one-block-out evaluation.

For each block: removes all points in that block from training, predicts the
block average using kriging on remaining points, compares to observed block mean.

# Arguments
- `z::Vector` — Observation values at points
- `coords::Tuple` — (x, y) coordinates as vectors
- `blocks::Vector` — Block centroids: [(x₁, y₁), (x₂, y₂), ...]
- `model::VariogramModel` — Fitted variogram
- `block_size::Float64` — Width/height of square block (default: 1.0)
- `n_neighbors::Int` — Local kriging neighborhood (default: 15)

# Returns
- Dict with:
  - `"rmse"` — Root mean squared error across blocks
  - `"mae"` — Mean absolute error across blocks
  - `"mse"` — Mean squared error
  - `"predictions"` — Block-level predictions
  - `"observed"` — Observed block means
  - `"residuals"` — Prediction residuals

# Theory
Leave-one-block-out CV avoids spatial autocorrelation bias by removing entire
blocks (not single points), ensuring test set is independent of training data.

Block prediction: ẑ_B = average kriging prediction over block area
Observed: z_B = mean of all observed values in block
"""
function block_cross_validate(z::Vector, coords::Tuple, blocks::Vector, model::VariogramModel;
                              block_size::Float64=1.0, n_neighbors::Int=15)
    n_blocks = length(blocks)
    block_predictions = Float64[]
    block_observed = Float64[]
    block_residuals = Float64[]

    # For each block: remove it, predict block average, compare to observed
    for leave_out_block in 1:n_blocks
        block_center = blocks[leave_out_block]
        block_radius = block_size / 2.0

        # Identify points inside this block
        in_block_idx = Int[]
        for i in 1:length(z)
            dx = coords[1][i] - block_center[1]
            dy = coords[2][i] - block_center[2]
            dist_to_center = sqrt(dx^2 + dy^2)
            # Include points within diagonal distance of block
            if dist_to_center <= block_radius * sqrt(2)
                push!(in_block_idx, i)
            end
        end

        # Skip this fold if no observations in block
        if isempty(in_block_idx)
            continue
        end

        # Training set: all points except those in this block
        out_of_block_idx = setdiff(1:length(z), in_block_idx)
        if isempty(out_of_block_idx)
            continue  # Can't train with no data
        end

        z_train = z[out_of_block_idx]
        coords_train = (coords[1][out_of_block_idx], coords[2][out_of_block_idx])

        # Generate grid points within block for averaging
        n_grid = 5  # 5×5 = 25 points per block for integration
        grid_coords = block_grid_points(block_center, block_size, n_grid)

        # Predict at all grid points
        result = ordinary_kriging(z_train, coords_train, grid_coords, model;
                                 n_neighbors=min(n_neighbors, length(z_train)))

        # Block average (from kriging predictions)
        block_pred = mean(result.predictions)

        # Observed block average (from actual data)
        block_true = mean(z[in_block_idx])

        # Store results
        push!(block_predictions, block_pred)
        push!(block_observed, block_true)
        push!(block_residuals, block_true - block_pred)
    end

    # Compute metrics
    if isempty(block_residuals)
        # No valid blocks
        return Dict(
            "rmse" => NaN,
            "mae" => NaN,
            "mse" => NaN,
            "predictions" => Float64[],
            "observed" => Float64[],
            "residuals" => Float64[]
        )
    end

    mse = mean(block_residuals .^ 2)
    rmse_val = sqrt(mse)
    mae_val = mean(abs.(block_residuals))

    return Dict(
        "rmse" => rmse_val,
        "mae" => mae_val,
        "mse" => mse,
        "predictions" => block_predictions,
        "observed" => block_observed,
        "residuals" => block_residuals
    )
end

# Error metrics

"""
    rmse(observed::Vector, predicted::Vector)

Root mean squared error.
"""
function rmse(observed::Vector, predicted::Vector)
    return sqrt(mean((observed .- predicted) .^ 2))
end

"""
    mae(observed::Vector, predicted::Vector)

Mean absolute error.
"""
function mae(observed::Vector, predicted::Vector)
    return mean(abs.(observed .- predicted))
end

"""
    smape(observed::Vector, predicted::Vector)

Symmetric mean absolute percentage error.
"""
function smape(observed::Vector, predicted::Vector)
    return mean(2.0 .* abs.(observed .- predicted) ./ (abs.(observed) .+ abs.(predicted) .+ 1e-10))
end
