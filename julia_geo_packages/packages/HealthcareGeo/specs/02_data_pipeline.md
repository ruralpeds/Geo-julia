# CLAUDE CODE SPECIFICATION: HRSA and Census Data Pipeline
# File: specs/02_data_pipeline.md

## Task
Implement src/data/download.jl within the HealthcareGeo package.
This module automates downloading and caching of data from HRSA and
the U.S. Census Bureau.

## Functions to Implement

### download_tiger_counties(year; force_refresh=false)
Download U.S. county TIGER/Line shapefile for the given year.
Cache in data/raw/tiger/. Return path to local .shp file.
URL pattern: https://www2.census.gov/geo/tiger/TIGER{year}/COUNTY/
             tl_{year}_us_county.zip

### download_ruca_codes(; force_refresh=false)
Download 2020 RUCA codes from USDA ERS.
URL: https://www.ers.usda.gov/webdocs/DataFiles/53241/
     ruca2010revised.xlsx
Parse XLSX, return DataFrame with columns: fips_tract, ruca_primary,
ruca_secondary, state_fips, county_fips.
Use the XLSX.jl package.

### download_hpsa_shapefile(; force_refresh=false)
Download current HPSA shapefile from HRSA data portal.
URL: https://data.hrsa.gov/DataDownload/DD_Files/
     BCD_HPSA_FCT_DET_PC.xlsx
Note: HRSA provides HPSA data as Excel; convert to spatial DataFrame.
Geocode using lat/lon columns (HPS_LAT, HPS_LON) present in the file.

### fetch_acs_insurance_coverage(state_fips, year=2022)
Fetch uninsurance rates by census tract from Census ACS 5-year estimates.
Variables: B27001_001E (total), B27001_017E, B27001_033E (uninsured groups)
Use Census API key from ENV["CENSUS_API_KEY"] or warn if absent.
Return DataFrame with columns: geoid, total_pop, uninsured_n, uninsured_pct

### load_ahrf(filepath)
Load Area Health Resources Files SAS transport file.
Require ReadStatTables.jl. Return DataFrame selecting:
county_fips (F11), active_pcp_per_100k (F1522086),
rucc (F1522166), pct_poverty (F1306105), median_income (F0453053),
total_population (F0453048).

## Error Handling
All download functions should: check for network availability before
attempting download; provide informative error messages with download URL
if network fails; validate file integrity after download (check file size > 0,
attempt to parse the first row).

## Caching Strategy
Use a data/raw/ directory relative to the project root.
Create subdirectories: tiger/, hrsa/, census/, usda/.
Add a manifest.json in each subdirectory recording download date and URL.
force_refresh=false skips download if cached file exists and is < 365 days old.
