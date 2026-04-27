"""
    ColorBrewer color palettes for choropleth classification.

References: colorbrewer2.org (Cynthia Brewer)
Licensed under Apache 2.0 License
"""

# Sequential palettes (single hue)
const SEQUENTIAL_PALETTES = Dict(
    :Blues => [
        "#f7fbff", "#deebf7", "#c6dbef", "#9ecae1", "#6baed6",
        "#4292c6", "#2171b5", "#08519c", "#08306b"
    ],
    :Greens => [
        "#f7fcf5", "#e5f5e0", "#c7e9c0", "#a1d99b", "#74c476",
        "#41ab5d", "#238b45", "#006d2c", "#00441b"
    ],
    :Greys => [
        "#ffffff", "#f0f0f0", "#d9d9d9", "#bdbdbd", "#969696",
        "#737373", "#525252", "#252525", "#000000"
    ],
    :Oranges => [
        "#fff5eb", "#fee6ce", "#fdd0a2", "#fdae6b", "#fd8d3c",
        "#f16913", "#d94801", "#a63603", "#7f2704"
    ],
    :Purples => [
        "#fcfbfd", "#efedf5", "#dadaeb", "#bcbddc", "#9e9ac8",
        "#756bb1", "#54278f", "#3f007d", "#240026"
    ],
    :Reds => [
        "#fff5f0", "#fee0d2", "#fcbba1", "#fc9272", "#fb6a4a",
        "#ef3b2c", "#cb181d", "#a50f15", "#67000d"
    ],
    :YlGn => [
        "#ffffe5", "#f7fcb9", "#d9f0a3", "#addd8e", "#78c679",
        "#41ab5d", "#238b45", "#006837", "#004529"
    ],
    :YlGnBu => [
        "#ffffd9", "#edf8b1", "#c7e9b4", "#7fcdbb", "#41b6c4",
        "#1d91c0", "#225ea8", "#253494", "#081d58"
    ],
    :YlOrBr => [
        "#ffffe5", "#fff7bc", "#fee391", "#fec44f", "#fe9929",
        "#ec7014", "#cc4c02", "#8c2d04", "#332b0c"
    ],
    :YlOrRd => [
        "#ffffcc", "#ffeda0", "#fed976", "#feb24c", "#fd8d3c",
        "#f03b20", "#e31a1c", "#bd0026", "#800026"
    ]
)

# Diverging palettes (two hues)
const DIVERGING_PALETTES = Dict(
    :BrBG => [
        "#d8b365", "#f5f5f5", "#5ab4ac"
    ],
    :PiYG => [
        "#e9a3c9", "#f7f7f7", "#a1d76a"
    ],
    :PRGn => [
        "#af8dc3", "#f7f7f7", "#7fbf7b"
    ],
    :PuOr => [
        "#f1a340", "#f7f7f7", "#998ec3"
    ],
    :RdBu => [
        "#ca0020", "#f7f7f7", "#0571b0"
    ],
    :RdGy => [
        "#ca0020", "#ffffff", "#404040"
    ],
    :RdYlBu => [
        "#d73027", "#ffffbf", "#1a9850"
    ],
    :RdYlGn => [
        "#d73027", "#ffffbf", "#1a9850"
    ],
    :Spectral => [
        "#d7191c", "#fdae61", "#ffffbf", "#a6d96a", "#1a9641"
    ]
)

# Qualitative palettes (multiple hues)
const QUALITATIVE_PALETTES = Dict(
    :Accent => [
        "#7fc97f", "#beaed4", "#fdc086", "#ffff99", "#386cb0", "#f0027f"
    ],
    :Dark2 => [
        "#1b9e77", "#d95f02", "#7570b3", "#e7298a", "#66a61e", "#e6ab02"
    ],
    :Paired => [
        "#a6cee3", "#1f78b4", "#b2df8a", "#33a02c", "#fb9a99", "#e31a1c"
    ],
    :Pastel1 => [
        "#fbb4ae", "#b3cde3", "#ccebc5", "#decbe4", "#fed9a6", "#ffffcc"
    ],
    :Pastel2 => [
        "#b3e2cd", "#fdcdac", "#f4cae4", "#e2f0d9", "#edf8f9", "#f1e2cc"
    ],
    :Set1 => [
        "#e41a1c", "#377eb8", "#4daf4a", "#984ea3", "#ff7f00", "#999999"
    ],
    :Set2 => [
        "#66c2a5", "#fc8d62", "#8da0cb", "#e78ac3", "#a6d854", "#ffd92f"
    ],
    :Set3 => [
        "#8dd3c7", "#ffffb3", "#bebada", "#fb8072", "#80b1d3", "#fdb462"
    ]
)

