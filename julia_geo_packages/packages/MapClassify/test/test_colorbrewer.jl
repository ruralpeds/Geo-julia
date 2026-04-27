using Test
using Colors

@testset "ColorBrewer Palettes" begin
    
    @testset "Sequential Palettes" begin
        seq_palettes = [:Blues, :Greens, :Greys, :Oranges, :Purples, :Reds, 
                        :YlGn, :YlGnBu, :YlOrBr, :YlOrRd]
        
        for pal in seq_palettes
            colors = get_colorbrewer_palette(pal, 5)
            @test length(colors) == 5
            @test all(c -> isa(c, Colorant), colors)
        end
    end
    
    @testset "Diverging Palettes" begin
        div_palettes = [:BrBG, :PiYG, :PRGn, :PuOr, :RdBu, :RdGy, :RdYlBu, :RdYlGn]
        
        for pal in div_palettes
            colors = get_colorbrewer_palette(pal, 7)
            @test length(colors) == 7
            @test all(c -> isa(c, Colorant), colors)
        end
    end
    
    @testset "Qualitative Palettes" begin
        qual_palettes = [:Accent, :Dark2, :Paired, :Pastel1, :Pastel2, :Set1, :Set2, :Set3]
        
        for pal in qual_palettes
            colors = get_colorbrewer_palette(pal, 6)
            @test length(colors) == 6
            @test all(c -> isa(c, Colorant), colors)
        end
    end
    
    @testset "Color Interpolation" begin
        # Request more colors than palette has
        colors = get_colorbrewer_palette(:Blues, 15)
        @test length(colors) == 15
        
        # All should be valid colors
        @test all(c -> isa(c, Colorant), colors)
        
        # Colors should be distinct
        @test length(unique(colors)) > 1
    end
    
    @testset "Exact Palette Size" begin
        colors = get_colorbrewer_palette(:Blues, 9)
        @test length(colors) == 9
    end
    
    @testset "Single Color" begin
        colors = get_colorbrewer_palette(:Blues, 1)
        @test length(colors) == 1
        @test isa(colors[1], Colorant)
    end
    
    @testset "Few Colors from Large Palette" begin
        colors = get_colorbrewer_palette(:Blues, 2)
        @test length(colors) == 2
        @test all(c -> isa(c, Colorant), colors)
    end
    
    @testset "Invalid Palette" begin
        @test_throws ErrorException get_colorbrewer_palette(:NonExistent, 5)
    end
    
    @testset "Color Consistency" begin
        # Same palette and size should always return same colors
        colors1 = get_colorbrewer_palette(:RdYlGn, 5)
        colors2 = get_colorbrewer_palette(:RdYlGn, 5)
        
        @test colors1 == colors2
    end
    
    @testset "List Available Palettes" begin
        palettes = list_colorbrewer_palettes()
        
        @test haskey(palettes, :sequential)
        @test haskey(palettes, :diverging)
        @test haskey(palettes, :qualitative)
        
        @test length(palettes[:sequential]) > 0
        @test length(palettes[:diverging]) > 0
        @test length(palettes[:qualitative]) > 0
    end
end

@testset "Color Properties" begin
    
    @testset "RGB Values in Range" begin
        colors = get_colorbrewer_palette(:Spectral, 10)
        
        for color in colors
            @test 0 <= red(color) <= 1
            @test 0 <= green(color) <= 1
            @test 0 <= blue(color) <= 1
        end
    end
    
    @testset "Color Diversity" begin
        colors = get_colorbrewer_palette(:Set1, 6)
        
        # Colors in a qualitative palette should be visually distinct
        @test length(unique(colors)) >= 4  # At least some diversity
    end
end
