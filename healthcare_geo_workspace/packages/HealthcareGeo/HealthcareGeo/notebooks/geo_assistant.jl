### A Pluto.jl notebook ###
# v0.19.46
#
# AI-Powered Geographic Analysis Assistant
# -----------------------------------------
# A reactive Pluto notebook that runs HealthcareGeo.jl spatial analyses and
# interprets results using the Anthropic Claude API.
#
# Usage:
#   julia -e 'using Pluto; Pluto.run(notebook="notebooks/geo_assistant.jl")'

using Markdown
using InteractiveUtils

# ╔═╡ 00000000-0000-0000-0000-000000000001
begin
    using Pkg
    Pkg.activate(joinpath(@__DIR__, ".."))
    using PlutoUI, WGLMakie, GeoMakie
    using DataFrames, Statistics
    using HTTP, JSON
    using HealthcareGeo
    using GeoDataFrames
end

# ╔═╡ 10000000-0000-0000-0000-000000000001
md"""
# 🗺️ Geographic Analysis Assistant

**Powered by HealthcareGeo.jl + Claude AI**

This notebook loads county-level data for a selected U.S. state, runs spatial
analyses (Moran's I, LISA clustering, E2SFCA accessibility), and sends the
numerical results to the Anthropic Claude API for natural-language
interpretation.
"""

# ╔═╡ 20000000-0000-0000-0000-000000000001
md"""
## Configuration

Select a state and set your Anthropic API key.
"""

# ╔═╡ 20000000-0000-0000-0000-000000000002
@bind state_abbr Select(
    ["ND" => "North Dakota",
     "SD" => "South Dakota",
     "MT" => "Montana",
     "WY" => "Wyoming",
     "ID" => "Idaho",
     "NE" => "Nebraska",
     "KS" => "Kansas",
     "MN" => "Minnesota",
     "IA" => "Iowa",
     "WI" => "Wisconsin",
     "ME" => "Maine",
     "VT" => "Vermont",
     "WV" => "West Virginia",
     "MS" => "Mississippi",
     "AR" => "Arkansas"],
    default = "ND"
)

# ╔═╡ 20000000-0000-0000-0000-000000000003
@bind catchment_km Slider(20:5:120; default = 60, show_value = true)

# ╔═╡ 30000000-0000-0000-0000-000000000001
md"""
## Analysis Runner

Downloads county data and runs:
1. Queen-contiguity spatial weights matrix
2. Global Moran's I
3. LISA cluster detection
4. E2SFCA accessibility (synthetic provider data if AHRF not loaded)
"""

# ╔═╡ 30000000-0000-0000-0000-000000000002
begin
    # Download and filter counties
    shp_path = download_tiger_counties(2023)
    all_counties = GeoDataFrames.read(shp_path)

    state_col = "STUSPS" in names(all_counties) ? :STUSPS : :STATEFP
    counties_df  = filter(r -> r[state_col] == state_abbr, all_counties)
    county_geoms = counties_df.geometry
    n_counties   = nrow(counties_df)

    md"Loaded **$(n_counties) counties** for **$(state_abbr)**."
end

# ╔═╡ 30000000-0000-0000-0000-000000000003
begin
    # Build centroids (lat/lon from bounding box midpoints as approximation)
    function _centroid_latlon(geom)
        bb = GeoInterface.extent(geom)
        lat = (bb.Y[1] + bb.Y[2]) / 2
        lon = (bb.X[1] + bb.X[2]) / 2
        (lat, lon)
    end

    centroids = _centroid_latlon.(county_geoms)
    coords    = Float64.(hcat(first.(centroids), last.(centroids)))

    # Synthetic provider density (replace with AHRF data when available)
    # Use ALAND (land area) as a rough proxy — more land → fewer providers
    if "ALAND" in names(counties_df)
        aland_km2 = Float64.(coalesce.(counties_df.ALAND, 1e9)) ./ 1e6
        provider_density = 20.0 ./ log1p.(aland_km2 ./ 1000.0)
    else
        provider_density = 5.0 .* rand(n_counties) .+ 1.0
    end

    # Spatial weights (distance-band, 100 km)
    W = build_distance_band_weights(coords; bandwidth_km = 100.0)

    # Global Moran's I
    morans_result = compute_morans_i(provider_density, W; permutations = 499)

    # LISA clusters
    lisa_result = lisa_clusters(provider_density, W; permutations = 499, alpha = 0.05)

    # E2SFCA accessibility (synthetic providers = county centroids)
    providers = DataFrame(
        lat    = first.(centroids),
        lon    = last.(centroids),
        supply = provider_density,
    )
    pop_locs = DataFrame(
        id         = string.(1:n_counties),
        lat        = first.(centroids),
        lon        = last.(centroids),
        population = fill(1000.0, n_counties),
    )
    access_df = e2sfca(providers, pop_locs, Float64(catchment_km);
                        decay = :gaussian, sigma_km = Float64(catchment_km) / 3)

    counties_df.provider_density = provider_density
    counties_df.lisa_cluster     = lisa_result
    counties_df.access_2sfca     = access_df.accessibility

    md"""
    **Analysis complete.**

    - Global Moran's I = **$(round(morans_result.I; digits=3))**
      (z = $(round(morans_result.z_score; digits=2)), p = $(round(morans_result.p_value; digits=3)))
    - LISA clusters: **$(sum(lisa_result .== "HH"))** HH, **$(sum(lisa_result .== "LL"))** LL
    - Mean accessibility score: **$(round(mean(access_df.accessibility); digits=4))**
    """
