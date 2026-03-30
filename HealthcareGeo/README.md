# HealthcareGeo.jl

**Geospatial health analysis for rural population health and healthcare access disparities.**

Companion code for *Geographic Analysis in Julia: Healthcare, Rural Populations, and Spatial Data Science* (2026 Edition).

## Overview

HealthcareGeo.jl provides a complete Julia toolkit for:

- **Spatial weights** — Queen contiguity, k-NN, distance band, inverse-distance matrices
- **Spatial autocorrelation** — Global Moran's I, Geary's C, LISA clusters, Getis-Ord G*
- **Healthcare accessibility** — 2SFCA, Enhanced 2SFCA (with distance decay), network-based 2SFCA, gravity model
- **Spatial regression** — Spatial lag model, spatial error model, Geographically Weighted Regression
- **Rural classification** — FORHP 4-rule rural definition using RUCA codes and Road Ruggedness Scale
- **Data pipelines** — Automated download/caching of TIGER/Line, HRSA HPSA, USDA RUCA, Census ACS
- **Visualization** — Choropleth maps and multi-panel healthcare atlases via GeoMakie/CairoMakie
- **AI assistant** — Pluto.jl notebook that interprets spatial results using Claude (claude-sonnet-4-6)
- **Report generator** — CLI tool producing a multi-section PDF rural health report for any U.S. state

---

## Installation

### Prerequisites

