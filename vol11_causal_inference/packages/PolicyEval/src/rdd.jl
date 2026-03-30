# rdd.jl — Regression discontinuity design

struct RDDResult
    τ::Float64          # estimated discontinuity at cutoff
    se::Float64
    ci_lower::Float64
    ci_upper::Float64
    bandwidth::Float64
    n_left::Int
    n_right::Int
    cutoff::Float64
    polynomial_order::Int
    slope_left::Float64
    slope_right::Float64
    density_test_p::Float64  # McCrary density continuity test p-value
end

"""
    rdd_fit(y, x; cutoff, bandwidth, poly_order, n_boot, rng) -> RDDResult

Regression discontinuity estimator via local polynomial regression.
Estimates separate polynomial of `poly_order` on each side of `cutoff`
within `bandwidth`. Default bandwidth: Imbens-Kalyanaraman (2012) selector.
"""
function rdd_fit(y::AbstractVector, x::AbstractVector;
                 cutoff::Float64=0.0,
                 bandwidth::Union{Float64,Nothing}=nothing,
                 poly_order::Int=1,
                 n_boot::Int=200,
                 rng=Random.default_rng())
    n    = length(y)
    x_c  = x .- cutoff       # running variable centred at cutoff
    D    = Float64.(x_c .>= 0)  # right of cutoff

    h    = isnothing(bandwidth) ? _ik_bandwidth(y, x_c) : bandwidth

    # Local observations within bandwidth
    idx  = abs.(x_c) .<= h
    y_l  = y[idx .& (D .== 0)]; x_l = x_c[idx .& (D .== 0)]
    y_r  = y[idx .& (D .== 1)]; x_r = x_c[idx .& (D .== 1)]

    # Polynomial basis on left and right
    β_l  = _local_poly(x_l, y_l, poly_order)
    β_r  = _local_poly(x_r, y_r, poly_order)

    τ    = β_r[1] - β_l[1]   # intercept difference = jump at cutoff
    sl_l = length(β_l) > 1 ? β_l[2] : 0.0
    sl_r = length(β_r) > 1 ? β_r[2] : 0.0

    # Bootstrap SE
    idx_arr = findall(idx)
    boot_ests = Vector{Float64}(undef, n_boot)
    for b in 1:n_boot
        boot_idx = rand(rng, idx_arr, length(idx_arr))
        yb = y[boot_idx]; xb = x_c[boot_idx]; Db = D[boot_idx]
        bl = _local_poly(xb[Db .== 0], yb[Db .== 0], poly_order)
        br = _local_poly(xb[Db .== 1], yb[Db .== 1], poly_order)
        boot_ests[b] = isempty(br) || isempty(bl) ? τ : br[1] - bl[1]
    end
    se = std(boot_ests)

    mc_p = mccrary_test(x; cutoff=cutoff).p_value

    RDDResult(τ, se, τ-1.96se, τ+1.96se, h,
              length(y_l), length(y_r), cutoff, poly_order,
              sl_l, sl_r, mc_p)
end

function _local_poly(x::AbstractVector, y::AbstractVector, p::Int)
    isempty(x) && return zeros(p + 1)
    n = length(x)
    X = hcat([x.^k for k in 0:p]...)
    (X'X + 1e-10*I) \ (X'y)
end

