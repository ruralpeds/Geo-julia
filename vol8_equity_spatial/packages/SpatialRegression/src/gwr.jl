# gwr.jl — Geographically Weighted Regression
# Chapter 49 — Open-Source Healthcare GIS Textbook in Julia
#
# Fotheringham, Brunsdon & Charlton (1996, 2002)
# Local regression: β_i = (X'W_i X)⁻¹X'W_i y
# where W_i = diag(K(d(u_i, u_j)/b)) for kernel K and bandwidth b

# ── Kernel functions ──────────────────────────────────────────────────────────

"""
    gaussian_kernel(d, b) -> Float64

Gaussian spatial kernel: K(d,b) = exp(-d²/(2b²))
"""
gaussian_kernel(d::Real, b::Real) = exp(-d^2 / (2b^2))

"""
    bisquare_kernel(d, b) -> Float64

Bisquare (tricube-squared) kernel: K(d,b) = (1-(d/b)²)² for d < b, else 0.
Has compact support (zero outside bandwidth).
"""
function bisquare_kernel(d::Real, b::Real)
    d >= b && return 0.0
    u = d / b
    (1 - u^2)^2
end

"""
    epanechnikov_kernel(d, b) -> Float64

Epanechnikov kernel: K(d,b) = (3/4)(1-(d/b)²) for d < b, else 0.
"""
function epanechnikov_kernel(d::Real, b::Real)
    d >= b && return 0.0
    u = d / b
    0.75 * (1 - u^2)
end

const KERNELS = Dict(
    :gaussian     => gaussian_kernel,
    :bisquare     => bisquare_kernel,
    :epanechnikov => epanechnikov_kernel,
)

# ── Distance matrix ───────────────────────────────────────────────────────────

"""
    haversine_dist_km(lat1, lon1, lat2, lon2) -> Float64

Great-circle distance in km using the Haversine formula.
"""
function haversine_dist_km(lat1, lon1, lat2, lon2)
    R = 6371.0   # Earth radius in km
    φ1, φ2 = deg2rad(lat1), deg2rad(lat2)
    Δφ = deg2rad(lat2 - lat1)
    Δλ = deg2rad(lon2 - lon1)
    a = sin(Δφ/2)^2 + cos(φ1)*cos(φ2)*sin(Δλ/2)^2
    2R * asin(sqrt(a))
end

"""
    distance_matrix(coords; metric) -> Matrix{Float64}

Compute n×n distance matrix from coordinates (n × 2 matrix of [lat, lon]).
"""
function distance_matrix(coords::AbstractMatrix; metric::Symbol=:euclidean)
    n = size(coords, 1)
    D = zeros(n, n)
    for i in 1:n, j in (i+1):n
        d = if metric == :haversine
            haversine_dist_km(coords[i,1], coords[i,2], coords[j,1], coords[j,2])
        else
            sqrt(sum((coords[i,:] .- coords[j,:]).^2))
        end
        D[i,j] = D[j,i] = d
    end
    D
end

# ── GWR model ─────────────────────────────────────────────────────────────────

"""
    GWRModel

Geographically Weighted Regression result.
Stores local coefficient estimates and associated statistics for each observation.
"""
struct GWRModel
    coords       :: Matrix{Float64}   # n × 2
    bandwidth    :: Float64
    kernel       :: Symbol
    n            :: Int
    p            :: Int               # number of predictors (excl. intercept)
    local_β      :: Matrix{Float64}   # n × (p+1): local coefficients
    local_se     :: Matrix{Float64}   # n × (p+1): local standard errors
    local_t      :: Matrix{Float64}   # n × (p+1): local t-statistics
    local_r2     :: Vector{Float64}   # n: local R²
    residuals    :: Vector{Float64}
    fitted       :: Vector{Float64}
    aic_c        :: Float64
    feature_names :: Vector{String}
end

