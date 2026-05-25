# Geo-Julia — Geographic Analysis in Julia for Healthcare & Rural Populations

A monorepo for geospatial health analysis in the **Julia programming language**, combining a 34-chapter interactive textbook, production-ready Julia packages, and a full healthcare-analytics toolkit focused on rural population health.

> *Rural healthcare geographic analysis — because where you live should not determine whether you live.*

---

## Repository Structure

```
Geo-julia/
├── textbook/                  # Quarto interactive book (34 chapters, 4 volumes)
├── textbooks/                 # Source .docx manuscripts
├── HealthcareGeo/             # HealthcareGeo.jl — core analytics package
├── julia_geo_packages/        # Standalone Julia geo packages
├── healthcare_geo_workspace/  # Workspace for multi-package development
├── shared/                    # Shared utilities (ErrorHandling, TestUtils)
├── tools/                     # Debug runner and test reporter
├── vol4_healthcare_platform/  # Vol IV platform code (Genie.jl web service)
├── vol5_ml_production/        # Vol V: ML in production
├── vol6_advanced_inference/   # Vol VI: advanced Bayesian inference
├── vol7_deep_learning/        # Vol VII: deep learning for spatial data
├── vol8_equity_spatial/       # Vol VIII: health equity & spatial analysis
├── vol9_survival_networks_ts/ # Vol IX: survival, networks, time series
├── vol10_geostatistics_mapping/  # Vol X: geostatistics & mapping
├── vol11_causal_inference/    # Vol XI: causal inference
├── vol12_health_optimization/ # Vol XII: health systems optimization
└── vol13_spatial_epidemiology/# Vol XIII: spatial epidemiology
```

---

## Textbook — *Geographic Analysis in Julia*

A Quarto-based interactive textbook covering GIS fundamentals through GPU-accelerated spatial analysis.

| Volume | Title | Chapters | Topics |
|--------|-------|----------|--------|
| **I** | Healthcare and Rural Populations | 1–10 | Foundations, JuliaGeo ecosystem, spatial statistics, rural health, data sources |
| **II** | Gap Analysis and Open Population Data | 11–15 | Julia vs Python/R gaps, Bayesian disease mapping, population data directory |
| **III** | Package Engineering | 16–25 | Building `SpatialStats.jl`, `Geocode.jl`, `SpatialReg.jl` from scratch |
| **IV** | Advanced Methods and Deployment | 26–34 | Point patterns, GLMs, Pluto dashboards, Genie.jl web services, GPU |

### Render the Book

Requires [Quarto](https://quarto.org/docs/get-started/) v1.4+.

```bash
cd textbook/
quarto preview   # live preview at localhost:4567
quarto render    # build static HTML site to _book/
```

---

## HealthcareGeo.jl

The core Julia package for rural health geospatial analysis.

**Capabilities:**

| Category | Methods |
|----------|---------|
| Spatial weights | Queen contiguity, k-NN, distance band, inverse-distance |
| Spatial autocorrelation | Global Moran's I, Geary's C, LISA clusters, Getis-Ord G* |
| Healthcare accessibility | 2SFCA, Enhanced 2SFCA, network-based 2SFCA, gravity model |
| Spatial regression | Spatial lag (SAR), spatial error (SEM), GWR |
| Rural classification | FORHP 4-rule definition (RUCA + Road Ruggedness Scale) |
| Data pipelines | TIGER/Line, HRSA HPSA, USDA RUCA, Census ACS downloads |
| Visualization | Choropleth maps, multi-panel healthcare atlases (GeoMakie/CairoMakie) |
| AI assistant | Pluto notebook with Claude-powered interpretation of spatial results |
| Report generator | CLI tool producing a PDF rural health report for any U.S. state |

### Installation

```bash
# Install Juliaup (recommended)
curl -fsSL https://install.julialang.org | sh
juliaup add release && juliaup default release

# Clone and activate
git clone https://github.com/timothyhartzog/geo-julia.git
cd geo-julia/HealthcareGeo
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

### Quick Start

```julia
using HealthcareGeo, GeoDataFrames, DataFrames

# Download Census county boundaries
shp_path = download_tiger_counties(2023)
nd_counties = filter(r -> r.STUSPS == "ND", GeoDataFrames.read(shp_path))

# Build 100 km distance-band spatial weights
coords = # ... county centroids as n×2 matrix
W = build_distance_band_weights(coords; bandwidth_km = 100.0)

# Global Moran's I on provider density
mi = compute_morans_i(provider_density, W)
println("Moran's I = $(round(mi.I; digits=3)), p = $(round(mi.p_value; digits=3))")

# LISA cluster map
clusters = lisa_clusters(provider_density, W; alpha = 0.05)

# Enhanced 2SFCA accessibility
access = e2sfca(providers, pop_locs, 60.0; decay = :gaussian)
```

### Generate a State Report

```bash
export CENSUS_API_KEY="your_key_here"
julia scripts/generate_report.jl --state ND --year 2022 --output nd_report.pdf
```

### AI-Powered Assistant

```bash
export ANTHROPIC_API_KEY="your_key_here"
julia -e 'using Pluto; Pluto.run(notebook="notebooks/geo_assistant.jl")'
```

---

## Packages Specified

Six production Julia packages are fully designed and specified throughout the series:

| Package | Purpose |
|---------|---------|
| `SpatialStats.jl` | Moran's I, LISA, G*, spatial regression |
| `Geocode.jl` | Address geocoding (Census Geocoder, Nominatim) |
| `MapClassify.jl` | 15 choropleth classification schemes |
| `SpatialReg.jl` | Spatial lag/error/Durbin models via ML |
| `PointPatterns.jl` | K-function, scan statistic, intensity estimation |
| `Overpass.jl` | OpenStreetMap Overpass API client |

---

## Key Data Sources

| Source | What |
|--------|------|
| Census TIGER/Line | County and tract boundaries |
| HRSA Data Warehouse | HPSA designations, AHRF workforce file |
| USDA ERS | RUCA codes (2025), Road Ruggedness Scale |
| Census ACS 5-year | Demographics, insurance coverage |
| CDC WONDER | Mortality data |
| WorldPop | 100 m gridded population 2015–2030 (CC BY 4.0) |
| GHSL | Global Human Settlement Layer (EU JRC) |
| LandScan | Ambient population, USA high-resolution (ORNL) |
| Kontur | H3 hexagonal population (quarterly) |

---

## Requirements

- **Julia 1.9+** — [julialang.org](https://julialang.org)
- **Quarto 1.4+** — [quarto.org](https://quarto.org) (textbook only)

Install all Julia dependencies from the repository root:

```julia
using Pkg
Pkg.activate(".")
Pkg.instantiate()
```

---

## Running Tests

```bash
cd HealthcareGeo
julia --project=. -e 'using Pkg; Pkg.test()'
```

---

## References

- Anselin, L. (1995). Local indicators of spatial association — LISA. *Geographical Analysis*.
- Luo, W. & Wang, F. (2003). Measures of spatial accessibility to health care. *Environment and Planning B*.
- Brunsdon, C. et al. (1996). Geographically weighted regression. *The Statistician*.
- FORHP (2025). *How We Define Rural*. HRSA.

---

*Generated 2026-03-30 · Julia 1.9+ · Repository: [timothyhartzog/Geo-julia](https://github.com/timothyhartzog/Geo-julia)*
