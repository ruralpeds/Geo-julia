# conley.jl — Conley (1999) spatial HAC standard errors using NearestNeighbors.jl

struct ConleyResult
    β::Vector{Float64}        # OLS coefficients
    se_ols::Vector{Float64}   # standard OLS SE
    se_conley::Vector{Float64}  # Conley spatial HAC SE
    t_stats::Vector{Float64}
    p_values::Vector{Float64}
    cutoff::Float64
    n::Int
    feature_names::Vector{String}
end

"""
    conley_se(y, X, coords; cutoff, kernel, feature_names) -> ConleyResult

OLS with Conley (1999) spatial HAC standard errors.
Uses NearestNeighbors.jl BallTree for efficient spatial neighbor lookup.
Bartlett kernel K(u) = max(0, 1-|u|) by default.
`coords` is n x 2 matrix of spatial coordinates.
`cutoff` is the spatial bandwidth in the same units as `coords`.
"""
function conley_se(y::AbstractVector, X::AbstractMatrix, coords::AbstractMatrix;
                   cutoff::Union{Float64,Nothing}=nothing,
                   kernel::Symbol=:bartlett,
                   feature_names=["x$i" for i in 1:size(X,2)])
    n, p = size(X)
    Xd   = hcat(ones(n), X)
    k    = p + 1

    # OLS
    XtX  = Xd' * Xd
    β    = (XtX + 1e-10*I) \ (Xd' * y)
    ε̂    = y .- Xd * β

    # OLS SE
    σ²   = dot(ε̂, ε̂) / (n - k)
    V_ols = σ² .* inv(XtX)
    se_ols = sqrt.(diag(V_ols))

    # Spatial bandwidth: default = 25th percentile of pairwise distances
    cut  = isnothing(cutoff) ? _default_cutoff(coords) : cutoff

    # Build BallTree for efficient spatial neighbor lookup within cutoff
    coords_t = Matrix(coords')  # NearestNeighbors expects d x n
    tree = BallTree(coords_t)

    # Spatial HAC meat: Omega = (1/n) Sum_i Sum_j K(d_ij/cut) eps_i eps_j x_i x_j'
    Ω = zeros(k, k)
    X_w = Xd .* ε̂   # n x k: x_i * eps_i

    for i in 1:n
        # Find all neighbors within cutoff distance
        neighbors = inrange(tree, coords_t[:, i], cut)
        for j in neighbors
            j < i && continue  # only count each pair once (plus diagonal)
            d   = sqrt(sum((coords[i,:] .- coords[j,:]).^2))
            u   = d / cut
            kw  = _kernel(u, kernel)
            kw == 0.0 && continue
            outer = X_w[i,:] * X_w[j,:]'
            Ω .+= kw .* (outer .+ outer')
        end
    end
    Ω ./= n

    XtX_inv  = inv(XtX)
    V_conley = XtX_inv * Ω * XtX_inv
    se_con   = sqrt.(abs.(diag(V_conley)))

    t_stats = β ./ max.(se_con, 1e-10)
    p_vals  = 2 .* (1 .- cdf.(Normal(), abs.(t_stats)))

    all_names = vcat("(Intercept)", feature_names)
    ConleyResult(β, se_ols, se_con, t_stats, p_vals, cut, n, all_names)
end

function _kernel(u::Float64, kernel::Symbol)
    u > 1.0 && return 0.0
    if kernel == :bartlett
        return 1.0 - u
    elseif kernel == :uniform
        return 1.0
    else
        return max(0.0, 1.0 - u^2)  # Epanechnikov-like
    end
end

function _default_cutoff(coords::AbstractMatrix)
    n = size(coords, 1)
    dists = Float64[]
    for i in 1:min(n, 50), j in i+1:min(n, 50)
        push!(dists, sqrt(sum((coords[i,:] .- coords[j,:]).^2)))
    end
    isempty(dists) && return 1.0
    quantile(dists, 0.25)
end

"""
    conley_summary(result) -> String

Print formatted regression table with OLS and Conley SE comparison.
"""
function conley_summary(r::ConleyResult)
    println("-"^70)
    println("Spatial HAC (Conley) Regression: n=$(r.n)  cutoff=$(round(r.cutoff,digits=4))")
    println("-"^70)
    println(@sprintf("%-18s %10s %12s %12s %8s", "Coef", "Estimate", "OLS SE", "Conley SE", "p-val"))
    println("-"^70)
    for j in 1:length(r.β)
        nm = get(r.feature_names, j, "$(j)")
        @printf("%-18s %10.4f %12.4f %12.4f %8.4f\n",
                nm, r.β[j], r.se_ols[j], r.se_conley[j], r.p_values[j])
    end
    println("-"^70)
end

import Printf: @sprintf, @printf