"""
    gwr_fit(y, X, coords; bandwidth, kernel, feature_names) -> GWRModel

Fit a Geographically Weighted Regression model.
For each observation i, solve: β_i = (X'W_i X)⁻¹X'W_i y
"""
function gwr_fit(
    y            :: AbstractVector{<:Real},
    X            :: AbstractMatrix{<:Real},
    coords       :: AbstractMatrix{<:Real};
    bandwidth    :: Float64  = -1.0,    # -1 = auto-select via AIC-c
    kernel       :: Symbol   = :gaussian,
    feature_names :: Vector{String} = String[],
    metric       :: Symbol   = :euclidean,
)
    n, p = size(X)
    if isempty(feature_names)
        feature_names = ["intercept"; ["x$(i)" for i in 1:p]]
    else
        feature_names = ["intercept"; feature_names]
    end

    # Auto-select bandwidth via AIC-c minimisation
    if bandwidth < 0
        bandwidth = bandwidth_aic(y, X, coords; kernel=kernel, metric=metric)
    end

    # Precompute distance matrix
    D = distance_matrix(coords; metric=metric)
    kern_fn = get(KERNELS, kernel, gaussian_kernel)

    # Add intercept
    X_aug = hcat(ones(n), X)
    k = size(X_aug, 2)

    local_β = zeros(n, k)
    local_se = zeros(n, k)
    local_t  = zeros(n, k)
    local_r2 = zeros(n)
    fitted   = zeros(n)

    for i in 1:n
        # Spatial kernel weights
        w_i = [kern_fn(D[i,j], bandwidth) for j in 1:n]
        W_i = Diagonal(w_i)

        # Local WLS: β_i = (X'W_i X)⁻¹ X'W_i y
        XtW  = X_aug' * W_i
        XtWX = XtW * X_aug + 1e-8I(k)
        XtWy = XtW * y

        try
            β_i = XtWX \ XtWy
            local_β[i, :] = β_i
            fitted[i] = dot(X_aug[i, :], β_i)

            # Residual variance for SEs
            e_i = y .- X_aug * β_i
            σ²_i = sum(w_i .* e_i.^2) / max(sum(w_i) - k, 1.0)
            cov_β = σ²_i .* (XtWX \ I(k))
            se_i = sqrt.(max.(diag(cov_β), 0.0))
            local_se[i, :] = se_i
            local_t[i, :]  = β_i ./ max.(se_i, 1e-12)

            # Local R²
            y_bar = sum(w_i .* y) / max(sum(w_i), 1e-12)
            ss_tot = sum(w_i .* (y .- y_bar).^2)
            ss_res = sum(w_i .* (y .- X_aug * β_i).^2)
            local_r2[i] = ss_tot > 0 ? 1 - ss_res/ss_tot : 0.0
        catch
            local_β[i, :] .= 0.0
        end
    end

    residuals = y .- fitted
    σ² = mean(residuals.^2)

    # AIC-c: Akaike-corrected for GWR bandwidth selection
    # tr(H): hat matrix trace ≈ effective number of parameters
    aic_c = n * log(σ²) + n * (n + k) / (n - k - 2)

    GWRModel(Matrix(coords), bandwidth, kernel, n, p,
             local_β, local_se, local_t, local_r2,
             residuals, fitted, aic_c, feature_names)
end

