# compartmental.jl — SIR, SEIR, SEIS compartmental ODE models

using Statistics

# ─── SIR ─────────────────────────────────────────────────────────────────────

struct SIRResult
    S::Vector{Float64}    # susceptible
    I::Vector{Float64}    # infectious
    R::Vector{Float64}    # removed (recovered + dead)
    t::Vector{Float64}    # time grid
    β::Float64            # transmission rate
    γ::Float64            # recovery rate
    R₀::Float64           # basic reproduction number β/γ
    peak_I::Float64       # peak infectious proportion
    peak_t::Float64       # time of peak
    attack_rate::Float64  # final epidemic size / N (fraction)
    N::Float64
    method::Symbol
end

"""
    sir(N, I₀, β, γ; t_end, dt, method) -> SIRResult

Simulate the deterministic SIR model:
  S' = -β·S·I/N
  I' = β·S·I/N - γ·I
  R' = γ·I

- `N`   — total population
- `I₀`  — initial infectious (individuals)
- `β`   — transmission rate (contacts × prob per day)
- `γ`   — recovery rate = 1/infectious_period
- `method` = :euler (fast) or :rk4 (accurate, default)

R₀ = β/γ; epidemic occurs iff R₀ > 1.
"""
function sir(N::Real, I₀::Real, β::Real, γ::Real;
             t_end::Float64=365.0,
             dt::Float64=0.1,
             method::Symbol=:rk4)
    N  = Float64(N); β = Float64(β); γ = Float64(γ)
    I₀ = clamp(Float64(I₀), 1.0, N-1)
    S₀ = N - I₀; R_init = 0.0
    t_end <= 0 && error("t_end must be positive")
    dt <= 0    && error("dt must be positive")

    ts = 0.0:dt:t_end
    T  = length(ts)
    S  = zeros(T); I = zeros(T); R = zeros(T)
    S[1] = S₀; I[1] = I₀; R[1] = R_init

    f_S(s,i) = -β * s * i / N
    f_I(s,i) = β * s * i / N - γ * i
    f_R(_,i) = γ * i

    for t in 2:T
        if method == :euler
            S[t] = max(0.0, S[t-1] + dt * f_S(S[t-1], I[t-1]))
            I[t] = max(0.0, I[t-1] + dt * f_I(S[t-1], I[t-1]))
            R[t] = R[t-1] + dt * f_R(S[t-1], I[t-1])
        else  # RK4
            s,i,r = S[t-1], I[t-1], R[t-1]
            k1s = dt*f_S(s,i);    k1i = dt*f_I(s,i);    k1r = dt*f_R(s,i)
            s2,i2 = s+k1s/2,i+k1i/2
            k2s = dt*f_S(s2,i2);  k2i = dt*f_I(s2,i2);  k2r = dt*f_R(s2,i2)
            s3,i3 = s+k2s/2,i+k2i/2
            k3s = dt*f_S(s3,i3);  k3i = dt*f_I(s3,i3);  k3r = dt*f_R(s3,i3)
            s4,i4 = s+k3s,i+k3i
            k4s = dt*f_S(s4,i4);  k4i = dt*f_I(s4,i4);  k4r = dt*f_R(s4,i4)
            S[t] = max(0.0, s + (k1s+2k2s+2k3s+k4s)/6)
            I[t] = max(0.0, i + (k1i+2k2i+2k3i+k4i)/6)
            R[t] = r + (k1r+2k2r+2k3r+k4r)/6
        end
        # Conservation: S+I+R=N
        tot = S[t]+I[t]+R[t]
        S[t] *= N/tot; I[t] *= N/tot; R[t] *= N/tot
    end

    peak_idx = argmax(I)
    R₀_val   = β/γ
    SIRResult(S./N, I./N, R./N, collect(ts),
              β, γ, R₀_val,
              maximum(I)/N, ts[peak_idx],
              R[end]/N, N, method)
end

# ─── SEIR ─────────────────────────────────────────────────────────────────────

struct SEIRResult
    S::Vector{Float64}; E::Vector{Float64}
    I::Vector{Float64}; R::Vector{Float64}
    t::Vector{Float64}
    β::Float64; σ::Float64; γ::Float64
    R₀::Float64; peak_I::Float64; peak_t::Float64
    attack_rate::Float64; N::Float64
end

