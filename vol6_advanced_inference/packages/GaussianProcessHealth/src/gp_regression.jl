# gp_regression.jl — Exact GP regression using AbstractGPs.jl + Optim.jl
# Chapter 44.2
#
# GP prior: f ~ GP(m(x), k(x,x'))
# Likelihood: y | f ~ N(f, σ²_n I)
# Posterior: f* | y ~ N(μ*, Σ*)
# Uses AbstractGPs for posterior computation and Optim.jl for hyperparameter tuning.

using LinearAlgebra: cholesky, Symmetric, I, diag, norm

"""
    GPModel

A fitted Gaussian Process model.
"""
struct GPModel
    kernel    ::GPKernel
    X_train   ::Matrix{Float64}   # n × d input matrix
    y_train   ::Vector{Float64}   # n-vector of targets
    σ²_noise  ::Float64           # noise variance
    α         ::Vector{Float64}   # (K + σ²I)⁻¹ y  (cached)
    L         ::Matrix{Float64}   # Cholesky factor of (K + σ²I)
    log_ml    ::Float64           # log marginal likelihood
    dist_fn   ::Function
    mean_fn   ::Function          # prior mean function
end

"""
    gp_fit(X, y, kernel; σ²_noise, dist_fn, mean_fn) -> GPModel

Fit an exact GP model via Cholesky decomposition.

# Arguments
- `X`        : n × d training inputs (or n × 2 [lat,lon] for geographic)
- `y`        : n-vector of targets
- `kernel`   : GPKernel instance
- `σ²_noise` : observation noise variance
- `dist_fn`  : distance function (default: Euclidean; use haversine_dist_deg for geo)
- `mean_fn`  : prior mean function (default: zero mean)
"""
function gp_fit(X        ::AbstractMatrix,
                y        ::AbstractVector,
                kernel   ::GPKernel;
                σ²_noise ::Float64   = 0.01,
                dist_fn  ::Function  = (a,b) -> norm(a.-b),
                mean_fn  ::Function  = x -> 0.0)

    n  = size(X, 1)
    X_ = Float64.(Matrix(X))
    y_ = Float64.(y) .- mean_fn.(eachrow(X_))

    # Build kernel matrix
    K  = kernel_matrix(kernel, X_, X_; dist_fn=dist_fn)
    # Add noise + jitter for numerical stability
    Kn = K + (σ²_noise + 1e-8) * I

    # Cholesky
    L  = cholesky(Symmetric(Kn)).L
    α  = L' \ (L \ y_)

    # Log marginal likelihood
    log_ml = -0.5 * dot(y_, α) - sum(log, diag(L)) - n/2 * log(2π)

    GPModel(kernel, X_, y_, σ²_noise, α, Matrix(L), log_ml, dist_fn, mean_fn)
end

"""
    gp_predict(model, X_star) -> (mean::Vector, var::Vector, std::Vector)

Posterior mean and variance at test points X_star.
"""
function gp_predict(model   ::GPModel,
                    X_star  ::AbstractMatrix)

    X_ = Float64.(Matrix(X_star))
    K_star = kernel_matrix(model.kernel, X_, model.X_train; dist_fn=model.dist_fn)
    K_ss   = kernel_matrix(model.kernel, X_, X_;            dist_fn=model.dist_fn)

    # μ* = K_star * α
    μ = K_star * model.α .+ [model.mean_fn(r) for r in eachrow(X_)]

    # Σ* = K_** - K_*ₙ (L L')⁻¹ K_ₙ* = K_** - v'v, v = L⁻¹K_ₙ*
    v     = model.L \ K_star'   # n_train × n_star
    var_  = max.(diag(K_ss) .- vec(sum(v.^2; dims=1)), 0.0)

    (mean=μ, var=var_, std=sqrt.(var_))
end

"""
    gp_log_marginal_likelihood(model) -> Float64

Return the log marginal likelihood of the fitted model.
Useful for model comparison and hyperparameter selection.
"""
gp_log_marginal_likelihood(model::GPModel) = model.log_ml

"""
    optimize_hyperparams!(kernel, X, y; σ²_noise, n_restarts, dist_fn) -> GPModel

Type-II maximum likelihood hyperparameter optimisation using Optim.jl.
Maximises log p(y|θ) over kernel parameters via Nelder-Mead.
"""
function optimize_hyperparams!(kernel   ::GPKernel,
                                X        ::AbstractMatrix,
                                y        ::AbstractVector;
                                σ²_noise ::Float64 = 0.01,
                                n_restarts::Int    = 3,
                                dist_fn  ::Function = (a,b) -> norm(a.-b))

    best_ml   = -Inf
    best_model = gp_fit(X, y, kernel; σ²_noise=σ²_noise, dist_fn=dist_fn)

    θ0 = get_params(kernel)
    p  = length(θ0)

    for restart in 1:n_restarts
        θ_init = restart == 1 ? θ0 : θ0 .+ 0.5 .* randn(p)

        # Minimise -log ML using Optim.jl Nelder-Mead
        obj = θ -> begin
            k_ = set_params(kernel, θ)
            m  = try
                gp_fit(X, y, k_; σ²_noise=σ²_noise, dist_fn=dist_fn)
            catch
                return Inf
            end
            -m.log_ml
        end

        result = Optim.optimize(obj, θ_init, Optim.NelderMead(),
                                Optim.Options(iterations=200, g_tol=1e-8))
        θ_opt = Optim.minimizer(result)

        k_opt = set_params(kernel, θ_opt)
        m_opt = try
            gp_fit(X, y, k_opt; σ²_noise=σ²_noise, dist_fn=dist_fn)
        catch
            continue
        end
        if m_opt.log_ml > best_ml
            best_ml    = m_opt.log_ml
            best_model = m_opt
        end
    end
    best_model
end

"""
    marginal_likelihood_surface(kernel_fn, X, y, param1_range, param2_range)
                               -> Matrix{Float64}

Compute log ML on a grid of (σ², ℓ) values for visualisation.
"""
function marginal_likelihood_surface(kernel_fn  ::Function,
                                      X          ::AbstractMatrix,
                                      y          ::AbstractVector,
                                      σ²_range   ::AbstractVector,
                                      ℓ_range    ::AbstractVector;
                                      σ²_noise   ::Float64 = 0.01)
    lml = fill(-Inf, length(σ²_range), length(ℓ_range))
    for (i, s) in enumerate(σ²_range), (j, l) in enumerate(ℓ_range)
        try
            m = gp_fit(X, y, kernel_fn(s, l); σ²_noise=σ²_noise)
            lml[i,j] = m.log_ml
        catch; end
    end
    lml
end
