"""
Kriging → Raster Integration

Functions for performing kriging operations on regular raster grids and
storing results with uncertainty quantification.

Grid organization follows raster convention: values stored as y×x matrices.
"""

"""
    create_regular_grid(bounds::NamedTuple, resolution_m::Float64)::RasterGrid

Create a uniform latitude/longitude grid from bounds and resolution.

# Arguments
- `bounds::NamedTuple` — Bounding box with fields (x_min, x_max, y_min, y_max)
  or (lon_min, lon_max, lat_min, lat_max)
- `resolution_m::Float64` — Grid resolution in meters

# Returns
- `RasterGrid` with x and y coordinates (empty values, all zeros)

# Conversion
- 1 degree ≈ 111 km = 111,000 m
- resolution_deg = resolution_m / 111_000.0

# Examples
```julia
bounds = (x_min=-120.0, x_max=-119.0, y_min=38.0, y_max=39.0)
grid = create_regular_grid(bounds, 1000.0)  # 1 km resolution
```
"""
function create_regular_grid(bounds::NamedTuple, resolution_m::Float64)::RasterGrid
    # Extract bounds - handle both naming conventions
    x_min = get(bounds, :x_min, get(bounds, :lon_min, bounds[1]))
    x_max = get(bounds, :x_max, get(bounds, :lon_max, bounds[2]))
    y_min = get(bounds, :y_min, get(bounds, :lat_min, bounds[3]))
    y_max = get(bounds, :y_max, get(bounds, :lat_max, bounds[4]))

    # Ensure ordering
    if x_min > x_max
        x_min, x_max = x_max, x_min
    end
    if y_min > y_max
        y_min, y_max = y_max, y_min
    end

    # Convert meters to degrees (1 degree ≈ 111 km)
    resolution_deg = resolution_m / 111_000.0

    # Create coordinate vectors
    x = collect(x_min:resolution_deg:x_max)
    y = collect(y_min:resolution_deg:y_max)

    # Remove last coordinate if it exceeds bounds
    if x[end] > x_max
        x = x[1:end-1]
    end
    if y[end] > y_max
        y = y[1:end-1]
    end

    # Create empty grid (y×x ordering)
    n_y = length(y)
    n_x = length(x)
    values = zeros(Float64, n_y, n_x)

    # Create RasterGrid with proper bounds
    bounds_named = (west=x_min, east=x_max, south=y_min, north=y_max)
    metadata = Dict{String, Any}(
        "source" => "kriging_grid",
        "created_at" => string(now()),
        "grid_type" => "regular"
    )

    grid = RasterGrid(values, x, y; crs="EPSG:4326", resolution_m=resolution_m, metadata=metadata)

    return grid
end

"""
    ordinary_kriging_grid(z::Vector, coords::Tuple, grid::RasterGrid,
                          model::VariogramModel; n_neighbors=15)::RasterGrid

Perform ordinary kriging on a regular grid.

# Arguments
- `z::Vector` — Observed values at training points
- `coords::Tuple` — (x, y) training coordinates
- `grid::RasterGrid` — Target grid with coordinates
- `model::VariogramModel` — Fitted variogram model
- `n_neighbors::Int` — Local kriging neighborhood (default: 15)

# Returns
- `RasterGrid` with predictions and variances stored in metadata["variances"]

# Implementation
1. Extract grid coordinates as Tuple{Vector, Vector}
2. Call Geostatistics.ordinary_kriging(z, coords, grid_coords, model)
3. Reshape predictions from linear to y×x matrix
4. Store variances in metadata
5. Return RasterGrid with kriging parameters

# Theory
Ordinary kriging provides unbiased minimum variance linear predictions
assuming constant (unknown) mean.
"""
function ordinary_kriging_grid(z::Vector, coords::Tuple, grid::RasterGrid,
                                model::VariogramModel; n_neighbors=15)::RasterGrid
    n_x = length(grid.x_coords)
    n_y = length(grid.y_coords)

    # Create grid point coordinates in row-major order (j×n_x + i)
    x_grid = zeros(n_x * n_y)
    y_grid = zeros(n_x * n_y)
    idx = 1
    for j in 1:n_y
        for i in 1:n_x
            x_grid[idx] = grid.x_coords[i]
            y_grid[idx] = grid.y_coords[j]
            idx += 1
        end
    end

    grid_coords = (x_grid, y_grid)

    # Call Geostatistics kriging function
    result = Geostatistics.ordinary_kriging(z, coords, grid_coords, model; n_neighbors=n_neighbors)

    # Reshape predictions to y×x matrix
    predictions_matrix = reshape_predictions(result.predictions, grid)
    variances_matrix = reshape_predictions(result.variances, grid)

    # Update grid with predictions
    grid.data[:, :] = predictions_matrix
    grid.metadata["variances"] = variances_matrix
    grid.metadata["kriging_method"] = "ordinary"
    grid.metadata["n_neighbors"] = n_neighbors
    grid.metadata["model_type"] = string(model.model_type)

    return grid
