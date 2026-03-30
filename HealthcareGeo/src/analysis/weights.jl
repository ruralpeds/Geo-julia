# src/analysis/weights.jl
# Spatial weights matrix construction methods.

"""
    build_queen_weights(geoms) -> Matrix{Float64}

Build a row-standardised queen-contiguity spatial weights matrix from a vector
of polygon geometries.  Two polygons are neighbours if they share any boundary
point or edge (queen criterion).

Uses `GeoInterface.intersects` for adjacency testing.
"""
function build_queen_weights(geoms::AbstractVector)::Matrix{Float64}
    n = length(geoms)
    W = zeros(Float64, n, n)

    for i in 1:n
        for j in (i + 1):n
            if GeoInterface.intersects(geoms[i], geoms[j])
                W[i, j] = 1.0
                W[j, i] = 1.0
            end
        end
    end

    # Row-standardise
    row_sums = sum(W; dims = 2)
    for i in 1:n
        if row_sums[i] > 0
            W[i, :] ./= row_sums[i]
        end
    end

    return W
end

"""
    build_knn_weights(coords, k=5) -> Matrix{Float64}

Build a row-standardised k-nearest-neighbour spatial weights matrix.

`coords` is an n×2 matrix where each row is `[lat, lon]` in decimal degrees.
Distances are computed with the haversine formula.
"""
function build_knn_weights(coords::Matrix{Float64}, k::Int = 5)::Matrix{Float64}
    n = size(coords, 1)
    W = zeros(Float64, n, n)

    for i in 1:n
        ci = (coords[i, 1], coords[i, 2])
        dists = [haversine(ci, (coords[j, 1], coords[j, 2])) for j in 1:n]
        dists[i] = Inf  # exclude self
        knn_idx = partialsortperm(dists, 1:k)
        for j in knn_idx
            W[i, j] = 1.0
        end
    end

    # Row-standardise
    row_sums = sum(W; dims = 2)
    for i in 1:n
        if row_sums[i] > 0
            W[i, :] ./= row_sums[i]
        end
    end

    return W
end

"""
    build_distance_band_weights(coords; bandwidth_km=50.0) -> Matrix{Float64}

Build a row-standardised binary distance-band spatial weights matrix.
All pairs within `bandwidth_km` receive weight 1 before row-standardisation.

`coords` is an n×2 matrix of `[lat, lon]` in decimal degrees.
"""
function build_distance_band_weights(coords::Matrix{Float64};
                                      bandwidth_km::Float64 = 50.0)::Matrix{Float64}
    n = size(coords, 1)
    W = zeros(Float64, n, n)

    for i in 1:n
        for j in 1:n
            i == j && continue
            d = haversine((coords[i, 1], coords[i, 2]),
                          (coords[j, 1], coords[j, 2]))
            if d <= bandwidth_km
                W[i, j] = 1.0
            end
        end
    end

    # Row-standardise
    row_sums = sum(W; dims = 2)
    for i in 1:n
        if row_sums[i] > 0
            W[i, :] ./= row_sums[i]
        end
    end

    return W
end

"""
    build_inverse_distance_weights(coords; power=1.0) -> Matrix{Float64}

Build a row-standardised inverse-distance spatial weights matrix.
`W[i,j] = 1 / d(i,j)^power` for i ≠ j.

`coords` is an n×2 matrix of `[lat, lon]` in decimal degrees.
"""
function build_inverse_distance_weights(coords::Matrix{Float64};
                                         power::Float64 = 1.0)::Matrix{Float64}
    n = size(coords, 1)
    W = zeros(Float64, n, n)

    for i in 1:n
        for j in 1:n
            i == j && continue
            d = haversine((coords[i, 1], coords[i, 2]),
                          (coords[j, 1], coords[j, 2]))
            W[i, j] = d > 0 ? 1.0 / d^power : 0.0
        end
    end

    # Row-standardise
    row_sums = sum(W; dims = 2)
    for i in 1:n
        if row_sums[i] > 0
            W[i, :] ./= row_sums[i]
        end
    end

    return W
end
