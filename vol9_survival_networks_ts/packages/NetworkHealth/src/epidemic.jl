# epidemic.jl — SIR / SEIR / SEIRD compartmental ODE models
# Integration via RK4; R₀ estimation; herd immunity threshold

using Statistics

# ── ODE right-hand sides ──────────────────────────────────────────────────────

function _sir_rhs(u, p, t)
    S, I, R = u
    N = S + I + R
    β, γ = p
    dS = -β * S * I / N
    dI =  β * S * I / N - γ * I
    dR =  γ * I
    [dS, dI, dR]
end

function _seir_rhs(u, p, t)
    S, E, I, R = u
    N = S + E + I + R
    β, σ, γ = p
    dS = -β * S * I / N
    dE =  β * S * I / N - σ * E
    dI =  σ * E - γ * I
    dR =  γ * I
    [dS, dE, dI, dR]
end

function _seird_rhs(u, p, t)
    S, E, I, R, D = u
    N = S + E + I + R   # D is removed from N-at-risk
    β, σ, γ, μ = p
    dS = -β * S * I / N
    dE =  β * S * I / N - σ * E
    dI =  σ * E - (γ + μ) * I
    dR =  γ * I
    dD =  μ * I
    [dS, dE, dI, dR, dD]
end

# ── RK4 integrator ────────────────────────────────────────────────────────────

"""
    rk4_integrate(rhs, u0, tspan; dt) -> (times, states)

4th-order Runge-Kutta integration.
"""
function rk4_integrate(rhs::Function, u0::Vector{Float64},
                        tspan::Tuple{Float64,Float64};
                        dt::Float64=0.5, p=())
    t0, tf = tspan
    times  = collect(t0:dt:tf)
    isempty(times) && push!(times, t0)
    times[end] != tf && push!(times, tf)

    n_t    = length(times)
    states = zeros(length(u0), n_t)
    states[:, 1] = u0
    u = copy(u0)

    for i in 2:n_t
        h  = times[i] - times[i-1]
        t_i = times[i-1]
        k1 = rhs(u, p, t_i)
        k2 = rhs(u .+ h/2 .* k1, p, t_i + h/2)
        k3 = rhs(u .+ h/2 .* k2, p, t_i + h/2)
        k4 = rhs(u .+ h   .* k3, p, t_i + h)
        u  = u .+ h/6 .* (k1 .+ 2k2 .+ 2k3 .+ k4)
        # Clamp non-negative
        u  = max.(u, 0.0)
        states[:, i] = u
    end
    times, states
end

# ── SIR model ─────────────────────────────────────────────────────────────────

"""
    SIRResult

ODE solution for SIR model.

Fields: times, S, I, R, β, γ, R0, peak_I, peak_time, final_size.
"""
struct SIRResult
    times      ::Vector{Float64}
    S          ::Vector{Float64}
    I          ::Vector{Float64}
    R          ::Vector{Float64}
    β          ::Float64
    γ          ::Float64
    R0         ::Float64
    peak_I     ::Float64
    peak_time  ::Float64
    final_size ::Float64   # total fraction infected
end

"""
    sir_model(N, I0; β, γ, tspan, dt) -> SIRResult

Simulate SIR epidemic.

# Parameters
- `β` : transmission rate (contacts × probability per contact)
- `γ` : recovery rate (1/γ = mean infectious period)
- R₀ = β/γ
"""
function sir_model(N::Int, I0::Int=1;
                   β::Float64=0.3, γ::Float64=0.1,
                   tspan::Tuple{Float64,Float64}=(0.0, 160.0),
                   dt::Float64=0.5)
    S0 = Float64(N - I0)
    u0 = [S0, Float64(I0), 0.0]
    p  = (β, γ)
    times, states = rk4_integrate(_sir_rhs, u0, tspan; dt=dt, p=p)

    S = states[1,:] ./ N
    I = states[2,:] ./ N
    R = states[3,:] ./ N

    R0    = β / γ
    pi    = argmax(I)
    SIRResult(times, S, I, R, β, γ, R0, I[pi], times[pi], R[end])
end

# ── SEIR model ────────────────────────────────────────────────────────────────

"""
    SEIRResult

ODE solution for SEIR model.

Fields: times, S, E, I, R, β, σ, γ, R0, peak_I, peak_time, herd_threshold.
"""
struct SEIRResult
    times          ::Vector{Float64}
    S              ::Vector{Float64}
    E              ::Vector{Float64}
    I              ::Vector{Float64}
    R              ::Vector{Float64}
    β              ::Float64
    σ              ::Float64
    γ              ::Float64
    R0             ::Float64
    peak_I         ::Float64
    peak_time      ::Float64
    herd_threshold ::Float64   # 1 - 1/R₀
end

"""
    seir_model(N, E0, I0; β, σ, γ, tspan, dt) -> SEIRResult

Simulate SEIR epidemic.

- `σ` : exposed-to-infectious rate (1/σ = mean incubation period)
"""
function seir_model(N::Int, E0::Int=5, I0::Int=1;
                    β::Float64=0.3, σ::Float64=0.2, γ::Float64=0.1,
                    tspan::Tuple{Float64,Float64}=(0.0, 200.0),
                    dt::Float64=0.5)
    u0 = Float64[N - E0 - I0, E0, I0, 0.0]
    p  = (β, σ, γ)
    times, states = rk4_integrate(_seir_rhs, u0, tspan; dt=dt, p=p)

    S = states[1,:] ./ N; E = states[2,:] ./ N
    I = states[3,:] ./ N; R = states[4,:] ./ N

    R0  = β / γ
    pi  = argmax(I)
    h_t = R0 > 1 ? 1.0 - 1.0/R0 : 0.0
    SEIRResult(times, S, E, I, R, β, σ, γ, R0, I[pi], times[pi], h_t)