- Julia 1.9+  ([julialang.org](https://julialang.org))
- Juliaup version manager (recommended)

```bash
# Install Juliaup
curl -fsSL https://install.julialang.org | sh
juliaup add release && juliaup default release
```

### Clone and activate

```bash
git clone https://github.com/timothyhartzog/geo-julia.git
cd geo-julia/HealthcareGeo
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

---

## Quick Start: North Dakota Primary Care Accessibility

```julia
using HealthcareGeo, GeoDataFrames, DataFrames

# 1. Download Census county boundaries
shp_path = download_tiger_counties(2023)
all_counties = GeoDataFrames.read(shp_path)
nd_counties  = filter(r -> r.STUSPS == "ND", all_counties)

# 2. Build centroids and distance-band weights (100 km)
centroids = [(46.0 + rand()*3, -97.0 - rand()*7) for _ in 1:nrow(nd_counties)]
coords    = hcat(first.(centroids), last.(centroids))
W = build_distance_band_weights(Float64.(coords); bandwidth_km = 100.0)

# 3. Synthetic provider density (replace with AHRF data)
provider_density = 5.0 .* rand(nrow(nd_counties)) .+ 1.0

# 4. Global Moran's I
mi = compute_morans_i(provider_density, W)
println("Moran's I = $(round(mi.I; digits=3)), p = $(round(mi.p_value; digits=3))")

# 5. LISA clusters
clusters = lisa_clusters(provider_density, W; alpha = 0.05)
println("HH clusters: $(sum(clusters .== "HH")), LL clusters: $(sum(clusters .== "LL"))")

# 6. E2SFCA accessibility
providers = DataFrame(
    lat    = first.(centroids),
    lon    = last.(centroids),
    supply = provider_density,
)
pop_locs = DataFrame(
    id         = string.(1:nrow(nd_counties)),
    lat        = first.(centroids),
    lon        = last.(centroids),
    population = fill(1000.0, nrow(nd_counties)),
)
access = e2sfca(providers, pop_locs, 60.0; decay = :gaussian)
println("Mean accessibility: $(round(mean(access.accessibility); digits=4))")
```

---

## Project Structure

```
HealthcareGeo/
├── Project.toml                    # Package dependencies
├── README.md                       # This file
├── src/
│   ├── HealthcareGeo.jl            # Main module
│   ├── data/
│   │   ├── download.jl             # TIGER, HRSA, Census, AHRF downloads
│   │   └── classify.jl             # FORHP rural classification
│   ├── analysis/
│   │   ├── weights.jl              # Spatial weights matrices
│   │   ├── autocorrelation.jl      # Moran's I, Geary's C, LISA, G*
│   │   ├── accessibility.jl        # 2SFCA, E2SFCA, network, gravity
│   │   └── regression.jl           # SAR, SEM, GWR
│   └── viz/
│       └── choropleth.jl           # Choropleth maps and atlas
├── data/
│   ├── raw/                        # Downloaded source files (cached)
│   │   ├── tiger/                  # Census TIGER/Line shapefiles
│   │   ├── hrsa/                   # HRSA HPSA data
│   │   ├── census/                 # ACS data
│   │   └── usda/                   # RUCA codes
│   ├── processed/                  # Cleaned, joined datasets
│   └── outputs/                    # Analysis results, maps
├── notebooks/
│   └── geo_assistant.jl            # Pluto AI-powered assistant notebook
├── scripts/
│   └── generate_report.jl          # CLI report generator
├── specs/
│   ├── 01_initialize_module.md     # Spec 1: package initialization
│   ├── 02_data_pipeline.md         # Spec 2: data downloads
│   ├── 03_spatial_analysis.md      # Spec 3: spatial analysis engine
│   ├── 04_report_generator.md      # Spec 4: automated reports
│   └── 05_ai_assistant.md          # Spec 5: AI assistant
└── test/
    └── runtests.jl                 # Unit and integration tests
```

---

## Running Tests

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

---

## Generating a State Report

```bash
# Set your Census API key (optional but recommended)
export CENSUS_API_KEY="your_key_here"

julia scripts/generate_report.jl --state ND --year 2022 --output nd_report.pdf
```

Supported flags:
| Flag | Description | Default |
|------|-------------|---------|
| `--state` | Two-letter state abbreviation | required |
| `--year`  | Data year | 2022 |
| `--output` | Output PDF file | `rural_health_report.pdf` |
| `--data-dir` | Pre-downloaded data directory | `data/raw/` |

---

## AI-Powered Assistant (Pluto Notebook)

```bash
export ANTHROPIC_API_KEY="your_key_here"
julia -e 'using Pluto; Pluto.run(notebook="notebooks/geo_assistant.jl")'
```

The notebook automatically downloads county data, runs Moran's I + LISA + E2SFCA,
displays an interactive LISA cluster map, and sends results to Claude for
natural-language interpretation and policy recommendations.

---

## Key Functions

| Function | Description |
|----------|-------------|
| `haversine(p1, p2)` | Great-circle distance in km |
| `classify_rural_forhp(df)` | FORHP 4-rule rural classification |
| `build_queen_weights(geoms)` | Queen contiguity spatial weights |
| `build_knn_weights(coords, k)` | K-nearest-neighbor weights |
| `compute_morans_i(vals, W)` | Global Moran's I with permutation test |
| `lisa_clusters(vals, W)` | LISA HH/LL/HL/LH/NS classification |
| `getis_ord_g(vals, W)` | Getis-Ord G* hotspot z-scores |
| `two_step_fca(prov, pop, km)` | Standard 2SFCA accessibility |
| `e2sfca(prov, pop, km)` | Enhanced 2SFCA with distance decay |
| `network_2sfca(prov, pop, T, min)` | Network travel-time 2SFCA |
| `gravity_accessibility(prov, pop)` | Gravity model accessibility |
| `gwr(y, X, coords)` | Geographically Weighted Regression |
| `spatial_lag_model(y, X, W)` | SAR spatial lag model |
| `spatial_error_model(y, X, W)` | SEM spatial error model |
| `make_choropleth_map(...)` | Single-panel choropleth |
| `healthcare_atlas(...)` | Four-panel healthcare atlas |
| `download_tiger_counties(year)` | Download Census TIGER counties |
| `download_ruca_codes()` | Download USDA ERS RUCA codes |
| `fetch_acs_insurance_coverage(state, year)` | ACS uninsurance by tract |
| `load_ahrf(filepath)` | Load HRSA AHRF SAS file |

---

## Data Sources

| Source | What | URL |
|--------|------|-----|
| Census TIGER/Line | County/tract boundaries | census.gov |
| HRSA Data Warehouse | HPSA designations | data.hrsa.gov |
| USDA ERS | RUCA codes, Beale codes | ers.usda.gov |
| Census ACS 5-year | Demographics, insurance | api.census.gov |
| HRSA AHRF | County health workforce | data.hrsa.gov |
| CDC WONDER | Mortality data | wonder.cdc.gov |

---

## References

- Anselin, L. (1995). Local indicators of spatial association — LISA.
- Luo, W. & Wang, F. (2003). Two-step floating catchment area method.
- Brunsdon, C. et al. (1996). Geographically weighted regression.
- FORHP (2025). How We Define Rural. HRSA.
- *Geographic Analysis in Julia: Healthcare, Rural Populations, and Spatial
  Data Science*, 2026 Edition.
