# src/data/classify.jl
# Rural classification logic using FORHP criteria.

"""
    classify_rural_forhp(tracts::DataFrame) -> DataFrame

Classify census tracts by rurality using the Federal Office of Rural Health
Policy (FORHP) definition.

**Required columns in `tracts`:**
- `fips`               — census tract FIPS code (String)
- `ruca_code`          — primary RUCA code (Int or Float)
- `rrs_code`           — Road Ruggedness Scale code (Int; 1–5)
- `omb_metro_type`     — `"metro"`, `"micro"`, or `"nonmetro"` (String)
- `area_sq_mi`         — land area in square miles (Float)
- `population_density` — persons per square mile (Float)

**Added column:**
- `is_rural_forhp` (Bool) — `true` if the tract meets FORHP rural criteria

**FORHP Rules (September 2025 update):**
1. All non-metropolitan counties → rural
2. Census tracts in metropolitan counties with RUCA codes 4–10 → rural
3. Large, sparse tracts in metro counties with RUCA 2–3 (≥400 sq mi AND
   ≤35 persons/sq mi) → rural
4. Rugged tracts in metro counties with RUCA 2–3 (RRS = 5 AND ≥20 sq mi) → rural
"""
function classify_rural_forhp(tracts::DataFrame)::DataFrame
    result = copy(tracts)
    result.is_rural_forhp = falses(nrow(tracts))

    for i in 1:nrow(tracts)
        r = tracts[i, :]

        # Rule 1: all non-metropolitan counties
        if r.omb_metro_type == "nonmetro"
            result.is_rural_forhp[i] = true
            continue
        end

        # Remaining rules apply only to metro counties
        r.omb_metro_type == "metro" || continue

        # Rule 2: RUCA 4–10 in metro counties
        if r.ruca_code >= 4
            result.is_rural_forhp[i] = true
            continue
        end

        # Rule 3: Large, sparse tracts with RUCA 2–3
        if r.ruca_code in (2, 3) &&
           r.area_sq_mi >= 400.0 &&
           r.population_density <= 35.0
            result.is_rural_forhp[i] = true
            continue
        end

        # Rule 4: Rugged tracts with RUCA 2–3 (RRS = 5, area ≥ 20 sq mi)
        if r.ruca_code in (2, 3) &&
           r.rrs_code == 5 &&
           r.area_sq_mi >= 20.0
            result.is_rural_forhp[i] = true
        end
    end

    return result
end
