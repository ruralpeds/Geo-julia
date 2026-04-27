"""
    fusion.jl

Bayesian population fusion from multiple raster sources (WorldPop, GHSL, etc.).

Functions:
- fuse_population_sources: Weighted average fusion with uncertainty propagation
- align_raster_grids: Regrid sources to common resolution
- estimate_source_weights: Correlation-based weighting from data

Reference: Bayesian hierarchical modeling for combining multiple population surveys.
"""

using LinearAlgebra, Statistics, Dates

"""
    align_raster_grids(sources::Vector{RasterGrid{T}})::Vector{RasterGrid{T}} where T<:Real

Align multiple raster grids to a common coordinate system and resolution.

Regrids all sources to the finest resolution, ensuring compatible x_coords and y_coords.

# Arguments
- `sources::Vector{RasterGrid{T}}` — Input raster grids

# Returns
- `Vector{RasterGrid{T}}` — Aligned grids with identical coordinate arrays

# Example
```julia
aligned = align_raster_grids([worldpop_grid, ghsl_grid])
```
"""
function align_raster_grids(sources::Vector{RasterGrid{T}})::Vector{RasterGrid{T}} where T<:Real
    isempty(sources) && throw(ArgumentError("sources cannot be empty"))
    length(sources) == 1 && return copy.(sources)

    # Find finest (smallest) resolution
    min_resolution = minimum(s.resolution_m for s in sources)

    # Determine common bounds
    min_x = minimum(minimum(s.x_coords) for s in sources)
    max_x = maximum(maximum(s.x_coords) for s in sources)
    min_y = minimum(minimum(s.y_coords) for s in sources)
    max_y = maximum(maximum(s.y_coords) for s in sources)

    # Create common coordinate arrays
    n_x = Int(ceil((max_x - min_x) / min_resolution)) + 1
    n_y = Int(ceil((max_y - min_y) / min_resolution)) + 1
    common_x = range(min_x, max_x, length=n_x) |> collect
    common_y = range(min_y, max_y, length=n_y) |> collect

    # Regrid each source to common grid (simple nearest-neighbor for now)
    aligned = RasterGrid{T}[]
    for source in sources
        data_aligned = Matrix{T}(undef, length(common_y), length(common_x))

        for (i_new, y) in enumerate(common_y)
            for (j_new, x) in enumerate(common_x)
                # Find nearest grid cell in original
                idx_x = argmin(abs.(source.x_coords .- x))
                idx_y = argmin(abs.(source.y_coords .- y))
                data_aligned[i_new, j_new] = source.data[idx_y, idx_x]
            end
        end

        metadata_new = copy(source.metadata)
        metadata_new["aligned_from_resolution"] = source.resolution_m

        # Compute new bounds
        x_step = (common_x[end] - common_x[1]) / (length(common_x) - 1)
        y_step = (common_y[end] - common_y[1]) / (length(common_y) - 1)
        new_bounds = (
            west = common_x[1] - x_step/2,
            east = common_x[end] + x_step/2,
            south = common_y[1] - y_step/2,
            north = common_y[end] + y_step/2
        )

        push!(aligned, RasterGrid(data_aligned, common_x, common_y, source.crs, new_bounds, min_resolution, metadata_new))
    end

    return aligned
end

"""
    estimate_source_weights(sources::Vector{RasterGrid{T}})::Dict{String,Float64} where T<:Real

Estimate weights for each source based on spatial correlation and stability.

Higher weights for sources with:
- Low coefficient of variation (stable, non-noisy estimates)
- High pairwise correlation (agreeing with other sources)

Returns weights normalized to sum to 1.0.

# Arguments
- `sources::Vector{RasterGrid{T}}` — Input raster grids (should be pre-aligned)

# Returns
- `Dict{String,Float64}` — Source weights (keys: "source_1", "source_2", etc.)

# Example
```julia
weights = estimate_source_weights([grid1, grid2, grid3])
# Returns: Dict("source_1" => 0.35, "source_2" => 0.40, "source_3" => 0.25)
```
"""
function estimate_source_weights(sources::Vector{RasterGrid{T}})::Dict{String,Float64} where T<:Real
    isempty(sources) && throw(ArgumentError("sources cannot be empty"))
    length(sources) == 1 && return Dict("source_1" => 1.0)

    # Compute coefficient of variation for each source (stability metric)
    n_sources = length(sources)
    cv_values = Float64[]

    for source in sources
        valid_cells = filter(!isnan, vec(source.data))
        if length(valid_cells) > 0
            μ = mean(valid_cells)
            σ = std(valid_cells)
            # CV = σ/μ; handle zero/near-zero mean
            cv = μ > 1e-10 ? σ / μ : σ + 1.0
            push!(cv_values, cv)
        else
            push!(cv_values, Inf)
        end
    end

    # Inverse CV weighting: stable sources (low CV) get higher weight
    inv_cv = 1.0 ./ (cv_values .+ eps(Float64))

    # Compute pairwise correlations
    grid_vectors = [vec(source.data) for source in sources]
    correlation_weights = ones(n_sources)

    for i in 1:n_sources
        corr_sum = 0.0
        n_pairs = 0
        for j in 1:n_sources
            if i != j
                # Filter to valid (non-NaN) points in both
                valid = (!isnan.(grid_vectors[i])) .& (!isnan.(grid_vectors[j]))
                if sum(valid) > 1
                    corr = cor(grid_vectors[i][valid], grid_vectors[j][valid])
                    if !isnan(corr)
                        corr_sum += max(0.0, corr)  # Use only positive correlation
                        n_pairs += 1
                    end
                end
            end
        end
        if n_pairs > 0
            correlation_weights[i] = 1.0 + (corr_sum / n_pairs)
        end
    end

    # Combine stability and correlation metrics
    combined_weights = inv_cv .* correlation_weights
    combined_weights ./= sum(combined_weights)  # Normalize

    # Return as dictionary with source identifiers
    weights_dict = Dict{String,Float64}()
    for (idx, w) in enumerate(combined_weights)
        weights_dict["source_$idx"] = w
    end

    return weights_dict
