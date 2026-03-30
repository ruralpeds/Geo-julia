# CLAUDE CODE SPECIFICATION: AI-Powered Analysis Assistant
# File: specs/05_ai_assistant.md

## Task
Build an AI-powered geographic analysis assistant as a Pluto.jl notebook
that uses the Anthropic API to provide natural-language interpretation of
spatial analysis results.

## Architecture
The assistant lives in notebooks/geo_assistant.jl as a reactive Pluto notebook.
It uses the HealthcareGeo.jl analysis functions to compute results and then
calls the Anthropic Claude API (via HTTP.jl) to interpret findings.

## Required Components

### 1. Analysis Runner Cell
A cell that: loads county data for a user-selected state,
runs Moran's I, LISA clustering, and E2SFCA accessibility,
stores results as reactive observables that downstream cells can use.

### 2. Anthropic API Integration Cell
```julia
function interpret_results(morans_result, lisa_result, accessibility_df,
                            state_name; api_key=ENV["ANTHROPIC_API_KEY"])
```
Build a structured prompt describing the statistical results numerically.
Include: Moran's I value, z-score, p-value, number of HH and LL clusters,
% population in access desert, mean and SD of accessibility scores.

System prompt: "You are an expert in rural health geography and spatial
epidemiology. You interpret spatial analysis results for healthcare
policymakers and rural health researchers. Your interpretations are
accurate, actionable, and accessible to non-statistician readers."

Use the claude-sonnet-4-6 model with max_tokens=1500.
Return the interpretation as a Markdown string.

### 3. Interactive Map Cell
Using WGLMakie inside Pluto, render an interactive choropleth map
of the LISA clusters. Include a county name tooltip on hover.
Allow the user to click on a county to see its data in a sidebar panel.

### 4. Policy Recommendation Cell
After the AI interpretation, a second API call generates 3-5 specific,
evidence-based policy recommendations for improving healthcare access
in the identified shortage clusters. Format as a numbered list.
Include relevant federal programs (NHSC, HPSA designation, CAH status)
that apply to the identified shortage areas.

## Error Handling
If the API call fails (network error, rate limit, invalid key):
display a friendly error message in the notebook and fall back to a
template-based interpretation using rule-based logic.

## Dependencies
Add to Project.toml: Pluto, WGLMakie, PlutoUI
The notebook must be fully reproducible: all data is downloaded
automatically via the data pipeline module.
