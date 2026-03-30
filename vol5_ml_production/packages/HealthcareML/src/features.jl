# features.jl — Feature engineering for healthcare access prediction
# Chapter 35.1

"""
    AccessFeatures

Configuration for healthcare access feature construction.

Fields:
- `spatial_lags::Int` — number of spatial lag orders (0 = no spatial features)
- `interaction_terms::Bool` — include pairwise interaction features
- `polynomial_degree::Int` — polynomial expansion degree (1 = linear only)
- `standardize::Bool` — z-score standardize numeric features
"""
struct AccessFeatures
    spatial_lags    ::Int
    interaction_terms::Bool
    polynomial_degree::Int
    standardize     ::Bool
    function AccessFeatures(; spatial_lags=1, interaction_terms=true,
                              polynomial_degree=2, standardize=true)
        new(spatial_lags, interaction_terms, polynomial_degree, standardize)
    end
end

"""
    build_features(df, target_col; feature_cols, config, W_sparse) -> (X, y, feature_names)

Build ML feature matrix from a healthcare county DataFrame.

Engineered features include:
1. Raw predictors: poverty rate, uninsurance rate, rurality index, age structure
2. Spatial lag features: W·x for each predictor (if config.spatial_lags > 0)
3. Polynomial features: x², x³ up to config.polynomial_degree
4. Interaction features: xᵢ·xⱼ for key pairs (if config.interaction_terms)
5. Derived features: Gini-like disparity index, provider-to-pop ratio

Returns X (n × p Float64 matrix), y (n-vector), feature_names (p-vector).
"""
function build_features(df::DataFrame, target_col::Symbol;
                        feature_cols::Vector{Symbol} = [:poverty_pct, :uninsured_pct,
                                                         :total_pop, :rurality],
                        config::AccessFeatures = AccessFeatures(),
                        W_sparse = nothing)
    n = nrow(df)
    X_parts = Matrix{Float64}[]
    names   = String[]

    # 1. Raw features
    for col in feature_cols
        if hasproperty(df, col)
            push!(X_parts, reshape(Float64.(df[!, col]), n, 1))
            push!(names, String(col))
        end
    end

    # Derived features
    if hasproperty(df, :total_pop) && hasproperty(df, :poverty_pct)
        pop_density_proxy = log1p.(Float64.(df.total_pop) ./ 1000)
        push!(X_parts, reshape(pop_density_proxy, n, 1))
        push!(names, "log_pop_k")
    end

    if hasproperty(df, :poverty_pct) && hasproperty(df, :uninsured_pct)
        disparity = Float64.(df.poverty_pct) .* Float64.(df.uninsured_pct) ./ 100
        push!(X_parts, reshape(disparity, n, 1))
        push!(names, "poverty_x_uninsured")
    end

    X_base = isempty(X_parts) ? zeros(n, 0) : hcat(X_parts...)
    p_base = size(X_base, 2)

    # 2. Polynomial features
    if config.polynomial_degree >= 2
        poly_parts = Matrix{Float64}[]
        for deg in 2:config.polynomial_degree
            Xpow = X_base .^ deg
            push!(poly_parts, Xpow)
            for i in 1:p_base
                push!(names, "$(names[i])_pow$(deg)")
            end
        end
        !isempty(poly_parts) && (X_base = hcat(X_base, poly_parts...))
    end

    # 3. Interaction features
    if config.interaction_terms && p_base >= 2
        for i in 1:p_base-1, j in i+1:p_base
            inter = X_base[:, i] .* X_base[:, j]
            X_base = hcat(X_base, inter)
            push!(names, "$(names[i])x$(names[j])")
        end
    end

    # 4. Spatial lag features
    if config.spatial_lags > 0 && !isnothing(W_sparse)
        W_mat = Matrix(W_sparse)
        for lag in 1:config.spatial_lags
            if lag == 1
                Wl = W_mat
            else
                Wl = W_mat^lag
            end
            for j in 1:p_base
                lag_feat = Wl * X_base[:, j]
                X_base = hcat(X_base, lag_feat)
                push!(names, "W$(lag)_$(names[j])")
            end
        end
    end

    # 5. Standardize
    μ_vec = zeros(size(X_base, 2))
    σ_vec = ones(size(X_base, 2))
    if config.standardize
        for j in 1:size(X_base, 2)
            μ_vec[j] = mean(X_base[:, j])
            σ_vec[j] = max(std(X_base[:, j]), 1e-9)
            X_base[:, j] .= (X_base[:, j] .- μ_vec[j]) ./ σ_vec[j]
        end
    end

    y = Float64.(df[!, target_col])
    (X=X_base, y=y, feature_names=names, μ=μ_vec, σ=σ_vec)
end
