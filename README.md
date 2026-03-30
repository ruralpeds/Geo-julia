# geo-julia

## Julia Geographic Analysis for Healthcare and Rural Populations

A comprehensive four-volume textbook series on geographic analysis using the Julia programming language, with a focus on healthcare applications, rural population health, and spatial epidemiology.

---

## 📚 Volumes

### Volume I — Geographic Analysis in Julia: Healthcare and Rural Populations
**`textbooks/2026-03-30/Vol1_GeoAnalysis_Julia_Healthcare_Textbook.docx`**

Chapters 1–10 covering:
- Foundations of geographic analysis in healthcare (Tobler's Law, MAUP, spatial autocorrelation, 2SFCA)
- Julia language fundamentals for geospatial science
- The JuliaGeo ecosystem (ArchGDAL, GeoDataFrames, Rasters, GeoStats, GeoMakie)
- Spatial statistics (Moran's I, LISA, GWR) with full Julia implementations
- Defining rural populations (OMB, RUCA, FORHP, Road Ruggedness Scale)
- State of the art in rural health geographic analysis
- Authoritative data sources (HRSA, CDC WONDER, Census Bureau)
- Complete Julia programming guide for healthcare GIS
- Visualization and cartography with GeoMakie.jl
- Claude Code specifications for building the geo analysis system

---

### Volume II — Gap Analysis and Open Population Data
**`textbooks/2026-03-30/Vol2_GapAnalysis_OpenPopulationData.docx`**

Chapters 11–15 covering:
- Deep gap analysis: what Julia's geospatial ecosystem lacks vs Python/R
- Spatial regression gaps (no SLM, SEM, SDM equivalent to PySAL/spatialreg)
- Geocoding desert — no library exists in Julia
- Network analysis gaps vs OSMnx
- Bayesian disease mapping with Turing.jl (BYM model implementation)
- Open population data directory: WorldPop, GHSL, LandScan, Kontur, Meta HRSL
- Complete `PopulationData.jl` module with download/cache system
- Julia `CensusClient.jl` module (tidycensus equivalent)
- Decision framework for when to use native Julia vs PyCall/RCall bridges
- 30-row open data master directory

---

### Volume III — Package Engineering: Building the Missing Ecosystem
**`textbooks/2026-03-30/Vol3_PackageEngineering_BuildingTheEcosystem.docx`**

Chapters 16–25 covering:
- Julia package architecture deep dive (Project.toml, Module system, load path)
- PkgTemplates.jl for production-quality scaffolding
- Type system design (abstract types, parametric types, Val() dispatch)
- Type stability analysis with `@code_warntype` and `@inferred`
- Complete `SpatialWeights` implementation with bounding-box pre-filtering
- Production Moran's I (permutation + analytical), LISA, Getis-Ord G*
- Full `Geocode.jl` with Census Bureau batch API, exponential backoff retry
- `SpatialReg.jl` with Ord (1975) eigenvalue trick for fast log-determinant
- Spatial Lag Model (ML estimation), Spatial Error Model (GMM)
- Testing, Documenter.jl, GitHub Actions CI/CD
- General Registry submission workflow
- PyCall/RCall bridges for PySAL and spdep
- 30-day package launch sequence

---

### Volume IV — Advanced Methods, Real Data, and Deployment
**`textbooks/2026-03-30/Vol4_AdvancedMethods_RealData_Deployment.docx`**

Chapters 26–34 covering:
- `PointPatterns.jl`: K-function, L-function, Monte Carlo envelopes, Kulldorff scan statistic
- Spatial Generalised Linear Models (Poisson, Negative Binomial, Logistic via Turing.jl)
- Bivariate choropleth maps (Joshua Stevens 3×3 palette)
- Dot density maps and Dorling cartograms
- Complete real-data pipeline: North Dakota primary care access analysis
- Pluto.jl interactive dashboard with reactive sliders
- Genie.jl REST API service with Docker containerization
- Contributing to existing JuliaGeo packages
- GPU acceleration with CUDA.jl and Metal.jl
- Master 40-day build program for all 6 missing packages

---

## 🗂️ Packages Specified

| Package | Description | Status |
|---------|-------------|--------|
| `SpatialStats.jl` | Moran's I, LISA, G*, spatial regression | Specified — build ready |
| `Geocode.jl` | Address geocoding (Census, Nominatim, Google) | Specified — build ready |
| `MapClassify.jl` | 15 choropleth classification schemes | Specified — build ready |
| `SpatialReg.jl` | Spatial Lag/Error/Durbin models via ML | Specified — build ready |
| `PointPatterns.jl` | K-function, scan statistic, intensity | Specified — build ready |
| `Overpass.jl` | OpenStreetMap Overpass API client | Specified — build ready |

---

## 📊 Key Data Sources Covered

- **HRSA**: FORHP rural areas, HPSA designations, AHRF (6,000+ county variables)
- **Census Bureau**: ACS 5-year, Decennial 2020, TIGER/Line boundaries
- **USDA ERS**: RUCA codes (2025), Road Ruggedness Scale, Rural Atlas
- **CDC**: WONDER mortality data, Social Vulnerability Index, BRFSS
- **WorldPop**: 100m gridded population 2015–2030 (CC BY 4.0)
- **GHSL**: Global Human Settlement Layer (European Commission JRC)
- **LandScan**: Ambient population, USA high-resolution (ORNL)
- **Kontur**: H3 hexagonal population (~92m, quarterly updates)

---

## 🛠️ Technical Stack

```
Julia 1.9+ | JuliaGeo ecosystem | Turing.jl | GeoMakie.jl
Pluto.jl | Genie.jl | CUDA.jl | Metal.jl
ArchGDAL.jl | Rasters.jl | GeoStats.jl
NearestNeighbors.jl | SparseArrays | HTTP.jl
```

---

## 📅 Generated

**Date:** 2026-03-30  
**Model:** Claude Sonnet 4.6  
**Series:** Julia GeoHealth Textbook — 4 Volumes, 34 Chapters

---

*Rural healthcare geographic analysis — because where you live should not determine whether you live.*
