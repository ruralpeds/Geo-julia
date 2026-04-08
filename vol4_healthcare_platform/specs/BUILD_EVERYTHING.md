# BUILD_EVERYTHING.md
## Master Claude Code Program — Julia Healthcare GIS Textbook
## Chapter 34.1: 8-Phase End-to-End Build Specification

This document is a complete machine-readable specification that, when executed
by Claude Code, produces the entire four-volume Julia geospatial healthcare
textbook ecosystem from scratch. Each phase is idempotent and can be re-run
independently.

---

## Prerequisites

```bash
# Julia 1.10+
curl -fsSL https://install.julialang.org | sh

# Docker (optional, for Genie deployment)
# CUDA toolkit (optional, for GPU chapter)
# Pluto.jl (optional, for interactive notebooks)
```

---

## Phase 1: Repository Initialisation

**Goal**: Create directory structure and root Project.toml.

```
/
├── julia_geo_packages/          # Vol 1–3 packages workspace
├── healthcare_geo_workspace/    # Vol 2 extended analysis
├── vol4_healthcare_platform/    # Vol 4 platform
├── .github/workflows/           # CI (all volumes)
└── docs/                        # Cross-volume textbook index
```

**Actions**:
1. `git init` (if not already a repo)
2. Create workspace `Project.toml` files for each volume
3. Set up `.gitignore` (exclude `data/raw/`, `*.jls`, `*.so`, `Manifest.toml`)

---

## Phase 2: Vol 1 — HealthcareGeo.jl Core Package

**Target**: `julia_geo_packages/packages/HealthcareGeo/`

**Key modules**:
- `src/census.jl` — Census API client (ACS B01003, B17001, B27001)
- `src/geocoding.jl` — Address → coordinates (Census Geocoder)
- `src/spatial.jl` — Haversine distance, E2SFCA
- `src/visualization.jl` — Choropleth via Plots.jl

**Validation**:
```julia
using HealthcareGeo
df = fetch_acs_data("38", "county"; year=2022, variables=[:pop, :poverty])
@assert nrow(df) == 53
```

---

## Phase 3: Vol 2 — Extended Spatial Analysis Workspace

**Target**: `healthcare_geo_workspace/`

**Key scripts** (executed in order):
1. `01_data_acquisition.jl` — TIGER + ACS for all 50 states
2. `02_access_analysis.jl` — E2SFCA for Primary Care, Mental Health, OB/GYN
3. `03_autocorrelation.jl` — Global/Local Moran's I, Getis-Ord G*
4. `04_regression.jl` — OLS spatial diagnostics, SLM, SEM
5. `05_visualization.jl` — Publication-quality maps

**Validation**:
```julia
include("03_autocorrelation.jl")
@assert 0 < moran_results[:primary_care].I < 1
```

---

## Phase 4: Vol 3 — Four-Package Ecosystem

**Target**: `julia_geo_packages/packages/`

### 4.1 SpatialStats.jl (upgraded)

**Key exports**: `moran`, `moran_local`, `lisa`, `geary`, `getis_ord`,
`lm_spatial`, `lm_tests`, `slm`, `sem`, `sdm`, `SpatialWeights`,
`queen_weights`, `knn_weights`, `distance_weights`, `haversine_km`

**Algorithms**:
- Moran's I: pseudo-p via conditional randomisation (permutations=999)
- LISA: cluster types `[:HH,:LL,:HL,:LH,:NS]` at configurable α
- SLM: ML via Ord (1975) eigenvalue trick, Brent ρ optimisation
- SEM: Cochrane-Orcutt spatial filter
- SDM: augment X with WX, call SLM

### 4.2 Geocode.jl

**Geocoders**: `CensusGeocoder` (batch 1000), `NominatimGeocoder` (1.1s rate),
`ArcGISGeocoder`; `geocode_all` with exponential-backoff retry

### 4.3 MapClassify.jl

