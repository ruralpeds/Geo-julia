"""
    PointPatterns.jl

Spatial point pattern analysis for Julia.
Fills the ecosystem gap: no spatstat equivalent exists in Julia.

Implements:
- PointPattern and ObservationWindow types
- Complete Spatial Randomness (CSR) tests: quadrat, Clark-Evans
- Ripley's K-function, L-function, G/F/J functions
- Monte Carlo CSR envelopes
- Kernel intensity estimation
- Nearest neighbour statistics
- Kulldorff spatial scan statistic for disease cluster detection

Vol 4 — Advanced Methods, Real Data, and Deployment, Chapter 26
"""
module PointPatterns

using Statistics
using LinearAlgebra
using Random
using DataFrames
using Distributions
using NearestNeighbors

# ── Type exports ─────────────────────────────────────────────────────────────
export PointPattern, ObservationWindow, RectWindow, PolyWindow

# ── CSR Tests ────────────────────────────────────────────────────────────────
export quadrat_test, clarkevans_test

# ── Summary statistics ────────────────────────────────────────────────────────
export Kfunction, Lfunction, Gfunction, Ffunction, Jfunction
export envelope

# ── Intensity estimation ──────────────────────────────────────────────────────
export kernel_intensity, adaptive_intensity, intensity

# ── Nearest neighbour ─────────────────────────────────────────────────────────
export nndist, nnwhich, pairdist

# ── Cluster detection ─────────────────────────────────────────────────────────
export scan_statistic

include("types.jl")
include("csr_tests.jl")
include("kfunction.jl")
include("gfunction.jl")
include("intensity.jl")
include("nearest.jl")
include("scan.jl")

end # module PointPatterns
