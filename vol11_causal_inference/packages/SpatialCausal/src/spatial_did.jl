# spatial_did.jl — Spatial difference-in-differences with spillover effects

struct SpatialDIDResult
    β_direct::Float64      # ATT: direct treatment effect
    β_spillover::Float64   # spillover effect in buffer zone
    β_post::Float64        # time trend
    se_direct::Float64
    se_spillover::Float64
    se_post::Float64
    ci_direct::Tuple{Float64,Float64}
    ci_spillover::Tuple{Float64,Float64}
    n::Int
    n_treated::Int
    n_spillover::Int
    n_control::Int
    radius::Float64
    buffer::Float64
end

"""
    spatial_did(y, coords, post, treatment_sites; radius, buffer, unit_ids, n_boot) -> SpatialDIDResult

Spatial DiD with spillover zones (Cerqua & Pellegrini 2014 style):
    yᵢₜ = αᵢ + γₜ + τ·Dᵢ·Postₜ + φ·Sᵢ·Postₜ + εᵢₜ

where:
- Dᵢ = 1 if unit i is within `radius` km of a treatment site
- Sᵢ = 1 if unit i is within buffer zone (radius, radius+buffer)
- Postₜ = 1 after treatment

`coords` is n×2 matrix (one row per unit), `treatment_sites` is k×2 matrix.
`y`, `coords` and `post` are observation-level (n_obs rows if panel data).
`unit_ids` maps each row to a spatial unit for the coordinate lookup.
"""
function spatial_did(y::AbstractVector,
                     coords::AbstractMatrix,        # n_units × 2
                     post::AbstractVector,          # n_obs binary
                     treatment_sites::AbstractMatrix;  # k × 2
                     radius::Float64=1.0,
                     buffer::Float64=0.5,
                     unit_ids::AbstractVector=collect(1:length(y)),
                     n_boot::Int=200,
                     rng=Random.default_rng())

    n_units = size(coords, 1)
    n_obs   = length(y)

    # Assign treatment / spillover status to each unit
    D_unit = falses(n_units)  # treated
    S_unit = falses(n_units)  # spillover buffer

    for i in 1:n_units
        min_dist = minimum(_haversine(coords[i,:], treatment_sites[k,:])
                           for k in 1:size(treatment_sites,1))
        if min_dist <= radius
            D_unit[i] = true
        elseif min_dist <= radius + buffer
            S_unit[i] = true
        end
    end

    # Map to observation level
    D_obs = D_unit[unit_ids]
    S_obs = S_unit[unit_ids]
    P_obs = Float64.(post)

    # TWFE: within-demean by unit and time
    times   = unique(post)
    u_ids   = unit_ids

    # Design: [D_obs·P_obs, S_obs·P_obs, P_obs]
    Xmat = hcat(Float64.(D_obs) .* P_obs,
                Float64.(S_obs) .* P_obs,
                P_obs)

    β_fn = (yv, Xm, uid) -> begin
        XY = hcat(Xm, yv)
        # Demean by unit
        for u in unique(uid)
            idx = uid .== u; XY[idx,:] .-= mean(XY[idx,:], dims=1)
        end
        X_w = XY[:,1:end-1]; y_w = XY[:,end]
        (X_w'X_w + 1e-10*I) \ (X_w'y_w)
    end

    β  = β_fn(y, Xmat, u_ids)
    se = _boot_se_units(y, Xmat, u_ids, β_fn, n_boot, rng)

    SpatialDIDResult(
        β[1], β[2], β[3],
        se[1], se[2], se[3],
        (β[1]-1.96se[1], β[1]+1.96se[1]),
        (β[2]-1.96se[2], β[2]+1.96se[2]),
        n_obs, sum(D_unit), sum(S_unit), sum(.!D_unit .& .!S_unit),
        radius, buffer
    )
end

function _boot_se_units(y, X, uid, fn, n_boot, rng)
    units = unique(uid)
    ests  = Matrix{Float64}(undef, size(X,2), n_boot)
    for b in 1:n_boot
        bu  = rand(rng, units, length(units))
        idx = vcat([findall(==(u), uid) for u in bu]...)
        ests[:,b] = fn(y[idx], X[idx,:], uid[idx])
    end
    vec(std(ests, dims=2))
end

# Simple Euclidean distance (coords in degrees, approximate)
function _haversine(a::AbstractVector, b::AbstractVector)
    sqrt(sum((a .- b).^2))
end

"""
    spillover_decomposition(result) -> NamedTuple

Report direct effect, spillover, and their ratio.
"""
function spillover_decomposition(r::SpatialDIDResult)
    (direct=r.β_direct, direct_se=r.se_direct,
     spillover=r.β_spillover, spillover_se=r.se_spillover,
     ratio=r.β_spillover / max(abs(r.β_direct), 1e-10),
     n_treated=r.n_treated, n_spillover=r.n_spillover, n_control=r.n_control)
end
