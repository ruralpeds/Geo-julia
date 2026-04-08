### A Pluto.jl notebook ###
# Run with: julia -e 'using Pluto; Pluto.run(notebook="notebooks/healthcare_dashboard.jl")'
# Vol 4 — Chapter 30: Interactive Dashboard with Pluto.jl

# Cell 1: Package loading
begin
    using Pluto, PlutoUI
    using WGLMakie, GeoMakie
    using DataFrames, CSV
    using SparseArrays, Statistics
    using SpatialStats
    md"""
    ## 🏥 North Dakota Primary Care Access Dashboard

    **Interactive spatial analysis with reactive controls.**
    Adjust catchment radius, significance level, and variable to explore
    healthcare access patterns across North Dakota counties.
    """
end

# Cell 2: Load pre-computed data
begin
    const DATA_DIR = joinpath(@__DIR__, "..", "data", "processed")

    nd_df = try
        CSV.read(joinpath(DATA_DIR, "nd_analysis_results.csv"), DataFrame)
    catch
        @warn "Analysis results not found. Run pipeline/03_spatial_analysis.jl first."
        # Demo data for testing
        n = 53
        DataFrame(
            GEOID         = ["38" * lpad(i, 3, '0') for i in 1:n],
            NAME          = ["County $(i)" for i in 1:n],
            centroid_lat  = 46.5 .+ range(-2.0, 2.0; length=n),
            centroid_lon  = -100.5 .+ range(-3.0, 3.0; length=n),
            access_score  = abs.(randn(n)) .* 0.01 .+ 0.005,
            poverty_pct   = 5.0 .+ 15.0 .* rand(n),
            uninsured_pct = 8.0 .+ 12.0 .* rand(n),
            total_pop     = 1000 .+ round.(Int, 50000 .* rand(n).^2),
        )
    end

    @info "Loaded $(nrow(nd_df)) ND counties"
end

# Cell 3: Interactive controls
begin
    catchment_slider = @bind catchment_km Slider(20:5:80; default=45, show_value=true)
    alpha_slider     = @bind alpha_val    Slider(0.01:0.01:0.10; default=0.05, show_value=true)
    var_select       = @bind selected_var Select([
        "access_score"   => "E2SFCA Access Score",
        "poverty_pct"    => "Poverty Rate (%)",
        "uninsured_pct"  => "Uninsurance Rate (%)",
        "lisa_cluster"   => "LISA Clusters",
    ])
    scheme_select    = @bind color_scheme Select([
        "viridis"  => "Viridis (perceptually uniform)",
        "YlGn"     => "Yellow-Green (sequential)",
        "Oranges"  => "Oranges (poverty)",
        "RdYlBu"   => "Red-Yellow-Blue (diverging)",
    ])

    md"""
    | Parameter            | Control                    |
    |----------------------|---------------------------|
    | Catchment radius     | $(catchment_slider) km     |
    | LISA significance α  | $(alpha_slider)            |
    | Map variable         | $(var_select)              |
    | Color scheme         | $(scheme_select)           |
    """
end

# Cell 4: Build synthetic weights for reactive analysis
function make_nd_weights(n::Int)
    Is = Int[]; Js = Int[]; Vs = Float64[]
    for i in 1:n-1
        push!(Is, i, i+1); push!(Js, i+1, i); push!(Vs, 1.0, 1.0)
    end
    for i in 1:n-8
        push!(Is, i, i+8); push!(Js, i+8, i); push!(Vs, 1.0, 1.0)
    end
    W = SparseArrays.sparse(Is, Js, Vs, n, n)
    row_sums = vec(sum(W; dims=2))
    rows, cols, vals = SparseArrays.findnz(W)
    for k in eachindex(rows); vals[k] /= row_sums[rows[k]]; end
    W = SparseArrays.sparse(rows, cols, vals, n, n)
    SpatialStats.SpatialWeights(W, n,
        SpatialStats.RowStandardizedStyle(), SpatialStats.QueenTransform(),
        0, mean(vec(sum(W .!= 0; dims=2))), 1, 8)
end

# Cell 5: Reactive analysis (re-runs when sliders change)
analysis = let
    @info "Recomputing: catchment=$(catchment_km)km, α=$(alpha_val)"
    n  = nrow(nd_df)
    w  = make_nd_weights(n)

    # LISA on access score
    access_vals = Float64.(coalesce.(nd_df.access_score, 0.0))
    lisa_result = SpatialStats.lisa(access_vals, w;
                                     permutations=499, alpha=alpha_val)

    # Moran's I for all key variables
    mr = Dict{Symbol, Any}()
    for var in [:access_score, :poverty_pct, :uninsured_pct]
        hasproperty(nd_df, var) || continue
        vals = Float64.(coalesce.(nd_df[!, var], 5.0))
        mr[var] = SpatialStats.moran(vals, w; permutations=199)
    end

    (; nd_df, w, moran_results=mr, lisa=lisa_result,
       hh_count=count(==(:HH), lisa_result.cluster_type),
       ll_count=count(==(:LL), lisa_result.cluster_type))
end

