"""
runtests.jl

Test suite for Raster.jl package (Days 14-15).

Phase C (Days 14): Kriging → Raster Integration
- Grid creation (regular lat/lon grids)
- Ordinary kriging on grid
- Universal kriging with drift
- Block kriging for area-level predictions
- Co-kriging with auxiliary variables
- Uncertainty quantification
- Value extraction and resampling

Phase D (Days 15): Population Fusion & Validation
- Grid alignment and coordinate handling
- Source weight estimation
- Bayesian population fusion
- Cross-validation metrics
- Inter-source agreement
- Fusion quality assessment
"""

using Test
using Raster

@testset "Raster.jl" begin
    # Phase C: Kriging integration
    if isfile(joinpath(@__DIR__, "test_kriging_grid.jl"))
        include("test_kriging_grid.jl")
    end

    # Phase IV-V: Spatial indexing optimization (Days 56-57)
    if isfile(joinpath(@__DIR__, "test_kdtree_2sfca.jl"))
        include("test_kdtree_2sfca.jl")
    end

    # Phase D: Population fusion
    if isfile(joinpath(@__DIR__, "test_fusion.jl"))
        include("test_fusion.jl")
    end
    if isfile(joinpath(@__DIR__, "test_validation.jl"))
        include("test_validation.jl")
    end
end
