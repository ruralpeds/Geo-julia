# report.jl — Console output for InfectiousDisease

using Printf, Statistics

function print_sir_report(res; label::String="SIR Model")
    println("\n", "═"^58)
    println("  $(label)")
    println("═"^58)
    @printf "  β = %.4f  γ = %.4f  R₀ = %.3f\n" res.β res.γ res.R₀
    @printf "  Population: %.0f\n" res.N
    @printf "  Peak prevalence : %.2f%%  at t = %.1f\n" (res.peak_I*100) res.peak_t
    @printf "  Final attack rate: %.2f%%\n" (res.attack_rate*100)
    @printf "  Herd immunity threshold: %.1f%%\n" (herd_immunity_threshold(res.R₀)*100)
    println("═"^58)
end

function print_spatial_sir_report(res; label::String="Spatial SIR")
    println("\n", "═"^58)
    println("  $(label)  ($(res.n_patches) patches)")
    println("═"^58)
    @printf "  γ = %.4f  R₀ (global) ≈ %.3f\n" res.γ res.R₀_global
    @printf "  Peak patch: %d\n" res.peak_patch
    println("  Attack rates by patch:")
    for p in 1:res.n_patches
        @printf "    Patch %2d : %.1f%%\n" p (res.attack_rate[p]*100)
    end
    println("═"^58)
end

herd_immunity_threshold(R₀::Real) = R₀ <= 1.0 ? 0.0 : 1.0 - 1.0/R₀
