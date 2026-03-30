# CLAUDE CODE SPECIFICATION: Initialize HealthcareGeo.jl
# File: specs/01_initialize_module.md
# Usage: claude specs/01_initialize_module.md

## Task
Create a new Julia package called HealthcareGeo with the following structure
and files. This is a geospatial health analysis library for studying rural
population health and healthcare access disparities.

## Requirements

### 1. Initialize Julia Package
Run `julia -e 'import Pkg; Pkg.generate("HealthcareGeo")'`
to create the package scaffold.

### 2. Add Dependencies to Project.toml
Add the following packages:
- Shapefile = "8e980197-1aa4-5ad6-a5d0-b97dc4de16d6"
- ArchGDAL = "c9ce4bd3-c3d5-55b8-8973-c0e20141b8c3"
- GeoDataFrames = "62cb38b5-d8d2-4862-a48e-6a340996859f"
- GeoInterface = "cf35fbd7-0cd7-5166-be24-54bfbe79505f"
- GeoStats = "dcc97b0b-8ce5-5539-9008-bb190f959ef6"
- Rasters = "700a0f68-0e07-4f34-ffe2-9db9f3c31d29"
- DataFrames = "a93c6f00-e57d-5684-b466-afe8fa294f38"
- CSV = "336ed68f-0bac-5ca0-87d4-7b16caf5d00e"
- Statistics = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"
- HTTP = "cd3eb016-35fb-5094-929b-558a96fad6f3"
- JSON = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
- CairoMakie = "13f3f980-e62b-5c42-98c6-ff1f3baf88f0"
- GeoMakie = "db073c08-6b98-4ee5-b22a-4b16714a7f43"
- BenchmarkTools = "6e4b80f9-dd63-53aa-95a3-0cdb28fa8baf"

### 3. Create src/HealthcareGeo.jl
Implement the main module file that includes all submodules.
Export the following functions: load_counties, load_providers,
classify_rural_forhp, build_queen_weights, compute_morans_i,
lisa_clusters, two_step_fca, e2sfca, haversine,
make_choropleth_map, healthcare_atlas

### 4. Create test/runtests.jl
Implement unit tests for:
- haversine(): test known distance (NYC to LA ≈ 3,944 km)
- compute_morans_i(): test with perfectly clustered data (should give I ≈ 1)
- classify_rural_forhp(): test with mock tract data including all 4 rules
- two_step_fca(): test with 3 providers and 5 population locations

### 5. Create README.md
Write a comprehensive README with installation instructions, quick start
example loading North Dakota county data and computing accessibility scores,
and links to documentation.
