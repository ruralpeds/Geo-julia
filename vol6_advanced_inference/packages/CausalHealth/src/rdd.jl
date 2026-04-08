# rdd.jl — Regression Discontinuity Design
# Chapter 43.4
#
# Sharp RD: treatment D_i = 1(Xᵢ ≥ c)  (e.g., Medicaid income threshold)
# τ_RD = lim_{x↓c} E[Y|X=x] - lim_{x↑c} E[Y|X=x]
#
# Local polynomial regression (order p, bandwidth h):
#   Fit separate polynomial regressions on each side of the cutoff
#   Local linear (p=1) is the default recommendation (Gelman & Imbens 2018)
#
# Bandwidth: Calonico-Cattaneo-Titiunik (CCT 2014) MSE-optimal bandwidth

"""
    RDResult

Result of a regression discontinuity design analysis.
"""
struct RDResult
    τ          ::Float64   # RD treatment effect at cutoff
    se         ::Float64   # robust SE
    t_stat     ::Float64
    p_value    ::Float64
    ci_lo      ::Float64
    ci_hi      ::Float64
    bandwidth  ::Float64   # optimal or user-specified bandwidth
    poly_order ::Int
    n_left     ::Int       # obs below cutoff within bandwidth
    n_right    ::Int       # obs above cutoff within bandwidth
    plot_data  ::DataFrame # running variable grid for plotting
end

"""
    rd_estimate(df; running_col, outcome_col, cutoff, bandwidth, poly_order,
                fuzzy_col) -> RDResult

Local polynomial RD estimation.

# Arguments
- `running_col`  : running variable X (e.g., income-to-poverty ratio)
- `outcome_col`  : outcome Y (access score, hospitalisation rate)
- `cutoff`       : discontinuity threshold c
- `bandwidth`    : window [c-h, c+h]; if nothing, uses CCT-like rule of thumb
- `poly_order`   : local polynomial order (1 = local linear, recommended)
- `fuzzy_col`    : if provided, treatment variable for fuzzy RD (IV approach)

# Reference:
# Imbens & Lemieux (2008) "Regression Discontinuity Designs: A Guide to Practice"
# Journal of Econometrics 142(2), 615-635.
"""
function rd_estimate(df         ::DataFrame;
                     running_col::Symbol,
                     outcome_col::Symbol,
                     cutoff     ::Float64,
                     bandwidth  ::Union{Float64,Nothing} = nothing,
                     poly_order ::Int    = 1,
                     fuzzy_col  ::Union{Symbol,Nothing} = nothing,
                     kernel     ::Symbol = :triangular)

    x = Float64.(df[!, running_col])
    y = Float64.(df[!, outcome_col])
    n = length(x)

    # Normalise running variable (centre at cutoff)
    xc = x .- cutoff
    h  = isnothing(bandwidth) ? rd_bandwidth(xc, y) : bandwidth

    # Select bandwidth window
    mask_l = @. xc >= -h && xc < 0
    mask_r = @. xc >= 0  && xc <= h
    n_l = sum(mask_l); n_r = sum(mask_r)

    (n_l < poly_order + 1 || n_r < poly_order + 1) &&
        return _rd_null_result(h, poly_order, n_l, n_r)

    # Kernel weights
    kernel_fn = kernel == :triangular ? (u -> max(1 - abs(u), 0.0)) :
                kernel == :epanechnikov ? (u -> max(3/4 * (1 - u^2), 0.0)) :
                (u -> 1.0)  # uniform

    w_l = kernel_fn.(abs.(xc[mask_l]) ./ h)
    w_r = kernel_fn.(abs.(xc[mask_r]) ./ h)

    # Local polynomial fit on each side
    τ_r, se_r, _ = _local_poly_fit(xc[mask_r], y[mask_r], w_r, poly_order, :right)
    τ_l, se_l, _ = _local_poly_fit(xc[mask_l], y[mask_l], w_l, poly_order, :left)

    τ    = τ_r - τ_l
    se   = sqrt(se_r^2 + se_l^2)
    t    = τ / max(se, 1e-12)
    p    = 2 * ccdf(Normal(), abs(t))

    # Fuzzy RD (Wald estimator): τ_Y / τ_D
    if !isnothing(fuzzy_col)
        d = Float64.(df[!, fuzzy_col])
        d_r, sd_r, _ = _local_poly_fit(xc[mask_r], d[mask_r], w_r, poly_order, :right)
        d_l, sd_l, _ = _local_poly_fit(xc[mask_l], d[mask_l], w_l, poly_order, :left)
        Δd  = d_r - d_l
        abs(Δd) > 1e-6 && (τ = τ / Δd)  # Wald estimate
    end

    # Plot data: fitted polynomials on grid
    plot_df = rdd_plot_data(xc, y, mask_l, mask_r, w_l, w_r, h, poly_order, cutoff)

    RDResult(τ, se, t, p, τ - 1.96se, τ + 1.96se, h, poly_order, n_l, n_r, plot_df)
end

function _local_poly_fit(x, y, w, p, side)
    # Design matrix: [1, x, x², ..., xᵖ]
    X = hcat([x.^k for k in 0:p]...)
    W = Diagonal(w)
    β = (X'WX + 1e-10I) \ (X'Wy)
    ê = y .- X * β
    σ² = sum(w .* ê.^2) / max(length(y) - p - 1, 1)
    V  = σ² * inv(X'WX + 1e-10I)
    intercept = β[1]
    se_intercept = sqrt(max(V[1,1], 0.0))
    (intercept, se_intercept, β)
end

"""
    rd_bandwidth(xc, y) -> Float64

CCT-like MSE-optimal bandwidth (rule of thumb).
h* ≈ σ_y / σ_x * n^{-1/5} * 2.702  (plug-in estimate)
"""
function rd_bandwidth(xc::Vector{Float64}, y::Vector{Float64})::Float64
    n  = length(y)
    σy = std(y)
    σx = std(xc)
    h  = 2.702 * σy / max(σx, 1e-9) * n^(-1/5)
    max(h, 0.01 * (maximum(xc) - minimum(xc)))
end

function _rd_null_result(h, p, nl, nr)
    RDResult(NaN, NaN, NaN, NaN, NaN, NaN, h, p, nl, nr, DataFrame())
end

"""
    rdd_plot_data(xc, y, mask_l, mask_r, w_l, w_r, h, p, cutoff) -> DataFrame

Generate fitted curve data for RD visualisation.
"""
function rdd_plot_data(xc, y, mask_l, mask_r, w_l, w_r, h, p, cutoff)
    grid_l = range(-h, 0; length=50)
    grid_r = range(0, h;  length=50)

    # Fit on each side
    _, _, β_l = _local_poly_fit(xc[mask_l], y[mask_l], w_l, p, :left)
    _, _, β_r = _local_poly_fit(xc[mask_r], y[mask_r], w_r, p, :right)

    pred_l = [sum(β_l[k+1] * g^k for k in 0:p) for g in grid_l]
    pred_r = [sum(β_r[k+1] * g^k for k in 0:p) for g in grid_r]

    DataFrame(
        running_var = vcat(collect(grid_l) .+ cutoff, collect(grid_r) .+ cutoff),
        fitted      = vcat(pred_l, pred_r),
        side        = vcat(fill("left", 50), fill("right", 50)),
    )
end

using LinearAlgebra: Diagonal, I
using Distributions: Normal, ccdf