end

"""
    universal_kriging_grid(z::Vector, coords::Tuple, grid::RasterGrid,
                           model::VariogramModel; drift_order=1, n_neighbors=15)::RasterGrid

Perform universal kriging on a regular grid with polynomial drift.

# Arguments
- `z::Vector` — Observed values
- `coords::Tuple` — (x, y) training coordinates
- `grid::RasterGrid` — Target grid
- `model::VariogramModel` — Fitted variogram model
- `drift_order::Int` — Polynomial drift order (1 = linear, 2 = quadratic)
- `n_neighbors::Int` — Local kriging neighborhood

# Returns
- `RasterGrid` with drift-adjusted predictions and drift_order in metadata

# Theory
Universal kriging removes spatial trends (drift) before kriging the residuals,
allowing prediction in presence of systematic spatial variation.
"""
function universal_kriging_grid(z::Vector, coords::Tuple, grid::RasterGrid,
                                 model::VariogramModel; drift_order=1, n_neighbors=15)::RasterGrid
    # Generate grid coordinates
    n_x = length(grid.x_coords)
    n_y = length(grid.y_coords)

    x_grid = zeros(n_x * n_y)
    y_grid = zeros(n_x * n_y)
    idx = 1
    for j in 1:n_y
        for i in 1:n_x
            x_grid[idx] = grid.x_coords[i]
            y_grid[idx] = grid.y_coords[j]
            idx += 1
        end
    end

    grid_coords = (x_grid, y_grid)

    # Call Geostatistics universal kriging
    result = Geostatistics.universal_kriging(z, coords, grid_coords, model;
                                              drift_order=drift_order, n_neighbors=n_neighbors)

    # Reshape to grid
    predictions_matrix = reshape_predictions(result.predictions, grid)
    variances_matrix = reshape_predictions(result.variances, grid)

    # Update grid
    grid.data[:, :] = predictions_matrix
    grid.metadata["variances"] = variances_matrix
    grid.metadata["kriging_method"] = "universal"
    grid.metadata["drift_order"] = drift_order
    grid.metadata["n_neighbors"] = n_neighbors
    grid.metadata["model_type"] = string(model.model_type)

    return grid
end

