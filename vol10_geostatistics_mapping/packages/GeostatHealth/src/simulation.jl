# simulation.jl — Sequential Gaussian Simulation (SGS)

using Statistics, LinearAlgebra, Random

"""
    sgs_simulate(coords, vm, pred_coords; n_real, rng) -> Matrix{Float64}

Sequential Gaussian Simulation (SGS) at `pred_coords`.

Returns a matrix of size (n_pred × n_real) with simulated realisations.

Algorithm:
1. Visit each prediction location in random order
2. Build local covariance system from nearest conditioning data + previously
   simulated nodes (up to n_neighbours)
3. Simple kriging prediction + variance → draw from N(ẑ, σ²_SK)
4. Add realisation to conditioning set
"""
function sgs_simulate(z::AbstractVector, coords::AbstractMatrix,
                       pred_coords::AbstractMatrix, vm::VariogramModel;
                       n_real::Int=5,
                       n_neighbours::Int=min(16, size(coords,1)),
                       rng::AbstractRNG=Random.GLOBAL_RNG)
    n_orig = length(z)
    n_pred = size(pred_coords, 1)
    all_coords = vcat(coords, pred_coords)
    N_total    = n_orig + n_pred

    results = zeros(n_pred, n_real)

    # Pre-compute all pairwise distances
    D = zeros(N_total, N_total)
    for i in 1:N_total, j in i+1:N_total
        d = sqrt(sum((all_coords[i,:] .- all_coords[j,:]).^2))
        D[i,j] = d; D[j,i] = d
    end

    for r in 1:n_real
        z_all = vcat(Float64.(z), fill(NaN, n_pred))  # NaN = not yet simulated
        order = n_orig .+ randperm(rng, n_pred)       # random visit order

        for idx in order
            # Find nearest conditioning points (simulated + original)
            cond_idx = findall(!isnan, z_all)
            # Sort by distance to current location
            dists_to = D[idx, cond_idx]
            nn       = min(n_neighbours, length(cond_idx))
            near_pos = partialsortperm(dists_to, 1:nn)
            near_idx = cond_idx[near_pos]

            c_near   = all_coords[near_idx, :]
            z_near   = z_all[near_idx]

            # SK with local mean = global mean of original data
            μ = mean(z)
            C_local   = [covariance_value(vm, D[near_idx[i], near_idx[j]])
                         for i in 1:nn, j in 1:nn]
            c_cross   = [covariance_value(vm, D[idx, near_idx[k]]) for k in 1:nn]
            C_reg     = C_local + 1e-10 * I
            λ         = C_reg \ c_cross
            ẑ         = μ + dot(λ, z_near .- μ)
            c0        = covariance_value(vm, 0.0)
            σ²        = max(c0 - dot(λ, c_cross), 0.0)
            z_all[idx] = ẑ + sqrt(σ²) * randn(rng)
        end

        results[:, r] = z_all[n_orig+1:end]
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