end

# ╔═╡ 40000000-0000-0000-0000-000000000001
md"""
## Interactive Map

LISA cluster map with county-level colour coding.
"""

# ╔═╡ 40000000-0000-0000-0000-000000000002
let
    cluster_color = Dict(
        "HH" => 4, "HL" => 3, "LH" => 2, "LL" => 1, "NS" => 0
    )
    cvals = Float64.([get(cluster_color, c, 0) for c in lisa_result])

    fig = Figure(resolution = (900, 600))
    ax  = GeoAxis(fig[1, 1];
                  dest  = "+proj=laea +lat_0=45 +lon_0=-96 +ellps=WGS84",
                  title = "LISA Clusters — $(state_abbr) Provider Density")
    poly!(ax, county_geoms;
          color       = cvals,
          colormap    = [:lightgray, :blue, :cyan, :orange, :red],
          colorrange  = (0, 4),
          strokecolor = :white,
          strokewidth = 0.5)

    legend_items = [
        PolyElement(color = :lightgray),
        PolyElement(color = :blue),
        PolyElement(color = :cyan),
        PolyElement(color = :orange),
        PolyElement(color = :red),
    ]
    Legend(fig[1, 2], legend_items,
           ["NS", "LL (cold spot)", "LH", "HL", "HH (hot spot)"];
           framevisible = false, labelsize = 11)

    fig
end

# ╔═╡ 50000000-0000-0000-0000-000000000001
md"""
## AI Interpretation

Uses the Anthropic Claude API to explain the spatial analysis results for
healthcare policymakers and rural health researchers.

Set `ANTHROPIC_API_KEY` in your environment before running.
"""

