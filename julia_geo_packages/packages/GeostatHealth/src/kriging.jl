# kriging.jl — Simple, Ordinary, and Universal Kriging

using Statistics, LinearAlgebra

# ── Covariance matrix from variogram model ────────────────────────────────────

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

function _cross_cov(vm::VariogramModel, coords::AbstractMatrix,
                    new_coords::AbstractMatrix)
    n_train = size(coords, 1)
    n_new   = size(new_coords, 1)
    C = zeros(n_train, n_new)
    for i in 1:n_train, j in 1:n_new
        h = sqrt(sum((coords[i,:] .- new_coords[j,:]).^2))
        C[i,j] = covariance_value(vm, h)
    end
    C
end

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
    C_inv   ::Matrix{Float64}   # inverse covariance
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

Predict at new locations using simple kriging.

ẑ(x₀) = μ + c₀'C⁻¹(z - μ·1)
σ²_SK(x₀) = C(0) - c₀'C⁻¹c₀
"""
function sk_predict(sk::SimpleKrigingResult, new_coords::AbstractMatrix)
    n_new = size(new_coords, 1)
    z_hat = zeros(n_new)
    σ²    = zeros(n_new)
    c0    = covariance_value(sk.vm, 0.0)
    r     = sk.z .- sk.μ  # residuals from mean

    for j in 1:n_new
        c_vec = [covariance_value(sk.vm,
                    sqrt(sum((sk.coords[i,:] .- new_coords[j,:]).^2)))
                 for i in 1:size(sk.coords,1)]
        λ = sk.C_inv * c_vec
        z_hat[j] = sk.μ + dot(λ, r)
        σ²[j]    = max(c0 - dot(λ, c_vec), 0.0)
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
    K_inv    ::Matrix{Float64}   # inverse of augmented system
end

"""
    ordinary_kriging(z, coords, vm) -> OrdinaryKrigingResult