end

"""
    fuse_population_sources(sources::Dict{String,RasterGrid{T}}; weights::Dict{String,Float64}=Dict())::RasterGrid{T} where T<:Real

Fuse multiple population sources using Bayesian weighted averaging.

Combines estimates from multiple sources (WorldPop, GHSL, etc.) into a single grid,
with uncertainty quantification combining source variances and inter-source disagreement.

# Arguments
- `sources::Dict{String,RasterGrid{T}}` — Dictionary of named sources (e.g., "WorldPop" => grid)
- `weights::Dict{String,Float64}` — Optional: pre-computed weights for each source.
  If not provided, estimated from spatial correlation.

# Returns
- `RasterGrid{T}` with fields:
  - `data` — Fused population estimates (weighted average)
  - `metadata["source_weights"]` — Weights used for fusion
  - `metadata["uncertainty"]` — Combined uncertainty surface (√(Σ w_s² * var_s) + var(sources))

# Method
```
fused = Σ w_s * source_s / Σ w_s  (weighted average)

var(fused) = √(Σ w_s² * var_s(local)) / (Σ w_s)² + var(sources across cells)
           = measurement uncertainty + inter-source disagreement
```

# Example
```julia
sources = Dict("WorldPop" => wp_grid, "GHSL" => ghsl_grid)
fused = fuse_population_sources(sources)

# With custom weights
weights = Dict("WorldPop" => 0.6, "GHSL" => 0.4)
fused = fuse_population_sources(sources; weights=weights)
```
"""
function fuse_population_sources(sources::Dict{String,RasterGrid{T}};
                                 weights::Dict{String,Float64}=Dict())::RasterGrid{T} where T<:Real
    isempty(sources) && throw(ArgumentError("sources cannot be empty"))

    source_names = collect(keys(sources))
    source_list = [sources[name] for name in source_names]

    # Align all sources to common grid
    aligned_sources = align_raster_grids(source_list)
    first_source = aligned_sources[1]

    # Estimate weights if not provided
    if isempty(weights)
        weights = estimate_source_weights(aligned_sources)
    else
        # Validate provided weights
        if !all(haskey(weights, name) for name in source_names)
            throw(ArgumentError("weights must have entries for all sources"))
        end
        # Normalize weights to sum to 1.0
        w_sum = sum(values(weights))
        weights = Dict(name => w / w_sum for (name, w) in weights)
    end

    # Extract weights in source order
    weight_vec = Float64[weights[name] for name in source_names]

    n_y, n_x = size(first_source.data)
    fused_data = Matrix{T}(undef, n_y, n_x)
    uncertainty_data = zeros(Float64, n_y, n_x)

    # Fuse each cell
    for i in 1:n_y
        for j in 1:n_x
            # Collect non-NaN values from each source
            cell_values = T[]
            for source in aligned_sources
                if !isnan(source.data[i, j])
                    push!(cell_values, source.data[i, j])
                end
            end

            if isempty(cell_values)
                fused_data[i, j] = T(NaN)
                uncertainty_data[i, j] = NaN
                continue
            end

            # Weighted average (only use weights for non-NaN sources)
            valid_mask = [!isnan(source.data[i, j]) for source in aligned_sources]
            valid_weights = weight_vec[valid_mask]
            valid_weights ./= sum(valid_weights)  # Renormalize
            fused_data[i, j] = sum(valid_weights .* Float64.(cell_values))

            # Uncertainty: measurement error + inter-source disagreement
            # Assume ~5-10% measurement uncertainty at source level
            fused_val = Float64(fused_data[i, j])
            measurement_var = sum(valid_weights.^2) * 0.01 * (fused_val^2)  # 1% relative error

            # Inter-source disagreement variance
            if length(cell_values) > 1
                disagreement_var = var(Float64.(cell_values))
            else
                disagreement_var = 0.0
            end

            combined_variance = measurement_var + disagreement_var
            uncertainty_data[i, j] = sqrt(combined_variance)
        end
    end

    # Build metadata with uncertainty surface
    metadata = copy(first_source.metadata)
    metadata["source_weights"] = weights
    metadata["uncertainty"] = uncertainty_data
    metadata["n_sources"] = length(sources)
    metadata["source_names"] = source_names
    metadata["fusion_method"] = "Bayesian weighted average"
    metadata["fused_at"] = string(now())

    return RasterGrid(fused_data, first_source.x_coords, first_source.y_coords,
                     first_source.crs, first_source.bounds, first_source.resolution_m, metadata)
end
