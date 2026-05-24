# compartmental.jl — SIR, SEIR, SEIS compartmental ODE models
# Uses OrdinaryDiffEq (Tsit5) instead of hand-rolled Euler/RK4

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

    # ODE right-hand side: u = [S, I, R]
    function sir_ode!(du, u, p, t)
        S_, I_, R_ = u
        β_, γ_, N_ = p
        infection = β_ * S_ * I_ / N_
        recovery  = γ_ * I_
        du[1] = -infection
        du[2] =  infection - recovery
        du[3] =  recovery
    end

    u0   = [S₀, I₀, R_init]
    tspan = (0.0, t_end)
    prob  = ODEProblem(sir_ode!, u0, tspan, (β, γ, N))
    sol   = solve(prob, Tsit5(); saveat=dt, abstol=1e-8, reltol=1e-8)

    ts = sol.t
    T  = length(ts)
    S  = [max(0.0, sol[1, i]) for i in 1:T]
    Iv = [max(0.0, sol[2, i]) for i in 1:T]
    Rv = [max(0.0, sol[3, i]) for i in 1:T]

    peak_idx = argmax(Iv)
    R₀_val   = β/γ
    SIRResult(S./N, Iv./N, Rv./N, collect(ts),
              β, γ, R₀_val,
              maximum(Iv)/N, ts[peak_idx],
              Rv[end]/N, N, method)
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

    function seir_ode!(du, u, p, t)
        S_, E_, I_, R_ = u
        β_, σ_, γ_, N_ = p
        infection = β_ * S_ * I_ / N_
        du[1] = -infection
        du[2] =  infection - σ_ * E_
        du[3] =  σ_ * E_ - γ_ * I_
        du[4] =  γ_ * I_
    end

    u0    = [N - E₀ - I₀, E₀, I₀, 0.0]
    tspan = (0.0, t_end)
    prob  = ODEProblem(seir_ode!, u0, tspan, (β, σ, γ, N))
    sol   = solve(prob, Tsit5(); saveat=dt, abstol=1e-8, reltol=1e-8)

    ts = sol.t; T = length(ts)
    S  = [max(0.0, sol[1, i]) for i in 1:T]
    E  = [max(0.0, sol[2, i]) for i in 1:T]
    Iv = [max(0.0, sol[3, i]) for i in 1:T]
    Rv = [max(0.0, sol[4, i]) for i in 1:T]

    peak_idx = argmax(Iv)
    SEIRResult(S./N, E./N, Iv./N, Rv./N, collect(ts),
               β, σ, γ, β/γ, maximum(Iv)/N, ts[peak_idx], Rv[end]/N, N)
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
        Δinf = rand(rng, Poisson(max(λ_inf, 0.0)))
        Δrec = rand(rng, Poisson(max(λ_rec, 0.0)))
        Δinf = min(Δinf, round(Int, s)); Δrec = min(Δrec, round(Int, i))
        Sv[t]=s-Δinf; Iv[t]=i+Δinf-Δrec; Rv[t]=r+Δrec
    end
    peak_idx=argmax(Iv)
    SIRResult(Sv./N,Iv./N,Rv./N,collect(ts),
              β,γ,β/γ, maximum(Iv)/N, ts[peak_idx], Rv[end]/N, Float64(N), :stochastic)
end
