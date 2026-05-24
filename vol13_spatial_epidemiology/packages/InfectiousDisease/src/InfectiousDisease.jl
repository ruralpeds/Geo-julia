"""
    InfectiousDisease

Compartmental and spatial epidemic models for the Geo-Julia healthcare textbook.

Models:
- **SIR** — deterministic (Euler + RK4) and stochastic (τ-leaping)
- **SEIR** — adds latent/exposed compartment (RK4)
- **Spatial SIR** — multi-patch gravity coupling; county-level spread

Estimation:
- R₀ from early growth rate (Wallinga & Lipsitch 2007)
- R₀ from final attack rate (Ma & Earn 2006)
- R₀ from model parameters
- Herd immunity threshold 1 - 1/R₀
- Final attack rate prediction (implicit equation)
- Serial interval bootstrap CI
- Epidemic doubling time
"""
module InfectiousDisease

using Statistics, LinearAlgebra, Random
using OrdinaryDiffEq
using Distributions: Poisson

include("compartmental.jl")
include("spatial_sir.jl")
include("estimation.jl")
include("report.jl")

export
    # SIR
    SIRResult, sir, sir_stochastic,
    # SEIR
    SEIRResult, seir,
    # Spatial SIR
    SpatialSIRResult, spatial_sir,
    # Estimation
    r0_from_growth,
    r0_from_sir,
    r0_from_params,
    herd_immunity_threshold,
    effective_r0,
    estimate_serial_interval,
    attack_rate_prediction,
    doubling_time,
    # Report
    print_sir_report,
    print_spatial_sir_report

end # module