"""
    bandwidth_aic(y, X, coords; kernel, metric, candidates) -> Float64

Golden-section + coarse grid search for optimal GWR bandwidth via AIC-c.
"""
function bandwidth_aic(
    y      :: AbstractVector,
    X      :: AbstractMatrix,
    coords :: AbstractMatrix;
    kernel :: Symbol = :gaussian,
    metric :: Symbol = :euclidean,
    n_candidates :: Int = 12,
)
    n = size(X, 1)
    D = distance_matrix(coords; metric=metric)
    max_d = maximum(D)
    min_d = max_d / (n * 2)

    # Coarse search over log-spaced bandwidth candidates
    candidates = exp.(range(log(min_d), log(max_d); length=n_candidates))
    kern_fn    = get(KERNELS, kernel, gaussian_kernel)
    X_aug      = hcat(ones(n), X); k = size(X_aug, 2)

    best_b = candidates[1]; best_aic = Inf

    for b in candidates
        fitted = zeros(n)
        trH    = 0.0
        valid  = true

        for i in 1:n
            w_i  = [kern_fn(D[i,j], b) for j in 1:n]
            W_i  = Diagonal(w_i)
            XtW  = X_aug' * W_i
            XtWX = XtW * X_aug + 1e-8I(k)
            XtWy = XtW * y
            try
                β_i = XtWX \ XtWy
                fitted[i] = dot(X_aug[i, :], β_i)
                # Hat matrix diagonal: h_ii = x_i'(X'W_i X)⁻¹ x_i w_ii
                h_ii = dot(X_aug[i, :], (XtWX \ X_aug[i, :]))
                trH += h_ii * w_i[i]
            catch
                valid = false; break
            end
        end

        !valid && continue
        σ² = mean((y .- fitted).^2)
        σ² < 1e-12 && continue
        aic_c = n * log(σ²) + n * (n + trH) / max(n - trH - 2, 1.0)

        if aic_c < best_aic
            best_aic = aic_c
            best_b   = b
        end
    end

    best_b
end

"""
    gwr_predict(model, X_new, coords_new) -> Vector{Float64}

Predict at new locations by interpolating local coefficients using IDW.
"""
function gwr_predict(model::GWRModel, X_new::AbstractMatrix, coords_new::AbstractMatrix)
    n_new = size(X_new, 1)
    ŷ = zeros(n_new)

    for i in 1:n_new
        # Distances from new point to all training locations
        dists = [distance_matrix(vcat(coords_new[i:i,:], model.coords[j:j,:]); metric=:euclidean)[1,2]
                 for j in 1:model.n]
        # IDW weights for coefficient interpolation
        idw_w = 1 ./ max.(dists, 1e-8).^2
        idw_w ./= sum(idw_w)
        # Interpolated local coefficients
        β_interp = model.local_β' * idw_w
        x_i = vcat(1.0, X_new[i, :])
        ŷ[i] = dot(x_i, β_interp)
    end
    ŷ
end

"""
    gwr_summary(model) -> DataFrame

Per-observation summary: fitted values, residuals, local R², and coefficients.
"""
function gwr_summary(model::GWRModel)
    df = DataFrame(
        fitted    = model.fitted,
        residual  = model.residuals,
        local_r2  = model.local_r2,
    )
    for (j, nm) in enumerate(model.feature_names)
        df[!, Symbol("β_"*nm)]  = model.local_β[:, j]
        df[!, Symbol("se_"*nm)] = model.local_se[:, j]
        df[!, Symbol("t_"*nm)]  = model.local_t[:, j]
    end
    df
end

function Base.show(io::IO, m::GWRModel)
    global_rmse = sqrt(mean(m.residuals.^2))
    mean_r2     = mean(m.local_r2)
    println(io, "GWRModel")
    println(io, "  n=$(m.n), p=$(m.p), kernel=$(m.kernel)")
    println(io, "  Bandwidth: $(round(m.bandwidth; digits=4))")
    println(io, "  Global RMSE: $(round(global_rmse; digits=4))")
    println(io, "  Mean local R²: $(round(mean_r2; digits=3))")
    println(io, "  AIC-c: $(round(m.aic_c; digits=2))")
    println(io, "  Coefficient ranges:")
    for (j, nm) in enumerate(m.feature_names)
        lo = minimum(m.local_β[:, j])
        hi = maximum(m.local_β[:, j])
        println(io, "    $nm: [$(round(lo;digits=3)), $(round(hi;digits=3))]")
    end
end
