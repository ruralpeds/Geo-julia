# PointPatterns.jl

Point pattern analysis for spatial epidemiology

## Purpose

Provides specialized functionality for the RuralHealthPlatform.jl system.

## Key Features

- Typed exception handling via RuralCore
- Audit logging for regulatory compliance
- Integration with RuralCore domain types
- Test coverage with error and audit tests

## Installation

```julia
using Pkg
Pkg.activate("packages/PointPatterns")
Pkg.instantiate()
```

## Basic Usage

```julia
using PointPatterns
using RuralCore

# Use typed exceptions from RuralCore
try
    # Your computation
catch e
    if e isa DataValidationError
        # Handle validation error
    elseif e isa CalculationError
        # Handle calculation error
    end
end

# Wrap critical calculations in audit logging
result = @audited_calculation my_critical_function(data)
```

## Testing

```bash
julia --project=packages/PointPatterns -e 'using Pkg; Pkg.test()'
```

## Error Handling

All public functions validate inputs and throw typed exceptions from RuralCore:
- `DataValidationError` — invalid input data
- `DomainValidationError` — business rule violations
- `CalculationError` — computation failures
- `ConfigurationError` — missing configuration

See [CLAUDE.md](../../CLAUDE.md) for error handling patterns.

## Audit Logging

Critical functions can be wrapped with `@audited_calculation` for full provenance tracking:

```julia
# At call site (not in function definition)
result = @audited_calculation my_function(input)
```

This records timestamp, input/output hashes, elapsed time, Julia version, and git SHA.

## Documentation

- [CLAUDE.md](../../CLAUDE.md) — Project standards and patterns
- [test/error_tests.jl](test/error_tests.jl) — Error handling examples
- [test/audit_tests.jl](test/audit_tests.jl) — Audit logging examples

## Dependencies

- Julia 1.12+
- RuralCore (path dependency)
