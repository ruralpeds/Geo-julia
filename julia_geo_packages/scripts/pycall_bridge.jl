#!/usr/bin/env julia
# scripts/pycall_bridge.jl
#
# PyCall bridge: call PySAL (esda, spreg, libpysal) from Julia.
# Enables comparison with Python spatial statistics ecosystem.
#
# Prerequisites:
#   pip install pysal esda libpysal spreg geopandas
#   julia> using Pkg; Pkg.add("PyCall")
#
# Vol 3 — Julia Package Engineering, Chapter 23.2

using PyCall
using DataFrames
using SparseArrays
using LinearAlgebra

# ── PySAL imports (lazy-loaded on first use) ─────────────────────────────────
const _pysal = Ref{Any}(nothing)
const _esda  = Ref{Any}(nothing)
const _spreg = Ref{Any}(nothing)
const _libpysal = Ref{Any}(nothing)
const _np    = Ref{Any}(nothing)

function _init_pysal()
    _pysal[]    !== nothing && return
    try
        _np[]       = pyimport("numpy")
        _libpysal[] = pyimport("libpysal")
        _esda[]     = pyimport("esda")
        _spreg[]    = pyimport("spreg")
        @info "PySAL loaded successfully"
    catch e
        error("PySAL not available. Install with: pip install pysal esda libpysal spreg\nError: $e")
    end
end

# ── to_pysal_w — convert Julia SpatialWeights to PySAL W object ──────────────

"""
    to_pysal_w(sw) -> PyObject

Convert a Julia `SpatialWeights` to a PySAL `libpysal.weights.W` object.

# Arguments
- `sw` : `SpatialWeights` from SpatialStats.jl
"""
function to_pysal_w(sw)::PyObject
    _init_pysal()
    n = sw.n
    W = sw.W

    # Build PySAL W from adjacency dict
    neighbors = Dict{Int, Vector{Int}}()
    weights   = Dict{Int, Vector{Float64}}()

    for i in 1:n
        row = W[i, :]
        nb_idx, nb_vals = SparseArrays.findnz(row)
        neighbors[i-1] = nb_idx .- 1  # PySAL is 0-indexed
        weights[i-1]   = nb_vals
    end

    # Convert to Python dicts
    py_neighbors = pydict(Dict(string(k) => pylist(v) for (k,v) in neighbors))
    py_weights   = pydict(Dict(string(k) => pylist(v) for (k,v) in weights))

    W_pysal = _libpysal[].weights.W(py_neighbors, py_weights)
    W_pysal
end

# ── pysal_moran — Global Moran's I via PySAL ─────────────────────────────────

"""
    pysal_moran(y, sw; permutations=999) -> NamedTuple

Compute Moran's I using PySAL esda.moran.Moran.
Returns (I, p_sim, z_sim, expected_I, method=:pysal).
"""
function pysal_moran(y::AbstractVector{<:Real}, sw;
                      permutations::Int = 999)

    _init_pysal()
    W_py = to_pysal_w(sw)
    y_np = _np[].array(Float64.(y))

    mi = _esda[].moran.Moran(y_np, W_py; permutations=permutations)

    (
        I          = Float64(mi.I),
        p_sim      = Float64(mi.p_sim),
        z_sim      = Float64(mi.z_sim),
        expected_I = Float64(mi.EI),
        method     = :pysal,
    )
end

# ── pysal_lisa — LISA clusters via PySAL ─────────────────────────────────────

"""
    pysal_lisa(y, sw; permutations=999, alpha=0.05) -> DataFrame

Compute LISA using PySAL esda.moran.Moran_Local.
Returns DataFrame with columns: I_local, p_sim, q (quadrant), cluster_type.
"""
function pysal_lisa(y::AbstractVector{<:Real}, sw;
                     permutations :: Int    = 999,
                     alpha        :: Float64 = 0.05)::DataFrame

    _init_pysal()
    W_py = to_pysal_w(sw)
    y_np = _np[].array(Float64.(y))

    ml = _esda[].moran.Moran_Local(y_np, W_py; permutations=permutations)

    I_local = Float64.(collect(ml.Is))
    p_sim   = Float64.(collect(ml.p_sim))
    q       = Int.(collect(ml.q))  # 1=HH, 2=LH, 3=LL, 4=HL in Moran scatter quadrants

    quad_to_type = Dict(1 => :HH, 2 => :LH, 3 => :LL, 4 => :HL)
    cluster_type = [p_sim[i] <= alpha ? get(quad_to_type, q[i], :NS) : :NS for i in eachindex(p_sim)]

    DataFrame(
        I_local      = I_local,
        p_sim        = p_sim,
        quadrant     = q,
        cluster_type = cluster_type,
    )
end

# ── pysal_slm — Spatial Lag Model via PySAL spreg ────────────────────────────

"""
    pysal_slm(y, X, sw; coef_names) -> NamedTuple

Fit Spatial Lag Model using PySAL spreg.GM_Lag (2SLS).

Returns (coefficients, rho, pseudo_r2, aic, method=:pysal).
"""
function pysal_slm(y::AbstractVector{<:Real},
                    X::AbstractMatrix{<:Real},
                    sw;
                    coef_names :: Union{Nothing, Vector{String}} = nothing)

    _init_pysal()
    W_py = to_pysal_w(sw)

    y_np = _np[].array(Float64.(y)).reshape(-1, 1)
    X_np = _np[].array(Float64.(X[:, 2:end]))  # drop intercept (added by spreg)

    model = _spreg[].GM_Lag(y_np, X_np; w=W_py, name_y="y",
                              name_x = coef_names === nothing ? nothing :
                                        pylist(coef_names[2:end]))

    coeffs = Float64.(collect(model.betas))
    rho    = Float64(model.rho)

    (
        coefficients = coeffs,
        rho          = rho,
        pseudo_r2    = Float64(model.pr2),
        method       = :pysal,
    )
end

# ── Comparison utility ────────────────────────────────────────────────────────

"""
    compare_moran(y, sw; permutations=999) -> DataFrame

Compare Moran's I results from Julia SpatialStats.jl and PySAL.
"""
function compare_moran(y::AbstractVector{<:Real}, sw;
                        permutations::Int = 999)::DataFrame

    using SpatialStats: moran

    julia_res = moran(y, sw; permutations=permutations)
    pysal_res = pysal_moran(y, sw; permutations=permutations)

    DataFrame(
        package = ["SpatialStats.jl", "PySAL esda"],
        I       = [julia_res.I,          pysal_res.I],
        p_value = [julia_res.p_value,    pysal_res.p_sim],
        method  = ["permutation",        "permutation"],
    )
end