**Schemes** (15): `EqualInterval`, `Quantiles`, `NaturalBreaks`, `FisherJenks`,
`JenksCaspall`, `StdMean`, `MaximumBreaks`, `BoxPlot`, `HeadTailBreaks`,
`Percentiles`, `UserDefined`, `PrettyBreaks`, `GeometricInterval`,
`JenksCaspallSampled`, `KMeans`

**Fisher-Jenks DP**: `O(n²·k)` exact optimal classification

### 4.4 Overpass.jl

**Builder**: `OverpassQuery |> node |> way |> bbox |> tag |> execute`
**Cache**: 24h SHA256 file cache
**Helpers**: `download_healthcare_pois(bbox)`, `download_road_network(bbox)`

**Validation** (all packages):
```bash
julia --project=julia_geo_packages test/integration_test.jl
# Expected: Test Summary: 14 tests passed
```

---

## Phase 5: Vol 4 — Healthcare Platform

### 5.1 PointPatterns.jl (Ch 26)

**Target**: `vol4_healthcare_platform/packages/PointPatterns/`

**Key exports**: `PointPattern`, `RectWindow`, `PolyWindow`, `simulate_csr`,
`Kfunction`, `Gfunction`, `Ffunction`, `Jfunction`, `envelope`,
`quadrat_test`, `clarkevans_test`, `scan_statistic`,
`kernel_intensity`, `adaptive_intensity`, `nndist`, `crossdist`

**Algorithms**:
- K-function: Ripley (1976) edge correction, `_ripley_weight` acos formula
- Scan statistic: Kulldorff (1997) Poisson LLR with Monte Carlo p-value
- Kernel intensity: Gaussian/Epanechnikov KDE, Silverman bandwidth rule

### 5.2 Spatial GLMs (Ch 27)

**Target**: `vol4_healthcare_platform/scripts/spatial_glm.jl`

**Models** (Turing.jl NUTS MCMC):
- `spatial_poisson_glm`: ICAR random effect, Poisson likelihood
- `spatial_negbin_glm`: adds NegativeBinomial dispersion parameter r
- `spatial_logistic`: Bernoulli likelihood, logit link

**ICAR prior**: `φ ~ MvNormal(0, σ²·pinv(D - W + εI))`

**Frequentist fallback**: `poisson_glm` via iteratively reweighted least squares

### 5.3 Advanced Cartography (Ch 28)

**Target**: `vol4_healthcare_platform/scripts/advanced_cartography.jl`

**Functions**:
- `bivariate_map`: Joshua Stevens 3×3/4×4 palettes, quantile classification
- `dot_density_positions`: rejection sampling within polygon bounds
- `dorling_cartogram`: force-directed circle packing (100 iterations)
- `fit_healthcare_variogram`: GeoStats.jl spherical/exponential fitting
- `kriging_surface`: Ordinary kriging on regular grid
- `st_difference`: ArchGDAL polygon difference

### 5.4 North Dakota Pipeline (Ch 29)

**Stage 1** — `01_acquire_data.jl`:
- `acquire_tiger_counties()`: TIGER/Line 2023 county shapefiles
- `acquire_acs_nd()`: Census API B17001/B27001/B01003 for state=38
- `acquire_nd_physicians()`: HRSA AHRF physician FTE counts
- `acquire_nd_provider_locations()`: NPPES NPI Registry query

**Stage 2** — `02_prepare_spatial.jl`:
- `geocode_providers()`: batch Census Geocoder with synthetic fallback
- `load_nd_counties()`: Shapefile.jl → GeoDataFrame + synthetic fallback
- `build_analysis_dataset()`: spatial join + ACS merge

**Stage 3** — `03_spatial_analysis.jl`:
- `build_synthetic_nd_weights(n)`: chain weights for offline use
- `compute_e2sfca_access(nd_df, prov_df; catchment_km=50.0)`:
  Gaussian decay 2-step E2SFCA
- `run_spatial_analysis(nd_df, prov_geocoded)`:
  queen weights → E2SFCA → Moran's I × 3 → LISA → OLS + LM tests → SLM

