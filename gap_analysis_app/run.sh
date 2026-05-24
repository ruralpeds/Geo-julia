#!/bin/bash
# Launch the Geo-Julia Gap Analysis Dashboard
# Requires Julia 1.10+ with Genie/Stipple packages

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Geo-Julia Gap Analysis Dashboard ==="
echo "Installing dependencies..."

cd "$SCRIPT_DIR"

julia --project=. -e '
    using Pkg
    Pkg.instantiate()
    println("Dependencies installed. Starting server...")
    include("src/app.jl")
'
