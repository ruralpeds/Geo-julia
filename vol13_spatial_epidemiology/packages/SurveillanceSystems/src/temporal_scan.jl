# temporal_scan.jl — Temporal Kulldorff scan statistic

using Statistics, Random

struct TemporalScanResult
    λ_obs::Float64          # observed LLR for most likely cluster
    p_value::Float64        # Monte Carlo p-value
    cluster_start::Int      # start time index of detected cluster
    cluster_end::Int        # end time index
    cluster_cases::Int      # observed cases in cluster window
    expected_cases::Float64 # expected cases under H₀ (proportional to window length)
    rr::Float64             # relative risk = (c/μ) / ((n-c)/(n-μ))
    n_sim::Int
    significant::Bool       # p < 0.05
end

"""
    temporal_scan(x; max_window, n_sim, rng) -> TemporalScanResult

Temporal Kulldorff scan statistic (Kulldorff 1997) for detecting the most
anomalous time window in a count series.

For each candidate window [t₁, t₂] with length ≤ max_window:
  - c  = observed cases in window
  - μ  = expected cases (proportional to window length / total length)
  - LLR = c·log(c/μ) + (n-c)·log((n-c)/(n-μ))  [Poisson model]
  - Retain window with maximum LLR

Monte Carlo: simulate `n_sim` Poisson(μₜ) series; compute LLR_max for each.
p-value = P(LLR_max_simulated ≥ LLR_obs) = rank / n_sim.
"""
function temporal_scan(x::AbstractVector{<:Real};
                        max_window::Int=div(length(x), 2),
                        n_sim::Int=199,
                        rng=Random.default_rng())
    T    = length(x)
    n    = sum(x)
    max_window = clamp(max_window, 1, T-1)

    # LLR for Poisson null
    function llr(c, μ, n_total)
        c == 0 && return 0.0
        μ_out = n_total - μ
        c_out = n_total - c
        c_out <= 0 && return 0.0
        # Guard against c/μ ≤ 1 (no excess) — only interested in elevated windows
        c/μ <= 1.0 && return 0.0
        val = c*log(c/μ) + c_out*log(max(c_out/μ_out, 1e-300))
        max(val, 0.0)
    end

    # Scan all windows
    function scan_series(y)
        best_llr = 0.0; best_t1 = 1; best_t2 = 1
        y_total = sum(y)
        y_total == 0 && return (best_llr, best_t1, best_t2)
        for t1 in 1:T
            c = 0.0
            for t2 in t1:min(t1+max_window-1, T)
                c += y[t2]
                w  = t2 - t1 + 1
                μ  = y_total * w / T
                l  = llr(c, μ, y_total)
                if l > best_llr
                    best_llr = l; best_t1 = t1; best_t2 = t2
                end
            end
        end
        (best_llr, best_t1, best_t2)
    end

    λ_obs, t1_obs, t2_obs = scan_series(x)
    c_obs = sum(x[t1_obs:t2_obs])
    μ_obs = n * (t2_obs - t1_obs + 1) / T
    rr    = μ_obs > 0 ? (c_obs/μ_obs) / max((n-c_obs)/max(n-μ_obs,1e-9), 1e-9) : 1.0

    # Monte Carlo
    exceed = 0
    λ_mean = n / T
    for _ in 1:n_sim
        y_sim = Float64.([rand(rng, Poisson(max(λ_mean, 0.0))) for _ in 1:T])
        λ_sim, _, _ = scan_series(y_sim)
        λ_sim >= λ_obs && (exceed += 1)
    end
    p_val = (exceed + 1) / (n_sim + 1)

    TemporalScanResult(λ_obs, p_val, t1_obs, t2_obs,
                       Int(round(c_obs)), μ_obs, rr, n_sim, p_val < 0.05)
end


"""
    prospective_scan(x; window, n_sim, rng) -> NamedTuple

Space-time prospective scan: restrict the most recent `window` time points
as potential cluster ends (t₂ = T only). Suitable for real-time alerting.
"""
function prospective_scan(x::AbstractVector{<:Real};
                           window::Int=4,
                           n_sim::Int=199,
                           rng=Random.default_rng())
    T = length(x); n = sum(x)
    function prospective_llr(y)
        best_llr = 0.0; best_t1 = T
        y_total = sum(y)
        y_total == 0 && return (0.0, T)
        for t1 in max(1, T-window+1):T
            c = sum(y[t1:T])
            w = T - t1 + 1; μ = y_total * w / T
            c/max(μ,1e-9) <= 1.0 && continue
            l = c*log(c/μ) + (y_total-c)*log(max((y_total-c)/max(y_total-μ,1e-9),1e-300))
            l > best_llr && (best_llr = l; best_t1 = t1)
        end
        (best_llr, best_t1)
    end
    λ_obs, t1_obs = prospective_llr(x)
    exceed = 0; λ_mean = n/T
    for _ in 1:n_sim
        y_sim = Float64.([rand(rng, Poisson(max(λ_mean, 0.0))) for _ in 1:T])
        λ_sim, _ = prospective_llr(y_sim)
        λ_sim >= λ_obs && (exceed += 1)
    end
    p_val = (exceed+1)/(n_sim+1)
    (llr=λ_obs, cluster_start=t1_obs, p_value=p_val, significant=p_val<0.05)
end
