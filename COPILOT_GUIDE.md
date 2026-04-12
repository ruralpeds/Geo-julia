# GeoSpatialEngine - GitHub Copilot Implementation Guide

**Last Updated**: April 12, 2026  
**Version**: 1.0.0  
**Target**: AI-Assisted Development with GitHub Copilot

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture for Copilot](#architecture-for-copilot)
3. [Prompt Templates](#prompt-templates)
4. [Implementation Patterns](#implementation-patterns)
5. [Code Generation Guidelines](#code-generation-guidelines)
6. [Testing Patterns](#testing-patterns)
7. [Documentation Standards](#documentation-standards)
8. [Common Tasks with Copilot](#common-tasks-with-copilot)

---

## Overview

### Purpose
This guide provides structured patterns and prompts for using GitHub Copilot to efficiently implement GeoSpatialEngine functionality. The project is specifically designed to be Copilot-friendly with clear patterns, comprehensive types, and well-structured modules.

### Copilot Strengths in This Project
- ✅ Function signature matching (many patterns already defined)
- ✅ API client implementation (HTTP patterns repeatable)
- ✅ Test generation (from existing test patterns)
- ✅ Documentation (from docstrings)
- ✅ Boilerplate code (module setup, config)

### Copilot Limitations to Manage
- ⚠️ External API knowledge (needs mock responses or documentation)
- ⚠️ Complex spatial algorithms (needs research or examples)
- ⚠️ Performance optimization (needs benchmarks)
- ⚠️ Cross-module consistency (needs validation)

---

## Architecture for Copilot

### Module Structure (Copilot-Friendly)
```
GeoSpatialEngine/
├── src/
│   ├── GeoSpatialEngine.jl      # Main module
│   ├── core/
│   │   ├── types.jl             # All types defined first
│   │   └── engine.jl            # Core logic
│   ├── ingestion/
│   │   ├── ingestion.jl         # File/URL parsers
│   │   ├── validators.jl        # Validation logic
│   │   └── caching.jl           # Caching system
│   ├── sources/
│   │   ├── sources_registry.jl  # Registry pattern
│   │   ├── noaa.jl              # Each source separate
│   │   ├── usgs.jl
│   │   ├── openstreetmap.jl
│   │   ├── copernicus.jl
│   │   └── generic.jl
│   ├── analysis/
│   │   ├── spatial_analysis.jl
│   │   ├── statistics.jl
│   │   └── modeling.jl
│   ├── features/
│   │   ├── feature_extraction.jl
│   │   └── preprocessing.jl
│   ├── visualization/
│   │   ├── maps.jl
│   │   └── plots.jl
│   ├── workflow/
│   │   ├── workflow.jl
│   │   └── pipeline.jl
│   └── utils/
│       ├── logging.jl
│       ├── helpers.jl
│       └── configuration.jl
├── test/
│   ├── runtests.jl
│   ├── unit_tests/
│   ├── integration_tests/
│   └── fixtures/
└── docs/
    ├── make.jl
    ├── src/
    │   ├── index.md
    │   ├── guide.md
    │   └── api.md
    └── build/
```

### Why This Structure Works with Copilot
1. **Clear Module Boundaries**: Each file has one responsibility
2. **Consistent Patterns**: Similar functions have similar signatures
3. **Type Definitions First**: Copilot can understand all types before implementation
4. **Isolated Functionality**: Easy to generate code for single modules

---

## Prompt Templates

### Template 1: API Implementation

```
FILE: GeoSpatialEngine/src/sources/[SOURCE].jl
TASK: Implement actual API fetching for [SOURCE_NAME]

CONTEXT:
- Source API endpoint: [URL]
- Authentication: [None/API Key/OAuth2]
- Response format: [JSON/XML/etc]
- Required fields in response: [field list]

FUNCTION SIGNATURE (already defined):
function fetch_[DATA_TYPE](...)::GeoSpatialData

IMPLEMENTATION REQUIREMENTS:
1. Build HTTP request with proper URL encoding
2. Handle authentication (API keys in credentials dict)
3. Add timeout and retry logic
4. Parse JSON3 response to extract geospatial data
5. Validate required fields are present
6. Return GeoSpatialData with proper metadata
7. Handle errors gracefully with informative messages

EXAMPLE RESPONSE:
[Provide sample JSON from actual API]

CODE PATTERN TO FOLLOW:
```julia
function fetch_[DATA_TYPE](source::DataSource, kwargs) -> GeoSpatialData
    # 1. Build request URL from source.url and params
    url = string(source.url, "/endpoint?", 
                 "param1=", get(kwargs, :param1, "default"),
                 "&param2=", get(kwargs, :param2, "default"))
    
    # 2. Get credentials if needed
    api_key = get(source.credentials, "api_key", "")
    
    # 3. Make request
    try
        response = HTTP.get(url; 
                           headers=["Authorization" => "Bearer $api_key"],
                           timeout=source.timeout)
        
        # 4. Parse response
        data = JSON3.read(response.body)
        
        # 5. Extract and validate fields
        if !haskey(data, "required_field")
            error("Response missing required_field")
        end
        
        # 6. Build DataFrame
        df = DataFrame(
            lat=data["latitude"],
            lon=data["longitude"],
            value=data["value"]
        )
        
        # 7. Return GeoSpatialData
        return GeoSpatialData(df;
            metadata=Dict("source" => "SourceName", "api" => source.url),
            crs="EPSG:4326"
        )
    catch e
        @error "Failed to fetch data: $e"
        # Return empty but valid GeoSpatialData
        return GeoSpatialData(DataFrame())
    end
end
```
```

### Template 2: Spatial Operations

```
FILE: GeoSpatialEngine/src/analysis/spatial_analysis.jl
TASK: Implement [OPERATION_NAME] spatial operation

FUNCTION SIGNATURE:
function [operation_name](data::GeoSpatialData, [params...])::GeoSpatialData

OPERATION DESCRIPTION:
[Describe what the operation does geometrically]

ALGORITHM:
1. Extract geometries from data
2. Apply geometric transformation
3. Create new GeoSpatialData with results
4. Preserve or update metadata appropriately

REQUIRED LIBRARIES:
- GeoInterface.jl: For geometry interface
- LibGEOS.jl: For geometric operations

EXAMPLE:
Input: Points or polygons at arbitrary locations
Output: Same geometry type, modified according to operation
Metadata: Add operation info to "operations" array

EDGE CASES TO HANDLE:
1. Empty data
2. Invalid geometries
3. CRS mismatches between inputs
4. Extreme parameter values

IMPLEMENTATION PATTERN:
```julia
function [operation_name](data::GeoSpatialData, param::Float64)::GeoSpatialData
    # Validate inputs
    @info "Performing [operation_name] with param=$param"
    
    if nrow(data.data) == 0
        @warn "Empty dataset"
        return data
    end
    
    # Extract geometries
    geometries = extract_geometries(data)
    
    # Apply operation using LibGEOS
    result_geoms = [apply_operation(geom, param) for geom in geometries]
    
    # Create result data
    result_df = copy(data.data)
    result_data = GeoSpatialData(result_df;
        geometry=result_geoms,
        metadata=merge(data.metadata, 
                       Dict("operation" => "[operation_name]", "param" => param)),
        crs=data.crs
    )
    
    return result_data
end
```
```

### Template 3: Unit Tests

```
FILE: GeoSpatialEngine/test/unit_tests/test_[module].jl
TASK: Generate comprehensive unit tests for [function_name]

FUNCTION TO TEST:
[Provide function signature and docstring]

TEST CATEGORIES:
1. Happy path (normal input, expected output)
2. Edge cases (empty input, boundary values)
3. Error handling (invalid input, exceptions)
4. Performance (timing for large inputs)
5. Type correctness (output type validation)

FIXTURES AVAILABLE:
- sample_data::GeoSpatialData (10 rows of test data)
- test_bounds::NamedTuple ((-180, -90, 180, 90))
- test_crs::String ("EPSG:4326")

TEST PATTERN:
```julia
@testset "[Function Name] Tests" begin
    @testset "Happy path - [scenario]" begin
        result = [function_name]([args])
        @test isa(result, [ExpectedType])
        @test [validation_expression]
    end
    
    @testset "Edge case - [scenario]" begin
        # Empty data
        empty_data = GeoSpatialData(DataFrame())
        result = [function_name](empty_data)
        @test nrow(result.data) == 0
    end
    
    @testset "Error handling - [scenario]" begin
        @test_throws ErrorType [function_name]([invalid_args])
    end
end
```
```

### Template 4: Documentation

```
FILE: GeoSpatialEngine/src/[module]/[file].jl
TASK: Generate documentation for function [function_name]

REQUIREMENTS:
- Docstring in Julia docstring format
- Include all parameters in Args section
- Document return type and structure
- Provide usage example
- Include references to related functions
- Note any performance considerations

PATTERN:
```julia
\"\"\"
    function_name(arg1::Type1, arg2::Type2; kwarg1::Type3=default)::ReturnType

Brief description of what the function does.

Longer description explaining the function's behavior, assumptions,
and any important notes about usage.

# Arguments
- `arg1::Type1`: Description of arg1
- `arg2::Type2`: Description of arg2
- `kwarg1::Type3=default`: Description of optional keyword argument

# Returns
- `ReturnType`: Description of return value structure

# Examples
\`\`\`julia
using GeoSpatialEngine

# Create sample data
data = GeoSpatialData(DataFrame(...))

# Use the function
result = function_name(data, arg2_value)

# Access results
println(result.metadata)
\`\`\`

# Performance
- Time complexity: O(n) where n is number of rows
- Space complexity: O(n)
- Tips: Consider using batch processing for very large datasets

# See Also
- [`related_function`](@ref)
- [`other_function`](@ref)
\"\"\"
function function_name(arg1::Type1, arg2::Type2; kwarg1::Type3=default)::ReturnType
    # Implementation
end
```
```

---

## Implementation Patterns

### Pattern 1: Data Source Handler

Use this pattern for implementing each data source (NOAA, USGS, etc.):

```julia
# 1. Define source-specific function
function fetch_[specific_data](source::DataSource, kwargs)::GeoSpatialData
    # 2. Log the operation
    @info "Fetching [data type] from $(source.name)"
    
    # 3. Validate inputs
    validate_kwargs(kwargs)
    
    # 4. Build request
    url = "$(source.url)/endpoint"
    params = build_query_params(kwargs, source.parameters)
    
    # 5. Execute request
    response = make_api_request(url, params, source.credentials)
    
    # 6. Parse response
    data = parse_response(response)
    
    # 7. Construct GeoSpatialData
    df = build_dataframe(data)
    metadata = Dict(
        "source" => source.name,
        "url" => source.url,
        "parameters" => kwargs,
        "timestamp" => now(UTC)
    )
    
    return GeoSpatialData(df; metadata=metadata, crs="EPSG:4326")
end
```

### Pattern 2: Analysis Operation

```julia
function analyze_[operation](data::GeoSpatialData, [params...])::GeoSpatialData
    @info "Performing $(operation) analysis"
    
    # Validate input
    validate_geospatial_data(data) || error("Invalid input data")
    
    if nrow(data.data) == 0
        return data  # Return empty data unchanged
    end
    
    # Perform analysis
    result = perform_operation(data, [params...])
    
    # Create output
    output_data = GeoSpatialData(result;
        metadata=merge(data.metadata, Dict("analysis" => operation)),
        crs=data.crs,
        bounds=data.bounds
    )
    
    return output_data
end
```

### Pattern 3: Validation Function

```julia
function validate_[aspect](data::GeoSpatialData)::Bool
    # Check condition 1
    if !condition_1(data)
        @warn "Validation failed: [description]"
        return false
    end
    
    # Check condition 2
    if !condition_2(data)
        @warn "Validation failed: [description]"
        return false
    end
    
    @info "Validation passed"
    return true
end
```

### Pattern 4: Caching Wrapper

```julia
function ingest_with_cache(engine, source_name; kwargs...)
    cache_key = "$(source_name)_$(hash(kwargs))"
    
    # Check cache
    if engine.config.cache_enabled
        cached = get(engine.data_cache, cache_key, nothing)
        if !isnothing(cached)
            @debug "Returning cached data"
            return cached
        end
    end
    
    # Fetch fresh data
    data = fetch_actual_data(source_name; kwargs...)
    
    # Cache result
    if engine.config.cache_enabled
        engine.data_cache[cache_key] = data
    end
    
    return data
end
```

---

## Code Generation Guidelines

### For Copilot to Generate Good Code

#### 1. **Provide Clear Context**
```julia
# ✅ GOOD: Clear context for Copilot
"""
    fetch_water_quality(source::DataSource, site_id::String)::GeoSpatialData

Fetch water quality measurements from USGS NWIS service.
API: https://waterdata.usgs.gov/nwis/qw
Response fields: site_no, sample_dt, parm_cd, result_va
"""

# ❌ BAD: Vague context
function fetch_data(s, x)
    # Get water stuff
end
```

#### 2. **Use Explicit Type Signatures**
```julia
# ✅ GOOD
function process(data::GeoSpatialData, distance::Float64; units::String="meters")::GeoSpatialData

# ❌ BAD
function process(data, distance)
```

#### 3. **Include Example Comments**
```julia
# ✅ GOOD: Copilot can follow pattern
# Example: fetch_weather_data(source, latitude=40.7, longitude=-74.0)
# Returns: GeoSpatialData with columns: lat, lon, temp, precip, timestamp

# ❌ BAD: Too vague
# Fetch weather data
```

#### 4. **Leverage Existing Patterns**
When Copilot sees similar functions, it replicates patterns:

```julia
# After implementing fetch_noaa_weather(), similar functions get suggested:
function fetch_noaa_ocean() # Copilot suggests similar structure
    @info "Fetching NOAA ocean data"
    url = "$(source.url)/ocean"
    # ... Copilot fills in similar pattern
end
```

---

## Testing Patterns

### Unit Test Template

```julia
using Test, GeoSpatialEngine

@testset "GeoSpatialEngine Tests" begin
    
    @testset "Data Ingestion" begin
        # Test 1: Basic ingestion
        @test begin
            engine = GeoSpatialAnalysisEngine()
            isnothing(engine) == false
        end
        
        # Test 2: Source registration
        @test begin
            engine = GeoSpatialAnalysisEngine()
            source = get_data_source(engine, "NOAA_Weather")
            !isnothing(source)
        end
    end
    
    @testset "Data Validation" begin
        # Test 1: Valid CRS
        @test _is_valid_crs("EPSG:4326")
        @test _is_valid_crs("EPSG:3857")
        @test !_is_valid_crs("INVALID")
        
        # Test 2: Data completeness
        @test begin
            data = GeoSpatialData(DataFrame(a=[1,2,3]))
            validate_geospatial_data(data)["valid"]
        end
    end
    
end
```

### Integration Test Template

```julia
@testset "API Integration" begin
    # Test with mock responses
    @mock HTTP.get() => return MockResponse(200, sample_data)
    
    engine = GeoSpatialAnalysisEngine()
    data = ingest_data(engine, "NOAA_Weather"; region="US")
    
    @test nrow(data.data) > 0
    @test haskey(data.metadata, "source")
end
```

---

## Documentation Standards

### Module Documentation

Every module should have:

```julia
\"\"\"
    modulename

Module description and purpose.

# Exported Functions
- [`function1`](@ref)
- [`function2`](@ref)

# Example
\`\`\`julia
using GeoSpatialEngine

# Module usage example
\`\`\`

# See Also
- Related module 1
- Related module 2
\"\"\"
```

### Function Documentation

```julia
\"\"\"
    function_name(arg1::Type1, arg2::Type2; kwarg::Type=default)::ReturnType

One-line summary of what the function does.

Longer description providing context, assumptions, and behavior details.

# Arguments
- `arg1::Type1`: Description
- `arg2::Type2`: Description  
- `kwarg::Type=default`: Optional, description

# Returns
- `ReturnType`: Description of structure and contents

# Examples
\`\`\`julia
# Example 1: Basic usage
result = function_name(arg1_value, arg2_value)

# Example 2: With kwargs
result = function_name(arg1_value, arg2_value; kwarg=custom_value)
\`\`\`

# Notes
- Important implementation details
- Performance considerations
- Known limitations

# See Also
- [`related_function`](@ref)
\"\"\"
```

---

## Common Tasks with Copilot

### Task 1: Add a New Data Source

**Step 1**: Create file with function signatures
```julia
# File: src/sources/newsource.jl
function fetch_newsource_data(source::DataSource, kwargs)::GeoSpatialData end
function fetch_newsource_timeseries(source::DataSource, kwargs)::GeoSpatialData end
```

**Step 2**: Ask Copilot with context
```
TASK: Implement NEWSOURCE API integration
API: https://api.newsource.com/geospatial
Auth: API Key in "x-api-key" header
Response: JSON with fields: {"locations": [...], "readings": [...]}

Implement fetch_newsource_data() to:
1. Build URL with query parameters from kwargs
2. Add API key header
3. Parse JSON response
4. Return GeoSpatialData with locations and readings
```

**Step 3**: Review and test generated code

### Task 2: Add a Spatial Operation

**Step 1**: Define the signature
```julia
function buffer(data::GeoSpatialData, distance::Float64; units::String="meters")::GeoSpatialData
end
```

**Step 2**: Provide Copilot context
```
TASK: Implement buffer spatial operation

Requirements:
- Uses LibGEOS.jl for geometry operations
- Preserves all non-geometry columns
- Updates metadata with operation info
- Handles unit conversion (meters/kilometers)
- Validates distance parameter

Inputs: GeoSpatialData with geometries
Output: GeoSpatialData with buffered geometries
```

**Step 3**: Let Copilot generate implementation

### Task 3: Write Tests

**Step 1**: Provide test structure
```julia
@testset "buffer() tests" begin
    # Copilot generates tests based on pattern
end
```

**Step 2**: Add first test manually
```julia
@testset "buffer() tests" begin
    data = create_test_data(10)
    result = buffer(data, 100.0)
    @test nrow(result.data) == nrow(data.data)
    
    # Copilot suggests similar tests
end
```

---

## Anti-Patterns to Avoid

### ❌ What Copilot Often Gets Wrong

1. **Forgetting error handling**
```julia
# ❌ BAD: No error handling
data = JSON3.read(response.body)

# ✅ GOOD: With error handling
try
    data = JSON3.read(response.body)
catch e
    @error "Failed to parse JSON: $e"
    return GeoSpatialData(DataFrame())
end
```

2. **Not validating external data**
```julia
# ❌ BAD: Assumes valid response
df = DataFrame(lat=data["lat"], lon=data["lon"])

# ✅ GOOD: Validates data
if !haskey(data, "lat") || !haskey(data, "lon")
    error("Response missing required fields")
end
df = DataFrame(lat=data["lat"], lon=data["lon"])
```

3. **Forgetting CRS specification**
```julia
# ❌ BAD: No CRS
return GeoSpatialData(df; metadata=meta)

# ✅ GOOD: Always specify CRS
return GeoSpatialData(df; metadata=meta, crs="EPSG:4326")
```

4. **Not handling empty/null data**
```julia
# ❌ BAD: Doesn't handle empty results
for row in data
    # Process row
end

# ✅ GOOD: Checks for empty data
if length(data) == 0
    @warn "No data returned"
    return GeoSpatialData(DataFrame())
end
for row in data
    # Process row
end
```

---

## Copilot-Friendly Development Workflow

### Phase 1: Structure & Types (Manual)
Write all types and function signatures first.  
Copilot then knows what to generate.

### Phase 2: Implementation (Copilot + Manual)
- Copilot generates function bodies
- Review for correctness
- Add error handling manually
- Add logging manually

### Phase 3: Testing (Copilot + Manual)
- Copilot generates test structure
- Manually add edge cases
- Manually add performance tests
- Review test coverage

### Phase 4: Documentation (Copilot + Manual)
- Copilot fills in docstring structure
- Manually verify accuracy
- Manually add examples
- Manually add cross-references

---

## Copilot Prompt Engineering Tips

### Tip 1: Show Examples
Copilot learns from nearby code.
```julia
# Define similar function first
function fetch_x(source::DataSource) ...
    # Copilot suggests similar structure for fetch_y()
end

function fetch_y(source::DataSource)
    # Copilot suggests similar code here
end
```

### Tip 2: Use Context Comments
```julia
# Copilot reads ALL comments in vicinity
# Building NOAA API request: GET /points/{lat},{lon}
# Auth: None required
# Returns: JSON with properties.forecast URL
function fetch_noaa_forecast(lat, lon)
    # Copilot knows context for implementation
end
```

### Tip 3: Incrementalstub filling
```julia
function fetch_data(url, params)
    # Request building
    request_url = string(url, "?", 
                        # Copilot completes param joining
    
    # Response handling
    response = HTTP.get(request_url)
    # Copilot suggests error checking
    
    # Data extraction
    data = JSON3.read(response.body)
    # Copilot suggests required field validation
    
    return data
end
```

### Tip 4: Reference existing functions
```julia
# Copilot understands function relationships
# Similar to: fetch_noaa_weather()
# But for: USGS water data
function fetch_usgs_water(source::DataSource, kwargs)
    # Copilot suggests pattern from noaa function
end
```

---

## Quality Checks for Copilot-Generated Code

Before accepting Copilot suggestions:

- [ ] Type signatures match documentation
- [ ] Error handling is present
- [ ] CRS/metadata preserved/updated
- [ ] No hardcoded values (use configuration)
- [ ] Logging at appropriate levels
- [ ] No unused imports
- [ ] Performance acceptable for expected data sizes
- [ ] Docstring examples actually work
- [ ] No silent failures
- [ ] Thread-safe if used in parallel

---

## Integration with GitHub Actions

### Automated Checks on PR
When Copilot code is pushed:
1. Unit tests run (must pass)
2. Type checking runs (must pass)
3. Code formatting checked
4. Documentation built
5. Performance benchmarks run

### Review Workflow
1. Copilot generates → pushed to branch
2. GitHub Actions tests → must pass
3. Manual code review → 2 approvals
4. Integration tests → must pass
5. Merge to main

---

## Conclusion

GeoSpatialEngine is structured to maximize Copilot effectiveness while maintaining code quality. Follow these patterns and templates for best results:

1. **Types first** - Define all structures
2. **Signatures next** - Declare function interfaces
3. **Generate with context** - Provide clear prompts
4. **Test thoroughly** - Don't skip test generation
5. **Document completely** - Keep examples up-to-date

With this approach, Copilot can accelerate development while maintaining enterprise-grade code quality.

---

**For questions or updates to this guide, please open an issue on GitHub.**
