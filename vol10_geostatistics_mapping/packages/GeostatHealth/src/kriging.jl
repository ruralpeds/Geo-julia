# kriging.jl — Simple, Ordinary, and Universal Kriging
# Backed by GeoStats.jl / GeoStatsModels.jl

# ── Simple Kriging ────────────────────────────────────────────────────────────

"""
    SimpleKrigingResult

Fitted simple kriging model (known mean μ).
"""
struct SimpleKrigingResult
    vm      ::VariogramModel
    coords  ::Matrix{Float64}
    z       ::Vector{Float64}
    μ       ::Float64
    C_inv   ::Matrix{Float64}   # inverse covariance (kept for API compat)
end

"""
    simple_kriging(z, coords, vm; μ) -> SimpleKrigingResult

Fit simple kriging (SK) with known global mean μ.
"""
function simple_kriging(z::AbstractVector, coords::AbstractMatrix,
                         vm::VariogramModel; μ::Float64=mean(z))
    n = length(z)
    C = _cov_matrix(vm, coords)
    C_reg = C + 1e-10 * I
    C_inv = inv(C_reg)
    SimpleKrigingResult(vm, Matrix{Float64}(coords), Float64.(z), μ, C_inv)
end

"""
    sk_predict(sk, new_coords) -> (z_hat, σ²_kriging)

Predict at new locations using simple kriging via GeoStats.jl.
"""
function sk_predict(sk::SimpleKrigingResult, new_coords::AbstractMatrix)
    gv = _to_geostats_variogram(sk.vm)

    # Build georeferenced data
    n = length(sk.z)
    points_obs = [Meshes.Point(sk.coords[i,1], sk.coords[i,2]) for i in 1:n]
    domain_obs = Meshes.PointSet(points_obs)
    geotable   = GeoTables.georef((; Z = sk.z), domain_obs)

    # Build prediction domain
    n_new = size(new_coords, 1)
    points_new = [Meshes.Point(new_coords[j,1], new_coords[j,2]) for j in 1:n_new]
    domain_new = Meshes.PointSet(points_new)

    # Use GeoStatsModels Kriging
    model = GeoStatsModels.Kriging(gv, sk.μ)
    fitted = GeoStatsModels.fit(model, geotable)

    z_hat = zeros(n_new)
    σ²    = zeros(n_new)
    for j in 1:n_new
        μ_pred, σ²_pred = GeoStatsModels.predictprob(fitted, :Z, points_new[j])
        z_hat[j] = μ_pred
        σ²[j]    = max(σ²_pred, 0.0)
    end
    z_hat, σ²
end

# ── Ordinary Kriging ──────────────────────────────────────────────────────────

"""
    OrdinaryKrigingResult

Fitted ordinary kriging model (unknown mean, unbiasedness constraint).
"""
struct OrdinaryKrigingResult
    vm       ::VariogramModel
    coords   ::Matrix{Float64}
    z        ::Vector{Float64}
    K_inv    ::Matrix{Float64}   # inverse of augmented system (kept for API compat)
end

"""
    ordinary_kriging(z, coords, vm) -> OrdinaryKrigingResult

Fit ordinary kriging (OK).
"""
function ordinary_kriging(z::AbstractVector, coords::AbstractMatrix,
                            vm::VariogramModel)
    n = length(z)
    C = _cov_matrix(vm, coords)
    K     = [C ones(n); ones(1,n) 0.0]
    K_reg = K + 1e-10 * I
    K_inv = inv(K_reg)
    OrdinaryKrigingResult(vm, Matrix{Float64}(coords), Float64.(z), K_inv)
end

"""
    ok_predict(ok, new_coords) -> (z_hat, σ²_kriging)

Predict at new locations using ordinary kriging via GeoStats.jl.
"""
function ok_predict(ok::OrdinaryKrigingResult, new_coords::AbstractMatrix)
    gv = _to_geostats_variogram(ok.vm)

    # Build georeferenced data
    n = length(ok.z)
    points_obs = [Meshes.Point(ok.coords[i,1], ok.coords[i,2]) for i in 1:n]
    domain_obs = Meshes.PointSet(points_obs)
    geotable   = GeoTables.georef((; Z = ok.z), domain_obs)

    # Build prediction domain
    n_new = size(new_coords, 1)
    points_new = [Meshes.Point(new_coords[j,1], new_coords[j,2]) for j in 1:n_new]
    domain_new = Meshes.PointSet(points_new)

    # Use GeoStatsModels OrdinaryKriging
    model = GeoStatsModels.Kriging(gv, nothing)
    fitted = GeoStatsModels.fit(model, geotable)

    z_hat = zeros(n_new)
    σ²    = zeros(n_new)
    for j in 1:n_new
        μ_pred, σ²_pred = GeoStatsModels.predictprob(fitted, :Z, points_new[j])
        z_hat[j] = μ_pred
        σ²[j]    = max(σ²_pred, 0.0)
    end
    z_hat, σ²