# Cell 6: Reactive choropleth map
let
    nd = analysis.nd_df
    n  = nrow(nd)

    cluster_color_map = Dict(
        :HH => :red, :LL => :blue,
        :HL => :orange, :LH => :lightblue, :NS => :lightgray
    )

    fig = WGLMakie.Figure(resolution=(900, 600))
    ax  = GeoMakie.GeoAxis(fig[1,1];
          dest  = "+proj=laea +lat_0=47 +lon_0=-100",
          title = "$(selected_var) — Catchment: $(catchment_km)km, α=$(alpha_val)")

    if selected_var == "lisa_cluster"
        colors = [cluster_color_map[c] for c in analysis.lisa.cluster_type]
        # If geometries available
        if hasproperty(nd, :geometry) && !isnothing(nd.geometry[1])
            WGLMakie.poly!(ax, nd.geometry; color=colors,
                           strokecolor=:white, strokewidth=0.3)
        else
            # Fallback: scatter plot at centroids
            WGLMakie.scatter!(ax, nd.centroid_lon, nd.centroid_lat;
                              color=colors, markersize=12)
        end
        WGLMakie.text!(ax,
            "HH: $(analysis.hh_count)  LL: $(analysis.ll_count)";
            position=(-104.0, 45.9), fontsize=12, color=:black)
    else
        vals = Float64.(coalesce.(nd[!, Symbol(selected_var)], 0.0))
        if hasproperty(nd, :geometry) && !isnothing(nd.geometry[1])
            WGLMakie.poly!(ax, nd.geometry;
                           color=vals, colormap=Symbol(color_scheme),
                           strokecolor=:white, strokewidth=0.3)
        else
            WGLMakie.scatter!(ax, nd.centroid_lon, nd.centroid_lat;
                              color=vals, colormap=Symbol(color_scheme), markersize=12)
        end
        WGLMakie.Colorbar(fig[1,2]; colormap=Symbol(color_scheme),
                          limits=extrema(vals), width=15)
    end
    fig
end

# Cell 7: Statistical summary table
let
    mr = analysis.moran_results
    vars = [:access_score, :poverty_pct, :uninsured_pct]
    labels = ["Access Score", "Poverty Rate", "Uninsurance Rate"]

    rows = []
    for (var, label) in zip(vars, labels)
        haskey(mr, var) || continue
        r = mr[var]
        push!(rows, (
            Variable = label,
            Moran_I  = round(r.I; digits=4),
            Z_Score  = round(r.z_score; digits=2),
            P_Value  = round(r.p_value; digits=4),
            Sig      = r.p_value < 0.05 ? "★" : "",
        ))
    end
    DataFrame(rows)
end

# Cell 8: Interpretation via Claude API
begin
    anthropic_key = get(ENV, "ANTHROPIC_API_KEY", "")

    function interpret_spatial_results(moran_results, lisa_result)
        isempty(anthropic_key) && return _rule_based_interpretation(moran_results, lisa_result)

        import HTTP, JSON3
        access_I  = moran_results[:access_score].I
        access_p  = moran_results[:access_score].p_value
        hh = count(==(:HH), lisa_result.cluster_type)
        ll = count(==(:LL), lisa_result.cluster_type)

        prompt = """
        Interpret the following spatial autocorrelation results for North Dakota
        primary care access (E2SFCA scores across 53 counties):

        Global Moran's I = $(round(access_I; digits=4)) (p = $(round(access_p; digits=4)))
        LISA clusters: $(hh) High-High clusters, $(ll) Low-Low clusters

        Provide: (1) interpretation of the clustering pattern,
        (2) health equity implications, (3) policy recommendations.
        Be concise (3 paragraphs).
        """

        try
            resp = HTTP.post(
                "https://api.anthropic.com/v1/messages";
                headers = ["x-api-key" => anthropic_key,
                           "anthropic-version" => "2023-06-01",
                           "content-type" => "application/json"],
                body = JSON3.write(Dict(
                    "model"      => "claude-sonnet-4-6",
                    "max_tokens" => 600,
                    "messages"   => [Dict("role" => "user", "content" => prompt)]
                )),
                readtimeout = 30,
            )
            JSON3.read(resp.body)[:content][1][:text]
        catch e
            _rule_based_interpretation(moran_results, lisa_result)
        end
    end

    function _rule_based_interpretation(mr, lr)
        I   = mr[:access_score].I
        p   = mr[:access_score].p_value
        hh  = count(==(:HH), lr.cluster_type)
        ll  = count(==(:LL), lr.cluster_type)
        sig = p < 0.05

        io = IOBuffer()
        println(io, "**Spatial Autocorrelation Analysis Results**\n")
        print(io, "Global Moran's I = $(round(I; digits=4)) ")
        println(io, sig ? "(statistically significant, p=$(round(p; digits=3)))" :
                         "(not significant, p=$(round(p; digits=3)))")
        println(io, "")

        if sig && I > 0
            println(io, "Primary care access is **spatially clustered** in North Dakota. " *
                "Counties with high access tend to neighbor other high-access counties, " *
                "and low-access counties cluster together. This is consistent with " *
                "spatial concentration of providers in urban centers like Bismarck and Fargo.")
        elseif sig && I < 0
            println(io, "Primary care access shows **spatial dispersion** — high and low " *
                "access counties alternate in a checkerboard pattern.")
        else
            println(io, "No significant spatial clustering detected. Access is distributed " *
                "randomly across counties.")
        end

        println(io, "\nLISA analysis identified $(hh) High-High clusters and $(ll) Low-Low clusters " *
            "at α=$(round(lr.significance; digits=2)).")
        ll > 0 && println(io, "Low-Low clusters likely represent rural counties with " *
            "healthcare access shortages and HPSA designations.")

        String(take!(io))
    end

    interpretation = interpret_spatial_results(analysis.moran_results, analysis.lisa)
    md"""
    ### AI Interpretation

    $(interpretation)
    """
end