"""
    seir(N, E₀, I₀, β, σ, γ; t_end, dt) -> SEIRResult

Deterministic SEIR model with latent (exposed) compartment:
  S' = -β·S·I/N
  E' = β·S·I/N - σ·E
  I' = σ·E - γ·I
  R' = γ·I

- `σ` — rate of progression from exposed to infectious = 1/incubation_period
"""
function seir(N::Real, E₀::Real, I₀::Real, β::Real, σ::Real, γ::Real;
              t_end::Float64=365.0, dt::Float64=0.1)
    N=Float64(N); β=Float64(β); σ=Float64(σ); γ=Float64(γ)
    E₀=clamp(Float64(E₀),0.0,N); I₀=clamp(Float64(I₀),0.0,N-E₀)
    ts=0.0:dt:t_end; T=length(ts)
    S=zeros(T); E=zeros(T); I=zeros(T); R=zeros(T)
    S[1]=N-E₀-I₀; E[1]=E₀; I[1]=I₀

    for t in 2:T
        s,e,i,r = S[t-1],E[t-1],I[t-1],R[t-1]
        inf_rate = β*s*i/N
        # RK4
        function deriv(s,e,i,r)
            ds = -β*s*i/N
            de = β*s*i/N - σ*e
            di = σ*e - γ*i
            dr = γ*i
            ds,de,di,dr
        end
        k1 = deriv(s,e,i,r)
        k2 = deriv(s+dt*k1[1]/2,e+dt*k1[2]/2,i+dt*k1[3]/2,r+dt*k1[4]/2)
        k3 = deriv(s+dt*k2[1]/2,e+dt*k2[2]/2,i+dt*k2[3]/2,r+dt*k2[4]/2)
        k4 = deriv(s+dt*k3[1],  e+dt*k3[2],  i+dt*k3[3],  r+dt*k3[4])
        S[t]=max(0.0,s+dt*(k1[1]+2k2[1]+2k3[1]+k4[1])/6)
        E[t]=max(0.0,e+dt*(k1[2]+2k2[2]+2k3[2]+k4[2])/6)
        I[t]=max(0.0,i+dt*(k1[3]+2k2[3]+2k3[3]+k4[3])/6)
        R[t]=r+dt*(k1[4]+2k2[4]+2k3[4]+k4[4])/6
        tot=S[t]+E[t]+I[t]+R[t]; f=N/tot
        S[t]*=f; E[t]*=f; I[t]*=f; R[t]*=f
    end
    peak_idx=argmax(I)
    SEIRResult(S./N,E./N,I./N,R./N,collect(ts),
               β,σ,γ, β/γ, maximum(I)/N, ts[peak_idx], R[end]/N, N)
end

# ─── Stochastic SIR ──────────────────────────────────────────────────────────

"""
    sir_stochastic(N, I₀, β, γ; t_end, dt, rng) -> SIRResult

Gillespie-style τ-leaping stochastic SIR.
Uses Poisson increments for infection and recovery events at each step dt.
"""
function sir_stochastic(N::Int, I₀::Int, β::Real, γ::Real;
                         t_end::Float64=365.0, dt::Float64=1.0,
                         rng=Random.default_rng())
    β=Float64(β); γ=Float64(γ)
    ts=0.0:dt:t_end; T=length(ts)
    Sv=zeros(T); Iv=zeros(T); Rv=zeros(T)
    Sv[1]=N-I₀; Iv[1]=I₀

    for t in 2:T
        s,i,r=Sv[t-1],Iv[t-1],Rv[t-1]
        λ_inf = β*s*i/N*dt
        λ_rec = γ*i*dt
        Δinf = rand(rng, Poisson_approx(max(λ_inf,0.0)))
        Δrec = rand(rng, Poisson_approx(max(λ_rec,0.0)))
        Δinf = min(Δinf, s); Δrec = min(Δrec, i)
        Sv[t]=s-Δinf; Iv[t]=i+Δinf-Δrec; Rv[t]=r+Δrec
    end
    peak_idx=argmax(Iv)
    SIRResult(Sv./N,Iv./N,Rv./N,collect(ts),
              β,γ,β/γ, maximum(Iv)/N, ts[peak_idx], Rv[end]/N, Float64(N), :stochastic)
end

struct Poisson_approx; λ::Float64; end
function Base.rand(rng::AbstractRNG, d::Poisson_approx)
    λ=d.λ; λ<=0 && return 0
    λ>30 && return max(0,round(Int,λ+sqrt(λ)*randn(rng)))
    L=exp(-λ); k=0; p=1.0
    while p>L; k+=1; p*=rand(rng); end; k-1
end