end

# ── Universal Kriging ─────────────────────────────────────────────────────────

"""
    UniversalKrigingResult

Universal kriging with polynomial trend m(x) = F·β.
"""
struct UniversalKrigingResult
    vm     ::VariogramModel
    coords ::Matrix{Float64}
    z      ::Vector{Float64}
    F      ::Matrix{Float64}   # trend matrix (n × p)
    K_inv  ::Matrix{Float64}   # inverse of augmented UK system (kept for API compat)
    degree ::Int               # polynomial degree (1 or 2)
end

"""
    universal_kriging(z, coords, vm; degree) -> UniversalKrigingResult

Universal kriging with polynomial trend of given degree (1=linear, 2=quadratic).
"""
function universal_kriging(z::AbstractVector, coords::AbstractMatrix,
                             vm::VariogramModel; degree::Int=1)
    n = length(z)
    F = _trend_matrix(coords, degree)
    p = size(F, 2)
    C = _cov_matrix(vm, coords)
    K = [C F; F' zeros(p,p)]
    K_inv = inv(K + 1e-10 * I)
    UniversalKrigingResult(vm, Matrix{Float64}(coords), Float64.(z), F, K_inv, degree)
end

function _trend_matrix(coords::AbstractMatrix, degree::Int)
    n = size(coords, 1)
    x = coords[:,1]; y = coords[:,2]
    if degree == 1
        return hcat(ones(n), x, y)
    else
        return hcat(ones(n), x, y, x.^2, x.*y, y.^2)
    end
end

"""
    uk_predict(uk, new_coords) -> (z_hat, σ²_kriging)

Predict at new locations using universal kriging via GeoStats.jl.
"""
function uk_predict(uk::UniversalKrigingResult, new_coords::AbstractMatrix)
    gv = _to_geostats_variogram(uk.vm)

    # Build georeferenced data
    n = length(uk.z)
    points_obs = [Meshes.Point(uk.coords[i,1], uk.coords[i,2]) for i in 1:n]
    domain_obs = Meshes.PointSet(points_obs)
    geotable   = GeoTables.georef((; Z = uk.z), domain_obs)

    # Build prediction domain
    n_new = size(new_coords, 1)
    points_new = [Meshes.Point(new_coords[j,1], new_coords[j,2]) for j in 1:n_new]
    domain_new = Meshes.PointSet(points_new)

    # Use GeoStatsModels with degree specification for universal kriging
    model = GeoStatsModels.Kriging(gv, uk.degree)
    fitted = GeoStatsModels.fit(model, geotable)

    z_hat = zeros(n_new)
    σ²    = zeros(n_new)
    for j in 1:n_new
        μ_pred, σ²_pred = GeoStatsModels.predictprob(fitted, :Z, points_new[j])
        z_hat[j] = μ_pred
        σ²[j]    = max(σ²_pred, 0.0)
    end
    z_hat, σ²
end

# ── Leave-one-out cross-validation ───────────────────────────────────────────

"""
    kriging_loo_cv(z, coords, vm; method) -> NamedTuple

Leave-one-out cross-validation for kriging accuracy.

Returns (rmse, mae, mean_bias, picp_95, mean_width_95).
"""
function kriging_loo_cv(z::AbstractVector, coords::AbstractMatrix,
                         vm::VariogramModel;
                         method::Symbol=:ordinary)
    n = length(z)
    errors = zeros(n)
    in_pi  = falses(n)
    widths = zeros(n)

    for i in 1:n
        train_idx = setdiff(1:n, i)
        z_tr  = z[train_idx]
        c_tr  = coords[train_idx, :]

        ẑ, σ² = if method == :ordinary
            m = ordinary_kriging(z_tr, c_tr, vm)
            ok_predict(m, coords[i:i,:])
        elseif method == :simple
            m = simple_kriging(z_tr, c_tr, vm)
            sk_predict(m, coords[i:i,:])
        else
            m = universal_kriging(z_tr, c_tr, vm)
            uk_predict(m, coords[i:i,:])
        end

        errors[i] = ẑ[1] - z[i]
        se = sqrt(max(σ²[1], 0.0))
        in_pi[i]  = abs(errors[i]) <= 1.96 * se
        widths[i] = 2 * 1.96 * se
    end

    (rmse     = sqrt(mean(errors.^2)),
     mae      = mean(abs.(errors)),
     mean_bias= mean(errors),
     picp_95  = mean(in_pi),
     mean_width= mean(widths),
     n        = n)
end

# ── Internal helpers ──────────────────────────────────────────────────────────

function _cov_matrix(vm::VariogramModel, coords::AbstractMatrix)
    n = size(coords, 1)
    C = zeros(n, n)
    for i in 1:n, j in i:n
        h   = sqrt(sum((coords[i,:] .- coords[j,:]).^2))
        c   = covariance_value(vm, h)
        C[i,j] = c; C[j,i] = c
    end
    C
end
