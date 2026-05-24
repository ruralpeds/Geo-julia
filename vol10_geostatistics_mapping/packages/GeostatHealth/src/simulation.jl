# simulation.jl — Sequential Gaussian Simulation (SGS)
# Backed by GeoStats.jl simulation solvers

"""
    sgs_simulate(coords, vm, pred_coords; n_real, rng) -> Matrix{Float64}

Sequential Gaussian Simulation (SGS) at `pred_coords`.

Returns a matrix of size (n_pred × n_real) with simulated realisations.

Uses GeoStats.jl LUGS (LU Gaussian Simulation) solver internally.
"""
function sgs_simulate(z::AbstractVector, coords::AbstractMatrix,
                       pred_coords::AbstractMatrix, vm::VariogramModel;
                       n_real::Int=5,
                       n_neighbours::Int=min(16, size(coords,1)),
                       rng::AbstractRNG=Random.GLOBAL_RNG)
    n_orig = length(z)
    n_pred = size(pred_coords, 1)

    gv = _to_geostats_variogram(vm)

    # Build georeferenced conditioning data
    points_obs = [Meshes.Point(coords[i,1], coords[i,2]) for i in 1:n_orig]
    domain_obs = Meshes.PointSet(points_obs)
    geotable   = GeoTables.georef((; Z = Float64.(z)), domain_obs)

    # Build prediction domain
    points_pred = [Meshes.Point(pred_coords[j,1], pred_coords[j,2]) for j in 1:n_pred]
    domain_pred = Meshes.PointSet(points_pred)

    results = zeros(n_pred, n_real)

    # Use GeoStats LUGS (LU-based Gaussian Simulation)
    process = GeoStats.GaussianProcess(gv)
    method  = GeoStats.LUGS(factorization=GeoStats.lu)

    for r in 1:n_real
        sim = GeoStats.rand(process, domain_pred, geotable, method, rng=rng)
        z_sim = sim.Z
        results[:, r] = Float64.(z_sim)
    end

    results
end

"""
    sgs_uncertainty(simulations) -> NamedTuple

Summarise SGS realisations into mean, variance, and 90% PI.
"""
function sgs_uncertainty(simulations::AbstractMatrix)
    n_pred, n_real = size(simulations)
    μ     = vec(mean(simulations, dims=2))
    σ²    = vec(var(simulations,  dims=2))
    lo_90 = [quantile(simulations[i,:], 0.05) for i in 1:n_pred]
    hi_90 = [quantile(simulations[i,:], 0.95) for i in 1:n_pred]
    (mean=μ, variance=σ², lower_90=lo_90, upper_90=hi_90, n_real=n_real)
end
