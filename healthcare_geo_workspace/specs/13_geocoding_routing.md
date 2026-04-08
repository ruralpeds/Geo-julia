# CLAUDE CODE SPECIFICATION: Geocoding and Routing Bridges
# File: specs/13_geocoding_routing.md
# Vol 2 Chapter 11.4 / 11.5

## Task
Implement geocoding (address → coordinates) and routing (travel time matrix)
utilities within HealthcareGeo as bridges to external services until native
Julia packages are available.

## Geocoding: src/data/geocoding.jl

### census_geocode_batch(addresses; vintage="Current") -> DataFrame
Batch geocode U.S. addresses via Census Bureau Geocoder API.
Input: DataFrame with columns: id, street, city, state, zip
Returns: input + lat, lon, match_type, matched_address, tract_fips
Max batch size: 1,000 addresses. No API key required.

### geocode_all(addresses; batch_size=500, sleep_sec=1.5) -> DataFrame
Chunk-and-batch geocoder for large address lists.
Respects rate limits with configurable sleep between batches.

## Routing: src/data/routing.jl

### osrm_table(origins, destinations; host=OSRM_PUBLIC) -> Matrix{Float64}
OSRM Table service: all-pairs travel time in minutes.
Unreachable pairs → Inf. Uses public demo server by default.
Self-hosting instructions: docker run osrm/osrm-backend ...

### osrm_route(origin, destination; host) -> NamedTuple
Single route: (duration_min, distance_km, geometry_geojson)

### download_osm_network(bbox; transport="drive", outfile) -> String
Download OSM road network from Overpass API as XML.
bbox: (south, west, north, east) decimal degrees
transport: "drive", "walk", or "all"
Returns raw OSM XML; save as .osm for OpenStreetMapX.jl.

## Notes on Julia Ecosystem Gaps (Vol 2 Ch 11)
- Julia has NO native geocoding package (critical gap vs Python/R)
- The Census Geocoder API fills this gap for U.S. healthcare applications
- OSRM self-hosting eliminates rate limits for production batch analysis
- The Overpass API bridges the absence of an OSMnx equivalent in Julia