# ╔═╡ 50000000-0000-0000-0000-000000000002
"""
    interpret_results(morans_result, lisa_result, accessibility_df, state_name;
                      api_key) -> String

Send spatial analysis results to Claude for natural-language interpretation.
Falls back to a rule-based template if the API call fails.
"""
function interpret_results(morans_result, lisa_result::Vector{String},
                            accessibility_df::DataFrame,
                            state_name::AbstractString;
                            api_key::String = get(ENV, "ANTHROPIC_API_KEY", ""))
    n         = length(lisa_result)
    hh_count  = sum(lisa_result .== "HH")
    ll_count  = sum(lisa_result .== "LL")
    pct_hh    = round(hh_count / n * 100; digits = 1)
    acc_mean  = round(mean(accessibility_df.accessibility); digits = 4)
    acc_sd    = round(std(accessibility_df.accessibility);  digits = 4)
    p10       = quantile(accessibility_df.accessibility, 0.10)
    pct_desert = round(sum(accessibility_df.accessibility .< p10) / n * 100; digits = 1)

    if isempty(api_key)
        return _fallback_interpretation(state_name, morans_result, hh_count,
                                         ll_count, acc_mean, pct_desert)
    end

    prompt = """
    You are analyzing spatial health data for $(state_name).

    **Spatial Autocorrelation (provider density):**
    - Global Moran's I = $(round(morans_result.I; digits=3))
    - Z-score = $(round(morans_result.z_score; digits=2))
    - P-value = $(round(morans_result.p_value; digits=3))

    **LISA Clusters:**
    - HH (hot spots, high provider density clusters): $(hh_count) counties ($(pct_hh)%)
    - LL (cold spots, low provider density clusters): $(ll_count) counties
    - Total counties analyzed: $(n)

    **Accessibility (E2SFCA scores):**
    - Mean: $(acc_mean), SD: $(acc_sd)
    - Counties in access desert (< 10th percentile): $(pct_desert)%

    Please provide a 3-4 paragraph interpretation of these findings for
    healthcare policymakers and rural health researchers. Explain what the
    spatial clustering patterns mean in practical terms, identify which
    populations are most at risk, and note what additional analyses would be
    informative. Be accurate, actionable, and accessible to non-statistician
    readers.
    """

    try
        resp = HTTP.post(
            "https://api.anthropic.com/v1/messages";
            headers = [
                "x-api-key"         => api_key,
                "anthropic-version" => "2023-06-01",
                "content-type"      => "application/json",
            ],
            body = JSON.json(Dict(
                "model"      => "claude-sonnet-4-6",
                "max_tokens" => 1500,
                "system"     => "You are an expert in rural health geography and " *
                                "spatial epidemiology. You interpret spatial analysis " *
                                "results for healthcare policymakers and rural health " *
                                "researchers. Your interpretations are accurate, " *
                                "actionable, and accessible to non-statistician readers.",
                "messages"   => [Dict("role" => "user", "content" => prompt)],
            )),
            status_exception = true,
        )
        data = JSON.parse(String(resp.body))
        return data["content"][1]["text"]
    catch e
        @warn "Anthropic API call failed: $(e). Using fallback interpretation."
        return _fallback_interpretation(state_name, morans_result, hh_count,
                                         ll_count, acc_mean, pct_desert)
    end
end

# ╔═╡ 50000000-0000-0000-0000-000000000003
function _fallback_interpretation(state, mi, hh_count, ll_count, acc_mean, pct_desert)
    if mi.I > 0.3 && mi.p_value < 0.05
        pattern = "significant positive spatial clustering (Moran's I = $(round(mi.I; digits=3)), p < 0.05), indicating that counties with similar provider levels tend to be geographically grouped"
    elseif abs(mi.I) < 0.1
        pattern = "no significant spatial clustering (Moran's I ≈ $(round(mi.I; digits=3))), suggesting provider distribution is geographically random"
    else
        pattern = "some spatial structure (Moran's I = $(round(mi.I; digits=3)))"
    end

    """
    **Automated Interpretation for $(state)**

    The spatial analysis reveals $(pattern).
    $(hh_count) counties form high-provider-density hot spots (HH clusters),
    while $(ll_count) counties are in low-density cold spots (LL clusters)
    that may represent primary care shortage areas warranting further review.

    The E2SFCA accessibility analysis shows a mean score of $(acc_mean).
    Approximately $(pct_desert)% of counties fall in the access desert
    (below the 10th percentile), indicating limited proximity to primary care.

    *Note: This is a template-based interpretation. Set ANTHROPIC_API_KEY for
    AI-generated analysis.*
    """
end

# ╔═╡ 50000000-0000-0000-0000-000000000004
interpretation = interpret_results(morans_result, lisa_result, access_df, state_abbr)

# ╔═╡ 50000000-0000-0000-0000-000000000005
Markdown.parse(interpretation)

# ╔═╡ 60000000-0000-0000-0000-000000000001
md"""
## Policy Recommendations

A second API call generates evidence-based policy recommendations for the
identified shortage areas.
"""