"""
    block_kriging_grid(z::Vector, coords::Tuple, blocks::Vector,
                       grid::RasterGrid, model::VariogramModel;
                       block_size=1.0, n_neighbors=15)::RasterGrid

Perform block kriging on grid for area-level predictions.

# Arguments
- `z::Vector` — Observed values
- `coords::Tuple` — (x, y) training coordinates
- `blocks::Vector` — Block membership vector or empty (auto-assign to grid cells)
- `grid::RasterGrid` — Target grid
- `model::VariogramModel` — Fitted variogram model
- `block_size::Float64` — Block size (width of square blocks)
- `n_neighbors::Int` — Local kriging neighborhood

# Returns
- `RasterGrid` with block-averaged predictions (lower variance than point kriging)

# Theory
Block kriging predicts the average value over a spatial block rather than at a point.
This reduces variance because averaging reduces estimation error.
"""
function block_kriging_grid(z::Vector, coords::Tuple, blocks::Vector,
                            grid::RasterGrid, model::VariogramModel;
                            block_size=1.0, n_neighbors=15)::RasterGrid
    # Generate grid coordinates (block centers)
    n_x = length(grid.x_coords)
    n_y = length(grid.y_coords)

    x_grid = zeros(n_x * n_y)
    y_grid = zeros(n_x * n_y)
    idx = 1
    for j in 1:n_y
        for i in 1:n_x
            x_grid[idx] = grid.x_coords[i]
            y_grid[idx] = grid.y_coords[j]
            idx += 1
        end
    end

    grid_coords = (x_grid, y_grid)

    # Call Geostatistics block kriging
    result = Geostatistics.block_kriging(z, coords, grid_coords, model;
                                          block_size=block_size, n_neighbors=n_neighbors)

    # Reshape to grid
    predictions_matrix = reshape_predictions(result.predictions, grid)
    variances_matrix = reshape_predictions(result.variances, grid)

    # Update grid
    grid.data[:, :] = predictions_matrix
    grid.metadata["variances"] = variances_matrix
    grid.metadata["kriging_method"] = "block"
    grid.metadata["block_size"] = block_size
    grid.metadata["n_neighbors"] = n_neighbors
    grid.metadata["model_type"] = string(model.model_type)

    return grid
end

"""
    cokriging_grid(z_primary::Vector, z_auxiliary::Vector, coords::Tuple,
                   grid::RasterGrid, model_p::VariogramModel, model_cross::VariogramModel;
                   model_aux=model_p, n_neighbors=15)::RasterGrid

Perform co-kriging on grid using auxiliary variable.

# Arguments
- `z_primary::Vector` — Primary variable values (sparse, expensive)
- `z_auxiliary::Vector` — Auxiliary variable values (abundant, cheap)
- `coords::Tuple` — (x, y) training coordinates
- `grid::RasterGrid` — Target grid
- `model_p::VariogramModel` — Primary variable variogram model
- `model_cross::VariogramModel` — Cross-variogram model
- `model_aux::VariogramModel` — Auxiliary variable model (default: model_p)
- `n_neighbors::Int` — Local kriging neighborhood

# Returns
- `RasterGrid` with co-kriging predictions and auxiliary predictions in metadata

# Theory
Co-kriging leverages correlation with auxiliary variable to improve predictions
of primary variable. Useful when primary is sparse but auxiliary is abundant
(e.g., provider density estimated from population).
"""
function cokriging_grid(z_primary::Vector, z_auxiliary::Vector, coords::Tuple,
                        grid::RasterGrid, model_p::VariogramModel, model_cross::VariogramModel;
                        model_aux=model_p, n_neighbors=15)::RasterGrid
    # Generate grid coordinates
    n_x = length(grid.x_coords)
    n_y = length(grid.y_coords)

    x_grid = zeros(n_x * n_y)
    y_grid = zeros(n_x * n_y)
    idx = 1
    for j in 1:n_y
        for i in 1:n_x
            x_grid[idx] = grid.x_coords[i]
            y_grid[idx] = grid.y_coords[j]
            idx += 1
        end
    end

    grid_coords = (x_grid, y_grid)

    # Call Geostatistics co-kriging
    result = Geostatistics.cokriging(z_primary, z_auxiliary, coords, grid_coords,
                                      model_p, model_cross; model_auxiliary=model_aux,
                                      n_neighbors=n_neighbors)

    # Reshape to grid
    predictions_matrix = reshape_predictions(result.predictions, grid)
    variances_matrix = reshape_predictions(result.variances, grid)
    aux_predictions_matrix = reshape_predictions(result.aux_predictions, grid)

    # Update grid
    grid.data[:, :] = predictions_matrix
    grid.metadata["variances"] = variances_matrix
    grid.metadata["aux_predictions"] = aux_predictions_matrix
    grid.metadata["kriging_method"] = "cokriging"
    grid.metadata["n_primary"] = result.n_primary
    grid.metadata["n_auxiliary"] = result.n_auxiliary
    grid.metadata["n_neighbors"] = n_neighbors
    grid.metadata["model_type"] = string(model_p.model_type)

    return grid
