# weights/knn.jl — k-nearest neighbour weights

"""
    knn_weights(df, k=5; transform=:W) -> SpatialWeights

Build k-nearest-neighbour spatial weights using centroid distances.

# Arguments
- `df`        : DataFrame with `:geometry` column, or DataFrame with `:lat`/`:lon`
- `k`         : number of nearest neighbours (default 5)
- `transform` : `:W` (row-standardised) or `:B` (binary)
"""
function knn_weights(df::DataFrame, k::Int = 5; transform::Symbol = :W)::SpatialWeights
    centroids = _centroids(df)
    n = length(centroids)
    k = min(k, n - 1)

    # KDTree on (lon, lat) in Cartesian-ish coords for speed
    # Use projected lat/lon — fine for continental US analysis
    coords = Float64.(hcat(last.(centroids), first.(centroids)))  # [lon; lat]
    tree = KDTree(coords)

    Is = Int[]; Js = Int[]; Vs = Float64[]
    for i in 1:n
        idxs, _ = knn(tree, coords[:, i], k + 1, true)
        for j in idxs
            j == i && continue
            push!(Is, i); push!(Js, j); push!(Vs, 1.0)
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

    SpatialWeights(W, n, style, KNNTransform(), island_count, mean_nb, min_nb, max_nb)
end
