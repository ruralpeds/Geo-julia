# weights/queen.jl — Queen and Rook contiguity weights

"""
    queen_weights(df; transform=:W) -> SpatialWeights

Build queen contiguity weights from a DataFrame with `:geometry` column.
Two polygons are neighbours if they share any boundary point (vertex or edge).

Uses bounding-box pre-filtering to avoid O(n²) geometry intersection tests.

# Arguments
- `df`          : DataFrame with a `:geometry` column (GeoInterface-compatible)
- `transform`   : `:W` (row-standardised, default) or `:B` (binary)
"""
function queen_weights(df::DataFrame; transform::Symbol = :W)::SpatialWeights
    n = nrow(df)
    geoms = df.geometry

    # Bounding boxes for pre-filtering
    extents = [GeoInterface.extent(g) for g in geoms]

    Is = Int[]; Js = Int[]; Vs = Float64[]

    for i in 1:n
        ext_i = extents[i]
        for j in (i+1):n
            ext_j = extents[j]
            # Bounding box overlap test (fast pre-filter)
            if ext_i.X[2] < ext_j.X[1] || ext_j.X[2] < ext_i.X[1] ||
               ext_i.Y[2] < ext_j.Y[1] || ext_j.Y[2] < ext_i.Y[1]
                continue
            end
            # Full intersection test
            if GeoInterface.intersects(geoms[i], geoms[j])
                push!(Is, i); push!(Js, j); push!(Vs, 1.0)
                push!(Is, j); push!(Js, i); push!(Vs, 1.0)
            end
        end
    end

    W = sparse(Is, Js, Vs, n, n)
    island_count, mean_nb, min_nb, max_nb = _build_metadata(W)

    if transform == :W
        _row_standardize!(W)
        style = RowStandardizedStyle()
    else
        style = BinaryStyle()
    end

    SpatialWeights(W, n, style, QueenTransform(), island_count, mean_nb, min_nb, max_nb)
end

"""
    rook_weights(df; transform=:W) -> SpatialWeights

Build rook contiguity weights (shared edges only, not vertices).
Approximated by queen weights with a note — true edge-only detection
requires polygon coordinate comparison.

# Note
Julia's GeoInterface does not expose edge-level topology. This function
uses queen contiguity and emits a warning. For true rook weights, use
an R bridge: `r_rook_weights(df)`.
"""
function rook_weights(df::DataFrame; transform::Symbol = :W)::SpatialWeights
    @warn "rook_weights: Julia GeoInterface lacks edge-only topology. " *
          "Returning queen contiguity. Use r_rook_weights() for true rook."
    queen_weights(df; transform)
end
