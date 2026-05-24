# epidemic.jl — SIR / SEIR / SEIRD compartmental ODE models
# Integration via OrdinaryDiffEq.jl (Tsit5); R₀ estimation; network SIR

using Statistics

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
    S0 = (N - I0) / N
    I0_frac = I0 / N
    R0_frac = 0.0
    u0 = [S0, I0_frac, R0_frac]

    function sir!(du, u, p, t)
        S, I, R = u
        β_p, γ_p = p
        du[1] = -β_p * S * I
        du[2] =  β_p * S * I - γ_p * I
        du[3] =  γ_p * I
    end

    prob = ODEProblem(sir!, u0, tspan, [β, γ])
    sol  = solve(prob, Tsit5(); saveat=dt)

    times = sol.t
    S = [sol[1, i] for i in 1:length(sol)]
    I = [sol[2, i] for i in 1:length(sol)]
    R = [sol[3, i] for i in 1:length(sol)]

    R0_val = β / γ
    pi     = argmax(I)
    SIRResult(times, S, I, R, β, γ, R0_val, I[pi], times[pi], R[end])
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
    u0 = [(N - E0 - I0) / N, E0 / N, I0 / N, 0.0]

    function seir!(du, u, p, t)
        S, E, I, R = u
        β_p, σ_p, γ_p = p
        du[1] = -β_p * S * I
        du[2] =  β_p * S * I - σ_p * E
        du[3] =  σ_p * E - γ_p * I
        du[4] =  γ_p * I
    end

    prob = ODEProblem(seir!, u0, tspan, [β, σ, γ])
    sol  = solve(prob, Tsit5(); saveat=dt)

    times = sol.t
    S = [sol[1, i] for i in 1:length(sol)]
    E = [sol[2, i] for i in 1:length(sol)]
    I = [sol[3, i] for i in 1:length(sol)]
    R = [sol[4, i] for i in 1:length(sol)]

    R0_val = β / γ
    pi     = argmax(I)
    h_t    = R0_val > 1 ? 1.0 - 1.0/R0_val : 0.0
    SEIRResult(times, S, E, I, R, β, σ, γ, R0_val, I[pi], times[pi], h_t)
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
    u0 = [(N - E0 - I0) / N, E0 / N, I0 / N, 0.0, 0.0]

    function seird!(du, u, p, t)
        S, E, I, R, D = u
        β_p, σ_p, γ_p, μ_p = p
        N_eff = S + E + I + R   # D removed from at-risk population
        N_eff = max(N_eff, 1e-10)
        du[1] = -β_p * S * I / N_eff
        du[2] =  β_p * S * I / N_eff - σ_p * E
        du[3] =  σ_p * E - (γ_p + μ_p) * I
        du[4] =  γ_p * I
        du[5] =  μ_p * I
    end

    prob = ODEProblem(seird!, u0, tspan, [β, σ, γ, μ])
    sol  = solve(prob, Tsit5(); saveat=dt)

    times = sol.t
    S = [sol[1, i] for i in 1:length(sol)]
    E = [sol[2, i] for i in 1:length(sol)]
    I = [sol[3, i] for i in 1:length(sol)]
    R = [sol[4, i] for i in 1:length(sol)]
    D = [sol[5, i] for i in 1:length(sol)]

    R0_val = β / γ   # ignoring μ in R0 (approximate)
    pi     = argmax(I)
    ifr    = μ / (γ + μ)
    SEIRDResult(times, S, E, I, R, D, β, σ, γ, μ, R0_val, ifr, I[pi], times[pi])
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
