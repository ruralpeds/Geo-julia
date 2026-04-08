# CLAUDE CODE SPECIFICATION: Vol 3 Bootstrap
# File: julia_geo_packages/specs/vol3_bootstrap.md
# Vol 3 Chapter 22 — Julia Geospatial Package Engineering

## Objective
Build six production-quality Julia packages for the General Registry,
bridging critical gaps in the Julia geospatial ecosystem.

## Workspace Root
`julia_geo_packages/` (relative to repo root)

## Package Inventory

| Package       | Gap Filled                          | Key Innovation                          |
|---------------|-------------------------------------|-----------------------------------------|
| SpatialStats  | No spatial stats package            | Sparse W, Val dispatch, LISA/G*/SLM/SEM |
| Geocode       | Zero geocoding packages in Julia    | CensusGeocoder + Nominatim + ArcGIS     |
| MapClassify   | No choropleth classifier            | 15 schemes, Fisher-Jenks DP O(n·k)      |
| Overpass      | No OSMnx equivalent                 | Fluent builder, healthcare POI download |

## Execution Order (all already implemented)
1. `packages/SpatialStats/` — upgraded from Vol 2 with sparse matrices throughout
2. `packages/Geocode/` — first geocoding library for Julia
3. `packages/MapClassify/` — 15 classification schemes
4. `packages/Overpass/` — Overpass API fluent builder
5. `scripts/pycall_bridge.jl` — PySAL integration
6. `scripts/rcall_bridge.jl` — R spdep/spatialreg integration
7. `test/integration_test.jl` — full cross-package integration test

## CRITICAL Architecture Notes

### SpatialStats: Sparse matrices throughout
- NEVER build a dense n×n weight matrix
- All W stored as `SparseMatrixCSC{Float64,Int}`
- LISA uses conditional permutation (fix i, permute all j≠i)
- ML eigenvalue approach: `log|I-ρW| = Σ log|1-ρ·eig_i|`
- Bounding-box pre-filter on queen contiguity (skip distant polygon pairs)

### Geocode: Rate limiting and User-Agent
- Nominatim: 1.1s sleep between requests (hard requirement)
- Nominatim: non-empty User-Agent is REQUIRED (throws if empty)
- Census geocoder: max 1,000 per batch
- `is_po_box()`, `is_rural_route()`: flag addresses that geocode poorly

### MapClassify: Fisher-Jenks DP
- O(n·k) via two n×k DP matrices (error_matrix and membership_matrix)
- GoodnesOfVarianceFit = 1 - SDCM/SDAM
- `compare_classifiers(values, k)` returns DataFrame for all schemes

### Overpass: Rate limiting and caching
- 1.0s minimum between requests
- 24h file cache keyed by SHA256(query)
- `pois_to_df()` filters to healthcare-relevant nodes only
- Healthcare tags: amenity={hospital,clinic,pharmacy,doctors,dentist,...}, healthcare=*

## Validation

Run in Julia after `Pkg.develop` of all packages:

```julia
using SpatialStats, Geocode, MapClassify, Overpass
using DataFrames, SparseArrays

# SpatialStats
n = 50
# Build chain weights manually for test
Is=[]; Js=[]; Vs=[]
for i in 1:n-1; push!(Is,i,i+1); push!(Js,i+1,i); push!(Vs,1.0,1.0); end
W = SparseArrays.sparse(Is,Js,Vs,n,n)
sw = SpatialStats.SpatialWeights(W, n,
     SpatialStats.RowStandardizedStyle(),
     SpatialStats.DistanceTransform(), 0, 1.5, 1, 2)
y = randn(n)
r = moran(y, sw); @assert -1.0 <= r.I <= 1.0
lr = lisa(y, sw; permutations=99)
@assert all(t ∈ (:HH,:LL,:HL,:LH,:NS) for t in lr.cluster_type)

# MapClassify
vals = randn(100) .* 10 .+ 50
r_nb = classify(vals, NaturalBreaks(5))
@assert r_nb.gvf >= classify(vals, EqualInterval(5)).gvf
@assert all(1 .<= r_nb.assignments .<= 5)

# Geocode
@assert is_po_box("P.O. Box 123")
@assert is_rural_route("RR 2 Box 45")
@assert normalize_address("123 Main St.") == "123 Main Street"
@assert standardize_state("North Dakota") == "ND"

# Overpass query builder
q = OverpassQuery() |>
    within_bbox(45.0,-100.0,47.0,-96.0) |>
    node_with_tag("amenity","hospital") |>
    recurse_down() |>
    output(:json)
ql = build_query(q)
@assert occursin("[out:json]", ql)
@assert occursin("hospital", ql)

println("All Vol 3 validation checks passed.")
```

## GitHub Actions CI (.github/workflows/test.yml)

```yaml
name: Test Vol 3 Packages
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: julia-actions/setup-julia@v2
        with: { version: '1.10' }
      - name: Test SpatialStats
        run: julia --project=julia_geo_packages/packages/SpatialStats -e 'using Pkg; Pkg.test()'
      - name: Test MapClassify
        run: julia --project=julia_geo_packages/packages/MapClassify -e 'using Pkg; Pkg.test()'
      - name: Test Geocode
        run: julia --project=julia_geo_packages/packages/Geocode -e 'using Pkg; Pkg.test()'
      - name: Test Overpass
        run: julia --project=julia_geo_packages/packages/Overpass -e 'using Pkg; Pkg.test()'
```

## General Registry Submission Checklist

For each package:
- [ ] `Project.toml` with UUID, version, all deps with UUIDs and compat bounds
- [ ] `src/<PackageName>.jl` with module docstring
- [ ] `test/runtests.jl` with comprehensive tests
- [ ] No private URLs in source
- [ ] CI green on ubuntu-latest Julia 1.10
- [ ] `Pkg.test()` passes offline (network tests wrapped in try/catch)
- [ ] Julia >= 1.10 compatibility
- [ ] Exported API documented with docstrings
- [ ] Register with: `using Registrator; @register`
