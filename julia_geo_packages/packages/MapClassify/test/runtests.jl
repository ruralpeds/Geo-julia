using Test

# Include the module first
include("../src/MapClassify.jl")
using .MapClassify

@testset "MapClassify.jl" begin
    include("test_methods.jl")
    include("test_colorbrewer.jl")
    include("test_metrics.jl")
end
