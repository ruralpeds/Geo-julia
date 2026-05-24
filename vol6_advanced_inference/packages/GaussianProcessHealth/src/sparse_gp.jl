# sparse_gp.jl — Sparse GP via inducing points (FITC approximation)
# Chapter 44.3
#
# Uses AbstractGPs.jl sparse GP approximations where possible,
# with fallback to manual FITC for custom distance functions.
#
# Snelson & Ghahramani (2006) "Sparse Gaussian Processes using Pseudo-inputs"
# Reduces O(n³) exact GP to O(nm²) where m ≪ n inducing points.

using LinearAlgebra: cholesky, Symmetric, I, diag, norm

"""
    SparseGP

Sparse GP model using m inducing points.
"""
struct SparseGP
    kernel      ::GPKernel
    X_train     ::Matrix{Float64}
    y_train     ::Vector{Float64}
    X_induce    ::Matrix{Float64}   # m × d inducing inputs
    σ²_noise    ::Float64
    Kmm_inv     ::Matrix{Float64}   # Kuu⁻¹
    α_sparse    ::Vector{Float64}   # (Qmm + Λ)⁻¹ y
    log_elbo    ::Float64           # evidence lower bound
    dist_fn     ::Function
end

"""
    sparse_gp_fit(X, y, kernel; m_inducing, σ²_noise, dist_fn) -> SparseGP

Fit FITC sparse GP with `m_inducing` pseudo-inputs placed at random subsets.

FITC approximation:
  Q_nn ≈ Knm Kmm⁻¹ Kmn  (rank-m approximation to Knn)
  Λ = diag(Knn - Qnn) + σ²_n I  (diagonal correction)
  Posterior: α = (Qnn + Λ)⁻¹ y  (via Woodbury identity)
"""
function sparse_gp_fit(X        ::AbstractMatrix,
                       y        ::AbstractVector,
                       kernel   ::GPKernel;
                       m_inducing::Int     = 20,
                       σ²_noise  ::Float64 = 0.01,
                       dist_fn   ::Function = (a,b) -> norm(a.-b),
                       rng       ::AbstractRNG = Random.GLOBAL_RNG)

    X_ = Float64.(Matrix(X))
    y_ = Float64.(y)
    n  = size(X_, 1)

    # Inducing points: random subset
    m = min(m_inducing, n)
    X_induce = X_[randperm(rng, n)[1:m], :]

    # Kernel matrices
    Kmm = kernel_matrix(kernel, X_induce, X_induce; dist_fn=dist_fn) + 1e-8I
    Knm = kernel_matrix(kernel, X_, X_induce; dist_fn=dist_fn)  # n × m
    knn_diag = [kernel(0.0) for _ in 1:n]   # diag(Knn) = σ² (stationary)

    # FITC diagonal: Λ = diag(Knn - Qnn) + σ²_n
    Kmm_inv = inv(Symmetric(Kmm))
    Qnn_diag = vec(sum((Knm * Kmm_inv) .* Knm; dims=2))
    Λ_diag  = max.(knn_diag .- Qnn_diag, 1e-8) .+ σ²_noise
    Λ_inv   = 1.0 ./ Λ_diag

    # Woodbury: (Qnn + Λ)⁻¹ = Λ⁻¹ - Λ⁻¹ Knm (Kmm + Knm'Λ⁻¹Knm)⁻¹ Knm'Λ⁻¹
    A    = Kmm + Knm' * (Λ_inv .* Knm)    # m × m
    L_A  = cholesky(Symmetric(A + 1e-8I)).L
    Λ_inv_y   = Λ_inv .* y_
    Λ_inv_Knm = Λ_inv .* Knm              # n × m (broadcast)

    # α = (Qnn + Λ)⁻¹ y via Woodbury
    t      = L_A \ (Knm' * Λ_inv_y)       # m
    α_wood = Λ_inv_y .- Λ_inv_Knm * (L_A' \ t)

    # ELBO (lower bound on log p(y|θ))
    logdet_term = sum(log, diag(L_A)) - 0.5*sum(log, Λ_diag) +
                  0.5*sum(log, diag(cholesky(Symmetric(Kmm + 1e-8I)).L))
    data_fit    = -0.5 * dot(y_, α_wood)
    trace_term  = -0.5 * sum(max.(knn_diag .- Qnn_diag, 0.0)) / σ²_noise
    elbo        = data_fit - logdet_term + trace_term - n/2 * log(2π)

    SparseGP(kernel, X_, y_, X_induce, σ²_noise, Matrix(Kmm_inv), α_wood, elbo, dist_fn)
end

"""
    sparse_gp_predict(model, X_star) -> (mean, var, std)

Predictive mean and variance for sparse GP at test points.
"""
function sparse_gp_predict(model::SparseGP, X_star::AbstractMatrix)
    X_ = Float64.(Matrix(X_star))
    kss_diag = [model.kernel(0.0) for _ in 1:size(X_,1)]

    # Mean: K_*n (Qnn+Λ)⁻¹ y
    Ks_n = kernel_matrix(model.kernel, X_, model.X_train; dist_fn=model.dist_fn)
    μ = Ks_n * model.α_sparse

    # Variance: k** - Q** + posterior correction (simplified FITC)
    Kns = kernel_matrix(model.kernel, X_, model.X_induce; dist_fn=model.dist_fn)
    Qss_diag = vec(sum((Kns * model.Kmm_inv) .* Kns; dims=2))
    var_ = max.(kss_diag .- Qss_diag .+ model.σ²_noise, 0.0)

    (mean=μ, var=var_, std=sqrt.(var_))
end