"""
    _ik_bandwidth(y, x_c) -> Float64

Simplified Imbens-Kalyanaraman (2012) MSE-optimal bandwidth.
h* ≈ C_K · (σ² / (B²·n))^{1/5}
where B is estimated second-derivative of regression function at cutoff.
"""
function _ik_bandwidth(y::AbstractVector, x_c::AbstractVector)
    n     = length(y)
    h_rot = 1.84 * std(x_c) * n^(-1/5)  # Silverman-style pilot
    n_h   = sum(abs.(x_c) .<= h_rot)
    n_h   < 6 && return h_rot

    # Pilot regression: cubic on each side for curvature estimation
    idx_l = x_c .< 0 .& abs.(x_c) .<= h_rot
    idx_r = x_c .>= 0 .& abs.(x_c) .<= h_rot
    bl3   = length(y[idx_l]) >= 4 ? _local_poly(x_c[idx_l], y[idx_l], 3) : zeros(4)
    br3   = length(y[idx_r]) >= 4 ? _local_poly(x_c[idx_r], y[idx_r], 3) : zeros(4)

    B2_l  = length(bl3) >= 3 ? 2*bl3[3] : 1.0
    B2_r  = length(br3) >= 3 ? 2*br3[3] : 1.0
    B2    = (B2_l^2 + B2_r^2) / 2.0

    σ²_l  = isempty(y[idx_l]) ? var(y) : var(y[idx_l])
    σ²_r  = isempty(y[idx_r]) ? var(y) : var(y[idx_r])
    σ²    = (σ²_l + σ²_r) / 2.0

    h_opt = (σ² / (B2 * n))^(1/5)
    clamp(h_opt, 0.05*std(x_c), 2.0*std(x_c))
end

"""
    mccrary_test(x; cutoff, n_bins, bw) -> NamedTuple

McCrary (2008) density discontinuity test.
Counts observations in bins on each side; tests for jump at cutoff.
"""
function mccrary_test(x::AbstractVector; cutoff::Float64=0.0,
                      n_bins::Int=20, bw::Union{Float64,Nothing}=nothing)
    xc    = x .- cutoff
    h     = isnothing(bw) ? 2*std(xc)*length(xc)^(-1/5) : bw
    bins  = range(-3h, 3h, length=n_bins+1)
    bins_left  = bins[bins .< 0]
    bins_right = bins[bins .>= 0]

    counts_l = [sum(bins_left[i] .<= xc .< bins_left[i+1])
                for i in 1:length(bins_left)-1]
    counts_r = [sum(bins_right[i] .<= xc .< bins_right[i+1])
                for i in 1:length(bins_right)-1]

    n_l = sum(counts_l); n_r = sum(counts_r)
    n   = n_l + n_r
    # Simple χ² test: expected proportional to side length
    exp_l = n * length(counts_l) / (length(counts_l) + length(counts_r))
    exp_r = n - exp_l
    # Density at boundary: extrapolation via last bin density
    ρ_l = length(counts_l) > 0 ? last(counts_l) / max(n_l, 1) : 0.0
    ρ_r = length(counts_r) > 0 ? first(counts_r) / max(n_r, 1) : 0.0
    # Variance of log density ratio: (1/n_l + 1/n_r)
    se_log = sqrt(1/max(n_l,1) + 1/max(n_r,1))
    z      = log(max(ρ_r,1e-10)/max(ρ_l,1e-10)) / se_log
    p_val  = 2*(1 - _norm_cdf(abs(z)))
    (z=z, p_value=p_val, n_left=n_l, n_right=n_r,
     density_left=ρ_l, density_right=ρ_r)
end

_norm_cdf(x) = 0.5*(1 + erf(x/sqrt(2)))
function erf(x::Float64)
    # Abramowitz & Stegun 7.1.26
    t = 1/(1+0.3275911*abs(x))
    y = 1 - (0.254829592t - 0.284496736t^2 + 1.421413741t^3 -
             1.453152027t^4 + 1.061405429t^5) * exp(-x^2)
    x >= 0 ? y : -y
end

"""
    rdd_summary(result) -> NamedTuple

Return key RDD statistics for display.
"""
function rdd_summary(r::RDDResult)
    (τ=r.τ, se=r.se, ci=(r.ci_lower, r.ci_upper), bandwidth=r.bandwidth,
     n_left=r.n_left, n_right=r.n_right,
     slope_left=r.slope_left, slope_right=r.slope_right,
     density_test_p=r.density_test_p)
end