# ╔═╡ 60000000-0000-0000-0000-000000000002
"""
    generate_policy_recommendations(state_name, hh_count, ll_count, pct_desert;
                                     api_key) -> String

Generate 3-5 specific, evidence-based policy recommendations based on
spatial analysis results.  Falls back to a template if the API is unavailable.
"""
function generate_policy_recommendations(state_name::AbstractString,
                                          hh_count::Int, ll_count::Int,
                                          pct_desert::Float64;
                                          api_key::String = get(ENV, "ANTHROPIC_API_KEY", ""))
    if isempty(api_key)
        return _fallback_recommendations(state_name, ll_count, pct_desert)
    end

    prompt = """
    Based on a spatial analysis of $(state_name), we found:
    - $(hh_count) counties in high-provider-density clusters (HH)
    - $(ll_count) counties in low-provider-density clusters (LL)
    - $(pct_desert)% of counties in healthcare access deserts (E2SFCA < 10th percentile)

    Please generate 3-5 specific, evidence-based policy recommendations for
    improving primary healthcare access in the identified shortage clusters.
    Format as a numbered list. For each recommendation, mention relevant
    federal programs where applicable (e.g., NHSC scholarship/loan repayment,
    HPSA designation, Critical Access Hospital program, FQHC designation,
    Rural Health Clinics, telehealth waivers).
    """

    try
        resp = HTTP.post(
            "https://api.anthropic.com/v1/messages";
            headers = [
                "x-api-key"         => api_key,
                "anthropic-version" => "2023-06-01",
                "content-type"      => "application/json",
            ],
            body = JSON.json(Dict(
                "model"      => "claude-sonnet-4-6",
                "max_tokens" => 1000,
                "system"     => "You are a rural health policy expert. Provide specific, " *
                                "actionable recommendations citing relevant federal programs.",
                "messages"   => [Dict("role" => "user", "content" => prompt)],
            )),
            status_exception = true,
        )
        data = JSON.parse(String(resp.body))
        return data["content"][1]["text"]
    catch e
        @warn "Policy recommendation API call failed: $(e). Using fallback."
        return _fallback_recommendations(state_name, ll_count, pct_desert)
    end
end

# ╔═╡ 60000000-0000-0000-0000-000000000003
function _fallback_recommendations(state, ll_count, pct_desert)
    """
    **Policy Recommendations for $(state)**

    1. **NHSC Loan Repayment Program** — Recruit primary care physicians,
       NPs, and PAs to the $(ll_count) identified LL-cluster counties by
       submitting HPSA designation applications for eligible areas.

    2. **Critical Access Hospital (CAH) Designation** — Review hospitals in
       access desert counties for CAH eligibility (≤25 beds, ≥35 miles from
       nearest hospital) to access enhanced Medicare reimbursement.

    3. **Federally Qualified Health Center (FQHC) Expansion** — Apply for
       HRSA Health Center Program funding to establish new FQHCs or expand
       existing sites in counties with < 10th percentile accessibility scores.

    4. **Telehealth Infrastructure Investment** — Partner with rural broadband
       initiatives to expand telehealth services in the $(round(Int, pct_desert))%
       of counties classified as access deserts.

    5. **Rural Health Clinic (RHC) Certification** — Encourage physician
       practices in shortage areas to obtain RHC certification for enhanced
       Medicaid and Medicare reimbursement.

    *Note: Set ANTHROPIC_API_KEY for AI-generated recommendations tailored
    to the specific geographic patterns identified.*
    """
end

# ╔═╡ 60000000-0000-0000-0000-000000000004
begin
    hh_n       = sum(lisa_result .== "HH")
    ll_n       = sum(lisa_result .== "LL")
    p10_acc    = quantile(access_df.accessibility, 0.10)
    pct_desert = round(sum(access_df.accessibility .< p10_acc) / n_counties * 100; digits=1)

    policy_text = generate_policy_recommendations(state_abbr, hh_n, ll_n, pct_desert)
    Markdown.parse(policy_text)
end

# ╔═╡ Cell order:
# ╠═00000000-0000-0000-0000-000000000001
# ╟─10000000-0000-0000-0000-000000000001
# ╟─20000000-0000-0000-0000-000000000001
# ╠═20000000-0000-0000-0000-000000000002
# ╠═20000000-0000-0000-0000-000000000003
# ╟─30000000-0000-0000-0000-000000000001
# ╠═30000000-0000-0000-0000-000000000002
# ╠═30000000-0000-0000-0000-000000000003
# ╟─40000000-0000-0000-0000-000000000001
# ╠═40000000-0000-0000-0000-000000000002
# ╟─50000000-0000-0000-0000-000000000001
# ╠═50000000-0000-0000-0000-000000000002
# ╠═50000000-0000-0000-0000-000000000003
# ╠═50000000-0000-0000-0000-000000000004
# ╠═50000000-0000-0000-0000-000000000005
# ╟─60000000-0000-0000-0000-000000000001
# ╠═60000000-0000-0000-0000-000000000002
# ╠═60000000-0000-0000-0000-000000000003
# ╠═60000000-0000-0000-0000-000000000004