"""
    get_colorbrewer_palette(palette::Symbol, n::Int=3) -> Vector{RGB}

Get a ColorBrewer palette and return RGB colors.
Automatically interpolates if requested number of colors doesn't match standard sizes.

# Arguments
- `palette::Symbol`: Palette name (e.g., :Blues, :RdYlGn, :Set1)
- `n::Int`: Number of colors (default: 3)

# Returns
- `Vector{RGB}`: RGB color objects
"""
function get_colorbrewer_palette(palette::Symbol, n::Int=3)
    if n < 1
        error("n must be >= 1")
    end
    
    # Check palette type
    colors_hex = nothing
    
    if haskey(SEQUENTIAL_PALETTES, palette)
        colors_hex = SEQUENTIAL_PALETTES[palette]
    elseif haskey(DIVERGING_PALETTES, palette)
        colors_hex = DIVERGING_PALETTES[palette]
    elseif haskey(QUALITATIVE_PALETTES, palette)
        colors_hex = QUALITATIVE_PALETTES[palette]
    else
        error("Unknown palette: $palette. Available: $(vcat(keys(SEQUENTIAL_PALETTES)..., keys(DIVERGING_PALETTES)..., keys(QUALITATIVE_PALETTES)...))")
    end
    
    # Convert hex to RGB
    rgb_colors = [parse(Colorant, hex) for hex in colors_hex]
    
    # Interpolate if needed
    if n == length(rgb_colors)
        return rgb_colors
    elseif n == 1
        # Single color: return middle color
        return rgb_colors[div(length(rgb_colors), 2):div(length(rgb_colors), 2)]
    elseif n < length(rgb_colors)
        # Sample from palette
        indices = round.(Int, range(1, length(rgb_colors), length=n))
        return rgb_colors[indices]
    else
        # Interpolate
        return _interpolate_colors(rgb_colors, n)
    end
end

"""
    _interpolate_colors(colors::Vector, n::Int) -> Vector{RGB}

Interpolate between colors in a palette.
"""
function _interpolate_colors(colors::Vector, n::Int)
    if n <= 1
        return colors[1:1]
    end
    
    interpolated = Vector{RGB}(undef, n)
    
    for i in 1:n
        # Position in palette (0 to 1)
        t = (i - 1) / (n - 1)
        
        # Find which pair of colors to interpolate between
        color_pos = t * (length(colors) - 1) + 1
        lower_idx = floor(Int, color_pos)
        upper_idx = ceil(Int, color_pos)
        
        if lower_idx == upper_idx
            interpolated[i] = colors[lower_idx]
        else
            # Linear interpolation between colors
            alpha = color_pos - lower_idx
            c1 = colors[lower_idx]
            c2 = colors[upper_idx]
            
            r = (1 - alpha) * red(c1) + alpha * red(c2)
            g = (1 - alpha) * green(c1) + alpha * green(c2)
            b = (1 - alpha) * blue(c1) + alpha * blue(c2)
            
            interpolated[i] = RGB(r, g, b)
        end
    end
    
    interpolated
end

"""
    list_colorbrewer_palettes() -> Dict

List all available ColorBrewer palettes by category.
"""
function list_colorbrewer_palettes()
    Dict(
        :sequential => collect(keys(SEQUENTIAL_PALETTES)),
        :diverging => collect(keys(DIVERGING_PALETTES)),
        :qualitative => collect(keys(QUALITATIVE_PALETTES))
    )
end
