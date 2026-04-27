"""
    validation.jl

Raster validation and quality assessment for fused population grids.

Functions:
- raster_cross_validate: Extract and compare values at validation points
- fusion_quality_report: Compute coefficient of variation and confidence
- inter_source_agreement: Spatial agreement between sources

Reference: Cross-validation metrics for spatial interpolation (Cressie 1991).
"""

using LinearAlgebra, Statistics

"""
    raster_cross_validate(sources::Vector{RasterGrid{T}}, val_coords::Tuple, val_values::Vector)::Dict where T<:Real

Cross-validate multiple rasters against known validation points.

Extracts predicted values from each raster at validation coordinates and compares
to observed values. Returns RMSE, MAE, and correlation for each source.

# Arguments
- `sources::Vector{RasterGrid{T}}` — Input raster grids
- `val_coords::Tuple` — (x_coords, y_coords) of validation points
- `val_values::Vector` — Observed values at validation points

# Returns
- `Dict` with keys:
  - `"rmse"` => Dict("source_1" => rmse1, "source_2" => rmse2, ...)
  - `"mae"` => Dict("source_1" => mae1, "source_2" => mae2, ...)
  - `"agreement"` => Correlation matrix between source predictions at val points
  - `"source_count"` => Number of sources compared

# Example
```julia
val_x, val_y = ([0.1, 0.5], [0.2, 0.6])
val_obs = [100.5, 120.3]
results = raster_cross_validate([grid1, grid2], (val_x, val_y), val_obs)
println(results["rmse"])
```
"""
function raster_cross_validate(sources::Vector{RasterGrid{T}}, val_coords::Tuple,
                               val_values::Vector)::Dict where T<:Real
    isempty(sources) && throw(ArgumentError("sources cannot be empty"))
    isempty(val_values) && throw(ArgumentError("val_values cannot be empty"))

    val_x, val_y = val_coords
    if length(val_x) != length(val_y) || length(val_x) != length(val_values)
        throw(DimensionMismatch("val_x, val_y, and val_values must have same length"))
    end

    n_points = length(val_x)
    n_sources = length(sources)

    rmse_dict = Dict{String,Float64}()
    mae_dict = Dict{String,Float64}()
    predictions_matrix = zeros(n_sources, n_points)  # For correlation

    # Extract predictions from each source at validation points
    for (src_idx, source) in enumerate(sources)
        residuals = Float64[]
        abs_residuals = Float64[]

        for pt_idx in 1:n_points
            x_val, y_val = val_x[pt_idx], val_y[pt_idx]
            obs = val_values[pt_idx]

            # Find nearest grid cell
            idx_x = argmin(abs.(source.x_coords .- x_val))
            idx_y = argmin(abs.(source.y_coords .- y_val))
            pred = source.data[idx_y, idx_x]

            if !isnan(pred) && !isnan(obs)
                predictions_matrix[src_idx, pt_idx] = pred
                push!(residuals, obs - pred)
                push!(abs_residuals, abs(obs - pred))
            end
        end

        if !isempty(residuals)
            rmse = sqrt(mean(residuals .^ 2))
            mae = mean(abs_residuals)
            rmse_dict["source_$src_idx"] = rmse
            mae_dict["source_$src_idx"] = mae
        else
            rmse_dict["source_$src_idx"] = NaN
            mae_dict["source_$src_idx"] = NaN
        end
    end

    # Compute correlation matrix between source predictions
    agreement_corr = cor(predictions_matrix', dims=1)

    return Dict(
        "rmse" => rmse_dict,
        "mae" => mae_dict,
        "agreement" => agreement_corr,
        "source_count" => n_sources,
        "validation_points" => n_points
    )
end

"""
    inter_source_agreement(sources::Vector{RasterGrid{T}})::RasterGrid{T} where T<:Real

Compute spatial agreement/disagreement between sources.

For each grid cell, computes standard deviation across sources.
Low std = high agreement, High std = high disagreement.

# Arguments
- `sources::Vector{RasterGrid{T}}` — Input raster grids (should be pre-aligned)

# Returns
- `RasterGrid{T}` where data = standard deviation of sources per cell

# Example
```julia
agreement = inter_source_agreement([grid1, grid2, grid3])
# agreement.data[i, j] = std([grid1[i,j], grid2[i,j], grid3[i,j]])
```
"""
function inter_source_agreement(sources::Vector{RasterGrid{T}})::RasterGrid{T} where T<:Real
    isempty(sources) && throw(ArgumentError("sources cannot be empty"))
    length(sources) == 1 && throw(ArgumentError("Need at least 2 sources for agreement"))

    # Align sources if not already aligned
    aligned = align_raster_grids(sources)
    first = aligned[1]
    n_y, n_x = size(first.data)

    std_grid = Matrix{T}(undef, n_y, n_x)

    for i in 1:n_y
        for j in 1:n_x
            # Collect non-NaN values across sources at this cell
            cell_values = T[]
            for source in aligned
                if !isnan(source.data[i, j])
                    push!(cell_values, source.data[i, j])
                end
            end

            if length(cell_values) > 1
                std_grid[i, j] = std(Float64.(cell_values))
            else
                std_grid[i, j] = T(NaN)
            end
        end
    end

    metadata = Dict{String, Any}(
        "metric" => "inter-source standard deviation",
        "interpretation" => "low_std=high_agreement, high_std=disagreement",
        "n_sources" => length(sources)
    )

    return RasterGrid(std_grid, first.x_coords, first.y_coords,
                     first.crs, first.bounds, first.resolution_m, metadata)
end

"""
    fusion_quality_report(fused::RasterGrid{T}, sources::Dict{String,RasterGrid{T}})::Dict where T<:Real

Assess quality of fusion by measuring inter-source agreement.

Computes coefficient of variation (CV) across sources per cell.
High CV → lower confidence; Low CV → higher confidence.

Confidence metric: 1 / (1 + CV) ∈ [0, 1]

# Arguments
- `fused::RasterGrid{T}` — Fused raster from fuse_population_sources
- `sources::Dict{String,RasterGrid{T}}` — Original sources (pre-fusion)

# Returns
- `Dict` with keys:
  - `"cv"` => Coefficient of variation matrix
  - `"confidence"` => Confidence matrix (1/(1+cv)) ∈ [0, 1]
  - `"mean_confidence"` => Global mean confidence
  - `"high_confidence_fraction"` => Fraction of cells with conf > 0.8
  - `"low_confidence_cells"` => Indices of cells with conf < 0.5

# Example
```julia
sources = Dict("WorldPop" => wp, "GHSL" => ghsl)
fused = fuse_population_sources(sources)
quality = fusion_quality_report(fused, sources)

println("Mean confidence: $(quality["mean_confidence"])")
println("High confidence cells: $(quality["high_confidence_fraction"])")
```
"""
function fusion_quality_report(fused::RasterGrid{T}, sources::Dict{String,RasterGrid{T}})::Dict where T<:Real
    source_list = collect(values(sources))
    aligned = align_raster_grids(source_list)

    n_y, n_x = size(fused.data)
    cv_grid = zeros(n_y, n_x)
    confidence_grid = zeros(n_y, n_x)

    for i in 1:n_y
        for j in 1:n_x
            # Collect non-NaN values across sources
            cell_values = Float64[]
            for source in aligned
                if !isnan(source.data[i, j])
                    push!(cell_values, source.data[i, j])
                end
            end

            if length(cell_values) > 1
                μ = mean(cell_values)
                σ = std(cell_values)
                cv = μ > 1e-10 ? σ / μ : Inf
                cv_grid[i, j] = cv
                confidence_grid[i, j] = 1.0 / (1.0 + cv)
            else
                cv_grid[i, j] = NaN
                confidence_grid[i, j] = NaN
            end
        end
    end

    # Summary statistics
    valid_confidence = filter(!isnan, vec(confidence_grid))
    mean_conf = isempty(valid_confidence) ? NaN : mean(valid_confidence)
    high_conf_frac = isempty(valid_confidence) ? NaN : sum(valid_confidence .> 0.8) / length(valid_confidence)

    low_conf_mask = vec(confidence_grid) .< 0.5
    low_conf_cells = findall(low_conf_mask)

    return Dict(
        "cv" => cv_grid,
        "confidence" => confidence_grid,
        "mean_confidence" => mean_conf,
        "high_confidence_fraction" => high_conf_frac,
        "low_confidence_cells" => low_conf_cells,
        "n_sources" => length(sources)
    )
end