end

"""
    extract_raster_values(raster::RasterGrid, coords::Tuple)::Vector

Sample raster values at arbitrary coordinates using nearest-neighbor interpolation.

# Arguments
- `raster::RasterGrid` — Source raster grid
- `coords::Tuple` — (x, y) coordinates to sample

# Returns
- `Vector` of interpolated values at coordinates

# Implementation
Uses nearest-neighbor interpolation between grid cells. Returns NaN if coordinates
are outside grid bounds.
"""
function extract_raster_values(raster::RasterGrid, coords::Tuple)::Vector
    n_points = length(coords[1])
    values = zeros(n_points)

    for p in 1:n_points
        x = coords[1][p]
        y = coords[2][p]

        # Find nearest grid indices
        x_idx = searchsortednearest(raster.x_coords, x)
        y_idx = searchsortednearest(raster.y_coords, y)

        # Check bounds
        if x_idx < 1 || x_idx > length(raster.x_coords) ||
           y_idx < 1 || y_idx > length(raster.y_coords)
            values[p] = NaN
            continue
        end

        # Nearest-neighbor value
        values[p] = raster.data[y_idx, x_idx]
    end

    return values
end

"""
    searchsortednearest(arr::Vector, x)::Int

Find the index of nearest element in sorted array.
"""
function searchsortednearest(arr::Vector, x)
    idx = searchsortedfirst(arr, x)
    if idx > length(arr)
        return length(arr)
    elseif idx == 1
        return 1
    else
        # Return index of nearest element
        if abs(arr[idx] - x) < abs(arr[idx-1] - x)
            return idx
        else
            return idx - 1
        end
    end
end

"""
    reshape_predictions(predictions::Vector, grid::RasterGrid)::Matrix

Reshape kriging predictions from linear to y×x matrix form.

# Arguments
- `predictions::Vector` — Linear array of predictions (n_x * n_y points)
- `grid::RasterGrid` — Grid with coordinate dimensions

# Returns
- `Matrix` in y×x ordering (n_y × n_x)

# Ordering
Predictions are generated in row-major order (j×n_x + i) to match
how grid points are created in kriging_grid.jl.

y-axis is rows, x-axis is columns.
"""
function reshape_predictions(predictions::Vector, grid::RasterGrid)::Matrix
    n_x = length(grid.x_coords)
    n_y = length(grid.y_coords)

    matrix = zeros(n_y, n_x)

    idx = 1
    for j in 1:n_y
        for i in 1:n_x
            matrix[j, i] = predictions[idx]
            idx += 1
        end
    end

    return matrix
end

"""
    create_uncertainty_surface(variances::Vector, grid::RasterGrid)::RasterGrid

Generate confidence interval surface from kriging variances.

# Arguments
- `variances::Vector` — Kriging variances from predictions
- `grid::RasterGrid` — Target grid

# Returns
- `RasterGrid` with 95% confidence interval (±1.96σ) stored in values

# Theory
Kriging provides point predictions ẑ(x₀) and variances σ²(x₀).
Standard error = σ = √(variance)
95% CI = [ẑ - 1.96σ, ẑ + 1.96σ]
"""
function create_uncertainty_surface(variances::Vector, grid::RasterGrid)::RasterGrid
    # Reshape variances to matrix
    variance_matrix = reshape_predictions(variances, grid)

    # Compute standard errors and CI width
    stderr_matrix = sqrt.(variance_matrix)
    ci_width = 1.96 .* stderr_matrix  # 95% CI half-width

    # Create new grid with CI widths
    uncertainty_grid = RasterGrid(ci_width, grid.x_coords, grid.y_coords,
                                   grid.crs, grid.bounds, grid.resolution_m, copy(grid.metadata))

    uncertainty_grid.metadata["type"] = "confidence_interval_95"
    uncertainty_grid.metadata["base_variances"] = variance_matrix

    return uncertainty_grid
end
