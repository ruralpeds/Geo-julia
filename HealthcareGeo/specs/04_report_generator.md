# CLAUDE CODE SPECIFICATION: Automated Rural Health Report Generator
# File: specs/04_report_generator.md

## Task
Build a command-line report generator that produces a complete rural health
geographic analysis report for a specified state. The report should be a
multi-page PDF with maps, tables, and narrative text.

## Entry Point
Create scripts/generate_report.jl with command-line interface:
  julia scripts/generate_report.jl --state ND --year 2022 --output report.pdf

## Report Sections

### Section 1: State Rural Profile
- Map: County-level RUCA classification (color by rurality tier)
- Table: Count and % of population in rural/urban by RUCA tier
- Narrative: 2-3 sentence automated summary of rural population composition

### Section 2: Healthcare Provider Supply
- Map: Primary care physicians per 100,000 population by county (choropleth)
- Map: HPSA-designated areas overlaid on county map
- Table: Top 10 most underserved counties (lowest PCP per 100k)
- Statistics: Moran's I for provider density (test for geographic clustering)

### Section 3: Spatial Accessibility Analysis
- Map: E2SFCA accessibility scores by census tract
- Map: Network-based 30-minute drive catchment areas for all hospitals
- Table: Population living > 30, 45, 60 minutes from nearest hospital
- Statistics: % rural population in access desert (accessibility score < p10)

### Section 4: Health Outcomes Geography
- Map: Age-adjusted cardiovascular mortality rate by county (CDC WONDER data)
- Map: LISA cluster map for CVD mortality
- Map: Premature death rate (YPLL < 75 per 100k, County Health Rankings)
- Statistics: Moran's I for CVD mortality; identify significant HH clusters

### Section 5: Social Determinants
- Map: Poverty rate by census tract (ACS 5-year)
- Map: Uninsurance rate by census tract
- Bivariate map: Provider density vs. poverty (2×2 grid classification)
- Correlation table: Pearson and Moran's bivariate I for SDOH vs. health outcomes

## Technical Requirements
Use CairoMakie for all maps (PDF-quality vector output).
Compose pages using the Figure layout system with multiple rows.
Use ColorBrewer-compatible color schemes throughout.
Add HRSA and Census data attribution in page footer.
Generate all maps at 300 DPI equivalent quality.
Complete report generation for a single state should run in < 5 minutes
on a modern laptop (M1/M2 Mac or equivalent).