Fit ordinary kriging (OK). Solves the augmented system:

  [C  1] [λ ]   [c₀]
  [1' 0] [μ*] = [1 ]

where μ* is the Lagrange multiplier ensuring Σλᵢ=1.
"""
function ordinary_kriging(z::AbstractVector, coords::AbstractMatrix,
                            vm::VariogramModel)
    n = length(z)
    C = _cov_matrix(vm, coords)
    # Augmented kriging system
    K     = [C ones(n); ones(1,n) 0.0]
    K_reg = K + 1e-10 * I
    K_inv = inv(K_reg)
    OrdinaryKrigingResult(vm, Matrix{Float64}(coords), Float64.(z), K_inv)
end

"""
    ok_predict(ok, new_coords) -> (z_hat, σ²_kriging)

Predict at new locations using ordinary kriging.
"""
function ok_predict(ok::OrdinaryKrigingResult, new_coords::AbstractMatrix)
    n      = size(ok.coords, 1)
    n_new  = size(new_coords, 1)
    z_hat  = zeros(n_new)
    σ²     = zeros(n_new)
    c0     = covariance_value(ok.vm, 0.0)

    for j in 1:n_new
        c_vec = [covariance_value(ok.vm,
                    sqrt(sum((ok.coords[i,:] .- new_coords[j,:]).^2)))
                 for i in 1:n]
        rhs = vcat(c_vec, 1.0)
        λ_μ = ok.K_inv * rhs
        λ   = λ_μ[1:n]
        μ_star = λ_μ[n+1]
        z_hat[j] = dot(λ, ok.z)
        σ²[j]    = max(c0 - dot(λ, c_vec) - μ_star, 0.0)
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
    K_inv  ::Matrix{Float64}   # inverse of augmented UK system
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

    # Augmented UK system: [C F; F' 0]
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
"""
function uk_predict(uk::UniversalKrigingResult, new_coords::AbstractMatrix)
    n      = size(uk.coords, 1)
    n_new  = size(new_coords, 1)
    p      = size(uk.F, 2)
    z_hat  = zeros(n_new)
    σ²     = zeros(n_new)
    c0     = covariance_value(uk.vm, 0.0)

    for j in 1:n_new
        c_vec = [covariance_value(uk.vm,
                    sqrt(sum((uk.coords[i,:] .- new_coords[j,:]).^2)))
                 for i in 1:n]
        f0    = _trend_matrix(new_coords[j:j,:], uk.degree)[1,:]
        rhs   = vcat(c_vec, f0)
        λ_μ   = uk.K_inv * rhs
        λ     = λ_μ[1:n]
        z_hat[j] = dot(λ, uk.z)
        σ²[j]    = max(c0 - dot(λ, c_vec), 0.0)
    end
    z_hat, σ²
end

# ── K-nearest-neighbour local search ─────────────────────────────────────────

"""
    _knn(coords, query_point, k) -> Vector{Int}

Return the indices of the `k` nearest rows in `coords` to `query_point`
(a length-2 vector). Uses brute-force sorted distances — fast enough for
the neighbourhood sizes used in kriging (k ≤ 64).
"""
function _knn(coords::AbstractMatrix, query_point, k::Int)
    n = size(coords, 1)
    k = min(k, n)
    qx = Float64(query_point[1]); qy = Float64(query_point[2])
    dists = [((coords[i,1] - qx)^2 + (coords[i,2] - qy)^2)
             for i in 1:n]
    partialsortperm(dists, 1:k)
end

"""
    ok_predict_local(ok, new_coords; max_neighbors) -> (z_hat, σ²_kriging)

Ordinary kriging with local neighbourhood search.  For each prediction
location only the `max_neighbors` nearest training points are used.

This is the recommended path for large datasets (faster than using all
data points while retaining prediction quality).
"""
function ok_predict_local(ok::OrdinaryKrigingResult, new_coords::AbstractMatrix;
                           max_neighbors::Int=32)
    n_new = size(new_coords, 1)
    z_hat = zeros(n_new)
    σ²    = zeros(n_new)

    for j in 1:n_new
        nn_idx   = _knn(ok.coords, new_coords[j,:], max_neighbors)
        c_local  = ok.coords[nn_idx, :]
        z_local  = ok.z[nn_idx]
        m_local  = ordinary_kriging(z_local, c_local, ok.vm)
        ẑj, σ²j  = ok_predict(m_local, reshape(new_coords[j,:], 1, 2))
        z_hat[j] = ẑj[1]
        σ²[j]    = σ²j[1]
    end
    z_hat, σ²
end

# ── Leave-one-out cross-validation ───────────────────────────────────────────

"""
    kriging_loo_cv(z, coords, vm; method) -> NamedTuple

Leave-one-out cross-validation for kriging accuracy.

Returns (rmse, mae, mean_bias, picp_95, mean_width, std_residuals, n).

`std_residuals` are the standardised residuals eᵢ/σ̂ᵢ; they should be
approximately N(0,1) for a well-calibrated kriging model.
"""
function kriging_loo_cv(z::AbstractVector, coords::AbstractMatrix,
                         vm::VariogramModel;
                         method::Symbol=:ordinary)
    n = length(z)
    errors      = zeros(n)
    std_resids  = zeros(n)
    in_pi       = falses(n)
    widths      = zeros(n)

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

        errors[i]     = ẑ[1] - z[i]
        se            = sqrt(max(σ²[1], 0.0))
        std_resids[i] = se > 0 ? errors[i] / se : 0.0
        in_pi[i]      = abs(errors[i]) <= 1.96 * se
        widths[i]     = 2 * 1.96 * se
    end

    (rmse         = sqrt(mean(errors.^2)),
     mae          = mean(abs.(errors)),
     mean_bias    = mean(errors),
     picp_95      = mean(in_pi),
     mean_width   = mean(widths),
     std_residuals= std_resids,
     n            = n)
end

# ── Grid interpolation ────────────────────────────────────────────────────────

"""
    kriging_grid(ok, x_range, y_range; max_neighbors) -> NamedTuple

Interpolate with ordinary kriging onto a regular grid defined by
`x_range` (a range or vector of x-values) and `y_range` (y-values).

Returns (x, y, z_hat, sigma2) where z_hat and sigma2 are matrices of
size (length(y_range) × length(x_range)).
"""
function kriging_grid(ok::OrdinaryKrigingResult,
                      x_range::AbstractVector,
                      y_range::AbstractVector;
                      max_neighbors::Int=32)
    nx = length(x_range)
    ny = length(y_range)
    z_hat  = zeros(ny, nx)
    σ²     = zeros(ny, nx)
    q_buf  = zeros(1, 2)   # reusable 1×2 prediction buffer

    for (jx, xv) in enumerate(x_range)
        for (iy, yv) in enumerate(y_range)
            q_buf[1,1] = xv; q_buf[1,2] = yv
            nn_idx = _knn(ok.coords, (xv, yv), max_neighbors)
            c_loc  = ok.coords[nn_idx, :]
            z_loc  = ok.z[nn_idx]
            m_loc  = ordinary_kriging(z_loc, c_loc, ok.vm)
            ẑj, s² = ok_predict(m_loc, q_buf)
            z_hat[iy, jx] = ẑj[1]
            σ²[iy, jx]    = s²[1]
        end
    end
    (x=collect(x_range), y=collect(y_range), z_hat=z_hat, sigma2=σ²)
end