end

# ── SEIRD model ───────────────────────────────────────────────────────────────

"""
    SEIRDResult

ODE solution for SEIRD model (with disease-induced death).
"""
struct SEIRDResult
    times     ::Vector{Float64}
    S         ::Vector{Float64}
    E         ::Vector{Float64}
    I         ::Vector{Float64}
    R         ::Vector{Float64}
    D         ::Vector{Float64}
    β::Float64; σ::Float64; γ::Float64; μ::Float64
    R0        ::Float64
    ifr       ::Float64   # infection fatality ratio
    peak_I    ::Float64
    peak_time ::Float64
end

"""
    seird_model(N; β, σ, γ, μ, E0, I0, tspan, dt) -> SEIRDResult

`μ` is additional disease-specific death rate; IFR ≈ μ/(γ+μ).
"""
function seird_model(N::Int;
                     β::Float64=0.3, σ::Float64=0.2,
                     γ::Float64=0.09, μ::Float64=0.01,
                     E0::Int=5, I0::Int=1,
                     tspan::Tuple{Float64,Float64}=(0.0, 200.0),
                     dt::Float64=0.5)
    u0 = Float64[N - E0 - I0, E0, I0, 0.0, 0.0]
    p  = (β, σ, γ, μ)
    times, states = rk4_integrate(_seird_rhs, u0, tspan; dt=dt, p=p)

    S = states[1,:] ./ N; E = states[2,:] ./ N
    I = states[3,:] ./ N; R = states[4,:] ./ N; D = states[5,:] ./ N

    R0  = β / γ   # ignoring μ in R0 (approximate)
    pi  = argmax(I)
    ifr = μ / (γ + μ)
    SEIRDResult(times, S, E, I, R, D, β, σ, γ, μ, R0, ifr, I[pi], times[pi])
end

# ── R₀ estimation ─────────────────────────────────────────────────────────────

"""
    estimate_r0(incidence; method=:exponential_growth) -> (R0, se)

Estimate R₀ from an observed incidence time series.

`:exponential_growth`: fit OLS on log(incidence) in the exponential phase;
R₀ = 1 + r/γ where r = growth rate.
`:attack_rate`: solve R₀ from final attack rate z via z = 1 - exp(-R₀ z).
"""
function estimate_r0(incidence::AbstractVector;
                     method::Symbol=:exponential_growth,
                     γ::Float64=0.1,
                     n_points::Int=10)
    if method == :exponential_growth
        # Take first n_points of growth phase
        n  = min(n_points, length(incidence))
        y  = log.(max.(incidence[1:n], 1e-6))
        x  = collect(1.0:n)
        β1 = (n*sum(x.*y) - sum(x)*sum(y)) / (n*sum(x.^2) - sum(x)^2)
        r  = max(β1, 0.0)
        R0 = 1.0 + r / γ
        se = R0 * 0.1  # rough approximation
        return (R0=R0, growth_rate=r, se=se)

    elseif method == :attack_rate
        z = last(incidence) / first(incidence)  # approximation
        z = clamp(z, 0.01, 0.99)
        # Solve R₀ = -log(1-z)/z
        R0 = -log(1 - z) / z
        return (R0=R0, growth_rate=NaN, se=NaN)
    end
    error("Unknown method: $method")
end

# ── Network SIR (stochastic on graph) ─────────────────────────────────────────

"""
    network_sir(g, I0_nodes; β, γ, n_steps, n_sims, rng) -> NamedTuple

Stochastic SIR on a HealthGraph. Returns mean ± std trajectory over n_sims.
"""
function network_sir(g::HealthGraph, I0_nodes::Vector{Int};
                     β::Float64=0.3, γ::Float64=0.1,
                     n_steps::Int=100, n_sims::Int=50,
                     rng::AbstractRNG=Random.GLOBAL_RNG)
    n = g.n
    S_runs = zeros(n_sims, n_steps+1)
    I_runs = zeros(n_sims, n_steps+1)
    R_runs = zeros(n_sims, n_steps+1)

    for sim in 1:n_sims
        state = fill(:S, n)
        for i in I0_nodes; state[i] = :I; end
        S_runs[sim, 1] = count(state .== :S) / n
        I_runs[sim, 1] = count(state .== :I) / n
        R_runs[sim, 1] = count(state .== :R) / n

        for step in 1:n_steps
            new_state = copy(state)
            for i in 1:n
                if state[i] == :I
                    # Recovery
                    rand(rng) < γ && (new_state[i] = :R)
                    # Infect neighbours
                    for (j, w) in g.adj[i]
                        if state[j] == :S
                            prob = β * w / max(sum(ww for (_, ww) in g.adj[i]; init=1.0), 1.0)
                            rand(rng) < prob && (new_state[j] = :I)
                        end
                    end
                end
            end
            state = new_state
            S_runs[sim, step+1] = count(state .== :S) / n
            I_runs[sim, step+1] = count(state .== :I) / n
            R_runs[sim, step+1] = count(state .== :R) / n
        end
    end

    ts = 0:n_steps
    (times=collect(Float64, ts),
     S_mean=vec(mean(S_runs, dims=1)),
     I_mean=vec(mean(I_runs, dims=1)),
     R_mean=vec(mean(R_runs, dims=1)),
     S_std =vec(std(S_runs, dims=1)),
     I_std =vec(std(I_runs, dims=1)),
     R_std =vec(std(R_runs, dims=1)))
end
