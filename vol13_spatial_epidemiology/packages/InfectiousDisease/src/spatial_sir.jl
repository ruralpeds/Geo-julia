# spatial_sir.jl — Spatial patch SIR model on a network of counties/regions
# Uses OrdinaryDiffEq for the coupled multi-patch ODE system

using Statistics, LinearAlgebra, Random

struct SpatialSIRResult
    S::Matrix{Float64}      # S[t, patch] — susceptible fraction
    I::Matrix{Float64}      # I[t, patch]
    R::Matrix{Float64}      # R[t, patch]
    t::Vector{Float64}
    β_local::Vector{Float64}  # per-patch transmission rates
    γ::Float64
    coupling::Matrix{Float64} # movement/gravity matrix (row = from, col = to)
    R₀_global::Float64       # R₀ estimated from global growth
    peak_patch::Int          # patch with highest peak prevalence
    attack_rate::Vector{Float64}  # final size per patch
    n_patches::Int
end

"""
    spatial_sir(N, I₀, coords, β, γ; coupling_strength, gravity, t_end, dt, rng)
    -> SpatialSIRResult

Multi-patch SIR model. Each patch is a geographic unit (county).

Dynamics for patch p:
  S'ₚ = -βₚ·Sₚ·Iₚ/Nₚ  - Σᵩ Mₚᵩ·Sₚ/Nₚ + Σᵩ Mᵩₚ·Sᵩ/Nᵩ
  I'ₚ = βₚ·Sₚ·Iₚ/Nₚ + coupled infectious exposure - γ·Iₚ

where M is the gravity-based movement matrix.

`gravity = true`  → Mᵢⱼ ∝ Nᵢ·Nⱼ / dist(i,j)²
`gravity = false` → uniform coupling M = coupling_strength/n_patches
"""
function spatial_sir(N::AbstractVector{<:Real},
                      I₀::AbstractVector{<:Real},
                      coords::AbstractMatrix,   # n_patches × 2
                      β::Union{Real,AbstractVector},
                      γ::Real;
                      coupling_strength::Float64=0.01,
                      gravity::Bool=true,
                      t_end::Float64=180.0,
                      dt::Float64=0.5,
                      rng=Random.default_rng())
    n = length(N)
    size(coords, 1) == n || error("coords must have n_patches rows")
    β_vec = β isa Real ? fill(Float64(β), n) : Float64.(β)
    Nf    = Float64.(N)
    γf    = Float64(γ)

    # Movement / coupling matrix
    M = _gravity_matrix(coords, Nf; coupling=coupling_strength, use_gravity=gravity)

    # ODE: state u = [S₁..Sₙ, I₁..Iₙ, R₁..Rₙ] (length 3n)
    function spatial_sir_ode!(du, u, p, t)
        β_v, γ_, N_, M_, np = p
        for pp in 1:np
            s = u[pp]
            i = u[np + pp]
            # Local infection
            local_inf = β_v[pp] * s * i / max(N_[pp], 1.0)
            # Imported infectious pressure
            import_inf = 0.0
            for q in 1:np
                q == pp && continue
                import_inf += M_[q, pp] * u[np + q] / max(N_[q], 1.0)
            end
            import_inf *= s
            recover = γ_ * i
            du[pp]        = -(local_inf + import_inf)        # dS
            du[np + pp]   =  (local_inf + import_inf) - recover  # dI
            du[2*np + pp] =  recover                          # dR
        end
    end

    u0 = vcat(Nf .- Float64.(I₀), Float64.(I₀), zeros(n))
    tspan = (0.0, t_end)
    prob = ODEProblem(spatial_sir_ode!, u0, tspan, (β_vec, γf, Nf, M, n))
    sol  = solve(prob, Tsit5(); saveat=dt, abstol=1e-6, reltol=1e-6)

    T_len = length(sol.t)
    Sv = zeros(T_len, n); Iv = zeros(T_len, n); Rv = zeros(T_len, n)
    for ti in 1:T_len
        for p in 1:n
            Sv[ti, p] = max(0.0, sol[p, ti])
            Iv[ti, p] = max(0.0, sol[n + p, ti])
            Rv[ti, p] = max(0.0, sol[2*n + p, ti])
        end
    end

    peak_patch  = argmax(maximum(Iv; dims=1)[:])
    attack_rate = Rv[end, :] ./ Nf
    # Global R₀ from early exponential growth
    total_I = sum(Iv; dims=2)[:]
    R₀_global = _estimate_r0_growth(total_I[1:min(30,T_len)], γf, dt)

    SpatialSIRResult(Sv./Nf', Iv./Nf', Rv./Nf', collect(sol.t),
                     β_vec, γf, M, R₀_global, peak_patch, attack_rate, n)
end

function _gravity_matrix(coords::AbstractMatrix, N::Vector{Float64};
                           coupling::Float64, use_gravity::Bool)
    n = length(N)
    M = zeros(n, n)
    if !use_gravity
        for i in 1:n, j in 1:n
            i != j && (M[i,j] = coupling / (n-1))
        end
        return M
    end
    for i in 1:n, j in 1:n
        i == j && continue
        d = sqrt(sum((coords[i,:] .- coords[j,:]).^2))
        M[i,j] = coupling * N[i] * N[j] / max(d^2, 1.0)
    end
    # Row-normalise so each patch exports at most `coupling` fraction
    for i in 1:n
        row_sum = sum(M[i,:])
        row_sum > coupling * N[i] && (M[i,:] .*= coupling * N[i] / row_sum)
    end
    M
end

function _estimate_r0_growth(I_series::AbstractVector, γ::Float64, dt::Float64)
    # Fit exponential: log(I) = a + r·t; R₀ ≈ (1 + r/γ) or (γ+r)/γ
    n = length(I_series)
    I_pos = I_series[I_series .> 0]
    length(I_pos) < 3 && return NaN
    log_I = log.(I_pos[1:min(20, end)])
    t_idx = Float64.(1:length(log_I)) .* dt
    t̄, ȳ = mean(t_idx), mean(log_I)
    r = sum((t_idx .- t̄) .* (log_I .- ȳ)) / max(sum((t_idx .- t̄).^2), 1e-12)
    max(1.0, (γ + r) / γ)
end
