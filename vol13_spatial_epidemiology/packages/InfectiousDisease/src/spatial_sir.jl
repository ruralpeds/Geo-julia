# spatial_sir.jl — Spatial patch SIR model on a network of counties/regions

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

    ts = 0.0:dt:t_end; T = length(ts)
    Sv = zeros(T, n); Iv = zeros(T, n); Rv = zeros(T, n)
    Sv[1, :] = Nf .- Float64.(I₀)
    Iv[1, :] = Float64.(I₀)

    for t in 2:T
        s = Sv[t-1, :]; i_prev = Iv[t-1, :]; r = Rv[t-1, :]

        # Patch-level ODEs with coupling (Euler for speed)
        ds = zeros(n); di = zeros(n); dr = zeros(n)
        for p in 1:n
            local_inf  = β_vec[p] * s[p] * i_prev[p] / max(Nf[p], 1.0)
            # Imported infectious pressure: Σᵩ M[q,p] * I[q]/N[q]
            import_inf = sum(M[q,p] * i_prev[q] / max(Nf[q],1.0) for q in 1:n if q!=p; init=0.0) * s[p]
            recover    = γf * i_prev[p]
            ds[p] = -(local_inf + import_inf)
            di[p] =  (local_inf + import_inf) - recover
            dr[p] =  recover
        end
        Sv[t, :] = max.(0.0, s .+ dt .* ds)
        Iv[t, :] = max.(0.0, i_prev .+ dt .* di)
        Rv[t, :] = r .+ dt .* dr
        # Renormalize
        for p in 1:n
            tot = Sv[t,p]+Iv[t,p]+Rv[t,p]
            f   = Nf[p]/max(tot, 1e-9)
            Sv[t,p]*=f; Iv[t,p]*=f; Rv[t,p]*=f
        end
    end

    peak_patch  = argmax(maximum(Iv; dims=1)[:])
    attack_rate = Rv[end, :] ./ Nf
    # Global R₀ from early exponential growth
    total_I = sum(Iv; dims=2)[:]
    R₀_global = _estimate_r0_growth(total_I[1:min(30,T)], γf, dt)

    SpatialSIRResult(Sv./Nf', Iv./Nf', Rv./Nf', collect(ts),
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
