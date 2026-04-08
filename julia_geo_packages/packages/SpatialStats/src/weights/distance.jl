# weights/distance.jl — Distance-band and inverse-distance weights

"""
    distance_weights(df, threshold_km; transform=:W) -> SpatialWeights

Build distance-band spatial weights: two observations are neighbours if
their great-circle centroid distance is ≤ `threshold_km`.

# Arguments
- `df`           : DataFrame with `:geometry` column
- `threshold_km` : distance cutoff in kilometres
- `transform`    : `:W` (row-standardised) or `:B` (binary)
"""
function distance_weights(df::DataFrame, threshold_km::Real;
                           transform::Symbol = :W)::SpatialWeights
    centroids = _centroids(df)
    n = length(centroids)

    Is = Int[]; Js = Int[]; Vs = Float64[]
    for i in 1:n
        lat_i, lon_i = centroids[i]
        for j in (i+1):n
            lat_j, lon_j = centroids[j]
            d = haversine_km(lat_i, lon_i, lat_j, lon_j)
            if d <= threshold_km
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

    SpatialWeights(W, n, style, DistanceTransform(), island_count, mean_nb, min_nb, max_nb)
end

"""
    inverse_distance_weights(df; power=1.0, threshold_km=Inf, transform=:W) -> SpatialWeights

Build inverse-distance weights: `w_ij = 1 / d_ij^power` for d > 0.
An optional `threshold_km` limits the neighbourhood.

# Arguments
- `df`           : DataFrame with `:geometry` column
- `power`        : distance decay exponent (default 1.0)
- `threshold_km` : optional distance cutoff; Inf = all pairs
- `transform`    : `:W` (row-standardised) or `:B` (raw inverse weights)
"""
function inverse_distance_weights(df::DataFrame;
                                   power::Real = 1.0,
                                   threshold_km::Real = Inf,
                                   transform::Symbol = :W)::SpatialWeights
    centroids = _centroids(df)
    n = length(centroids)

    Is = Int[]; Js = Int[]; Vs = Float64[]
    for i in 1:n
        lat_i, lon_i = centroids[i]
        for j in (i+1):n
            lat_j, lon_j = centroids[j]
            d = haversine_km(lat_i, lon_i, lat_j, lon_j)
            (d > threshold_km || d ≈ 0.0) && continue
            w = 1.0 / d^power
            push!(Is, i); push!(Js, j); push!(Vs, w)
            push!(Is, j); push!(Js, i); push!(Vs, w)
        end
    end

    W = sparse(Is, Js, Vs, n, n)
    W_binary = W .!= 0
    island_count, mean_nb, min_nb, max_nb = _build_metadata(W_binary)

    if transform == :W
        _row_standardize!(W)
        style = RowStandardizedStyle()
    else
        style = BinaryStyle()
    end

    SpatialWeights(W, n, style, InvDistTransform(), island_count, mean_nb, min_nb, max_nb)
end

"""
    normalize!(sw::SpatialWeights) -> SpatialWeights

Row-standardise a SpatialWeights in place (idempotent if already :W style).
"""
function normalize!(sw::SpatialWeights)::SpatialWeights
    sw.style isa RowStandardizedStyle && return sw
    _row_standardize!(sw.W)
    # Return a new instance with updated style (struct is immutable)
    SpatialWeights(sw.W, sw.n, RowStandardizedStyle(), sw.transform,
                   sw.island_count, sw.mean_neighbors, sw.min_neighbors, sw.max_neighbors)
end