**Stage 4** — `04_visualize.jl`:
- `create_atlas(nd_df, ar)`: 4-panel Figure (E2SFCA / LISA / Poverty / Bivariate)
- `create_pointpattern_plot(ar)`: K-function with CSR envelope

### 5.5 Pluto Dashboard (Ch 30)

**Target**: `vol4_healthcare_platform/notebooks/healthcare_dashboard.jl`

**Reactive cells**:
- Cell 3: `@bind` sliders for `catchment_km`, `alpha_val`, `selected_var`, `color_scheme`
- Cell 5: Reactive analysis — recomputes LISA + Moran when sliders change
- Cell 6: Choropleth / scatter map
- Cell 8: `interpret_spatial_results` — calls `claude-sonnet-4-6` API;
  rule-based fallback when `ANTHROPIC_API_KEY` absent

### 5.6 Genie.jl REST API (Ch 31)

**Target**: `vol4_healthcare_platform/web/app.jl`

**Endpoints**:

| Route | Method | Parameters |
|-------|--------|-----------|
| `/api/health` | GET | — |
| `/api/counties` | GET | — |
| `/api/county/:geoid` | GET | geoid path param |
| `/api/moran` | POST | `{values: [...], permutations: 999}` |
| `/api/access` | GET | `?catchment=45` (1–200 km) |
| `/api/lisa` | GET | `?alpha=0.05` (0.001–0.20) |

**Startup**: `__init_analysis__()` at server start; deserializes `nd_weights.jls`
or builds synthetic chain weights; loads `nd_analysis_results.csv` or synthetic demo

### 5.7 Docker (Ch 31.2)

**Target**: `vol4_healthcare_platform/web/Dockerfile`

**Build stages**:
1. `FROM julia:1.10-bullseye`
2. `apt-get install libgdal-dev libproj-dev libgeos-dev`
3. `Pkg.instantiate()` + `Pkg.precompile()`
4. `PackageCompiler.create_sysimage([...])` → `/app/geo_sysimage.so`
5. `CMD julia -J/app/geo_sysimage.so --project=. web/app.jl`

**Expected startup**: ~3s with sysimage, ~30s without

### 5.8 GPU Acceleration (Ch 33)

**Target**: `vol4_healthcare_platform/scripts/gpu_acceleration.jl`

**Functions**:
- `haversine_matrix_gpu(lats, lons)`: CUDA kernel (16×16 thread blocks)
- `e2sfca_gpu(pop_lats, pop_lons, pop, prov_lats, prov_lons)`: GPU E2SFCA
- `moran_permutation_gpu(x, W; permutations=9999)`: batched SpMM
  - `Z_perm` = (n × permutations) matrix, all shuffles at once
  - `WZ = d_W * d_Z` one GEMM call
  - `I_perm = diag(Z_perm' * WZ) / (n-1)`
- `spatial_lag_gpu(W, x)`: SpMV
- `benchmark_gpu_vs_cpu(n=500)`: comparison table

**Backends**: `:cuda` (NVIDIA), `:metal` (Apple Silicon), `:none` (CPU fallback)

---

## Phase 6: Testing

### 6.1 Unit tests

```bash
# PointPatterns
julia --project=vol4_healthcare_platform/packages/PointPatterns \
      vol4_healthcare_platform/packages/PointPatterns/test/runtests.jl

# SpatialStats (Vol 3)
julia --project=julia_geo_packages/packages/SpatialStats \
      julia_geo_packages/packages/SpatialStats/test/runtests.jl
```

### 6.2 Integration tests

```bash
# Vol 3
julia --project=julia_geo_packages julia_geo_packages/test/integration_test.jl

# Vol 4
julia --project=vol4_healthcare_platform \
      vol4_healthcare_platform/test/integration_test.jl
```

### 6.3 API smoke tests

