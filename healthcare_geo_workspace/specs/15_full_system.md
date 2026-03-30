# CLAUDE CODE SPECIFICATION: Healthcare GeoAnalysis Production System
# File: specs/15_full_system.md
# Vol 2 Chapter 15.2 — Master specification tying all components together.

## Objective
Build the complete HealthcareGeoAnalysis.jl multi-package workspace as described
in Chapter 15. All packages must be individually testable and composable.

## Workspace Structure
```
healthcare_geo_workspace/
├── Project.toml               # Workspace declaration
├── packages/
│   ├── HealthcareGeo/         # Core analysis package (Vol 1)
│   │   ├── Project.toml
│   │   └── src/
│   │       ├── HealthcareGeo.jl
│   │       ├── data/          # download, classify, geocoding, routing
│   │       ├── analysis/      # weights, autocorrelation, accessibility, regression
│   │       └── viz/           # choropleth, atlas
│   ├── SpatialStats/          # Spatial statistics package (Vol 2 Ch 14)
│   │   ├── Project.toml
│   │   └── src/
│   │       ├── SpatialStats.jl
│   │       ├── weights/       # SpatialWeights type
│   │       ├── autocorrelation/ # Moran, LISA, G*
│   │       └── regression/    # OLS+LM, SLM, SEM, SDM
│   └── PopulationData/        # Multi-source population data (Vol 2 Ch 13)
│       ├── Project.toml
│       └── src/
│           ├── PopulationData.jl
│           ├── worldpop.jl
│           ├── ghsl.jl
│           ├── landscan.jl
│           ├── census_client.jl
│           └── zonal_stats.jl
├── scripts/
│   ├── run_state_analysis.jl  # Full state-level analysis pipeline
│   └── batch_county_report.jl # Batch county reports
├── notebooks/
│   ├── exploratory/           # Pluto/Jupyter exploration notebooks
│   └── reports/               # Finalised report notebooks
├── data/
│   ├── raw/                   # Downloaded source data
│   ├── processed/             # Cleaned/joined datasets
│   └── outputs/               # Maps, reports, tables
└── specs/                     # This file and other Claude Code specs
```

## Prerequisites
- Julia >= 1.10
- Environment variables: CENSUS_API_KEY (optional), ANTHROPIC_API_KEY (for AI assistant)
- Docker (optional, for self-hosted OSRM)

## Execution Order
Run specifications in this order:
1. specs/01_initialize_module.md    (HealthcareGeo core — already implemented)
2. specs/02_data_pipeline.md        (HRSA/Census downloads — already implemented)
3. specs/03_spatial_analysis.md     (accessibility, autocorrelation — already implemented)
4. specs/04_report_generator.md     (automated PDF reports — already implemented)
5. specs/05_ai_assistant.md         (Claude AI assistant notebook — already implemented)
6. specs/11_spatial_stats_package.md (SpatialStats.jl — this phase)
7. specs/12_population_data_package.md (PopulationData.jl — this phase)
8. specs/13_geocoding_routing.md    (geocoding + routing bridges — this phase)

## Validation Tests
After all specifications are run, execute:

```julia
using HealthcareGeo, SpatialStats, PopulationData

# 1. Data acquisition
shp_path = HealthcareGeo.download_tiger_counties(2023)
counties = GeoDataFrames.read(shp_path)
@assert nrow(counties) > 3000

# 2. State filter
nd = filter(r -> r.STUSPS == "ND", counties)
@assert nrow(nd) == 53  # North Dakota has 53 counties

# 3. Spatial weights (SpatialStats)
w = SpatialStats.distance_weights(nd, 150.0)
@assert w.n == 53
@assert all(abs.(vec(sum(Matrix(w.W); dims=2)) .- 1.0) .< 1e-9)

# 4. Moran's I (SpatialStats)
vals = rand(53)
result = SpatialStats.moran(vals, w; method=:permutation, permutations=199)
@assert -1.0 <= result.I <= 1.0

# 5. Census ACS (PopulationData)
nd_acs = PopulationData.get_acs(["B01001_001E"]; geography="county", state="38")
@assert nrow(nd_acs) == 53

# 6. Accessibility (HealthcareGeo)
providers = DataFrame(lat=rand(10).+46, lon=rand(10).-97, supply=fill(5.0,10))
pops = DataFrame(id=string.(1:53), lat=rand(53).+46, lon=rand(53).-97,
                  population=fill(1000.0, 53))
access = HealthcareGeo.e2sfca(providers, pops, 60.0; decay=:gaussian)
@assert nrow(access) == 53
@assert all(access.accessibility .>= 0)
```

## Performance Benchmarks (Apple M2 or equivalent)
- distance_weights(nd_53_counties, 150km): < 1 second
- moran(vals_3000, W, permutations=999): < 5 seconds
- lisa(vals_3000, W, permutations=999): < 30 seconds
- e2sfca(50 providers, 500 pop locs): < 2 seconds
- full_state_report("ND"): < 5 minutes

## Deployment: Docker Container
```dockerfile
FROM julia:1.10-bullseye
COPY . /workspace
WORKDIR /workspace
RUN julia --project=/workspace -e 'import Pkg; Pkg.instantiate()'
ENV CENSUS_API_KEY=""
ENTRYPOINT ["julia", "--project=/workspace", "scripts/run_state_analysis.jl"]
```

Build and run:
```bash
docker build -t healthcare-geo .
docker run -e CENSUS_API_KEY=$CENSUS_API_KEY healthcare-geo --state ND --year 2022
```