```bash
# Start server
julia --project=vol4_healthcare_platform vol4_healthcare_platform/web/app.jl &
sleep 5

# Run tests
curl -s http://localhost:8080/api/health | jq '.status == "ok"'
curl -s http://localhost:8080/api/counties | jq 'length == 53'
curl -s 'http://localhost:8080/api/access?catchment=30' | jq 'length'
curl -s 'http://localhost:8080/api/lisa?alpha=0.05' | jq '.[0].cluster'
curl -s -X POST http://localhost:8080/api/moran \
     -H 'Content-Type: application/json' \
     -d '{"values": ['"$(python3 -c "import random; print(','.join([str(random.random()) for _ in range(53)]))")']}' \
     | jq '.I'
```

---

## Phase 7: CI Configuration

### 7.1 Vol 4 CI

**Target**: `.github/workflows/test_vol4.yml`

```yaml
name: Vol 4 Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        julia-version: ['1.10', '1.11']
    steps:
      - uses: actions/checkout@v4
      - uses: julia-actions/setup-julia@v2
        with: { version: '${{ matrix.julia-version }}' }
      - run: |
          julia --project=vol4_healthcare_platform/packages/PointPatterns \
            -e 'import Pkg; Pkg.test()'
      - run: |
          julia --project=vol4_healthcare_platform \
            vol4_healthcare_platform/test/integration_test.jl
```

---

## Phase 8: Registry Submission

### 8.1 PointPatterns.jl

```
Package: PointPatterns
UUID: a7b8c9d0-e1f2-3456-0123-789012345678
Version: 0.1.0
Julia compat: 1.10+
```

**Submission steps**:
1. Ensure `Project.toml` has `name`, `uuid`, `version`, `[compat]`
2. Ensure `test/runtests.jl` passes on Julia 1.10 + 1.11
3. `git tag v0.1.0 && git push --tags`
4. Comment `@JuliaRegistrator register` on the tagged commit
5. Review General registry PR (auto-merged in ~3 days if CI passes)

### 8.2 SpatialStats.jl (upgrade to 0.2.0)

```
- Add: sdm, geary, haversine_km exports
- Bump version: 0.1.0 → 0.2.0
- Update compat: NearestNeighbors = "0.4"
```

### 8.3 Geocode.jl, MapClassify.jl, Overpass.jl

Initial 0.1.0 submission for each package.

---

## Execution Order

For a complete build from scratch:

```bash
# 1. Repository init
git clone <repo> && cd geo-julia
git checkout claude/open-healthcare-textbook-178jy

# 2–3. Vol 1 + 2 (already built)
# (see julia_geo_packages/specs/vol2_bootstrap.md)

# 4. Vol 3 packages
julia --project=julia_geo_packages -e 'import Pkg; Pkg.instantiate()'
julia --project=julia_geo_packages julia_geo_packages/test/integration_test.jl

# 5. Vol 4 packages
julia --project=vol4_healthcare_platform/packages/PointPatterns \
      -e 'import Pkg; Pkg.instantiate()'
julia --project=vol4_healthcare_platform \
      -e 'import Pkg; Pkg.instantiate()'

# 6. ND pipeline (with synthetic data)
julia --project=vol4_healthcare_platform \
      vol4_healthcare_platform/pipeline/04_visualize.jl

# 7. Integration tests
julia --project=vol4_healthcare_platform \
      vol4_healthcare_platform/test/integration_test.jl

# 8. Web API
julia --project=vol4_healthcare_platform vol4_healthcare_platform/web/app.jl

# 9. Docker
cd vol4_healthcare_platform/web
docker build -t healthcare-geo:latest .
docker run -p 8080:8080 healthcare-geo:latest
```

---

## Textbook Chapter → File Mapping (All Volumes)

| Volume | Chapters | Location |
|--------|----------|----------|
| Vol 1 | 1–15 | `julia_geo_packages/packages/HealthcareGeo/` |
| Vol 2 | 16–22 | `healthcare_geo_workspace/` |
| Vol 3 | 23–25 | `julia_geo_packages/packages/{SpatialStats,Geocode,MapClassify,Overpass}/` |
| Vol 4 | 26–34 | `vol4_healthcare_platform/` |

---

*Master Build Specification — Julia Healthcare GIS Open Textbook*
*Total: 4 volumes, 34 chapters, ~15,000 lines of production Julia code*
*Timothy Hartzog — 2026*
