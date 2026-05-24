# kernels.jl — Covariance kernels for spatial GP regression
# Chapter 44.1
#
# Wrapper structs around KernelFunctions.jl for API compatibility.

abstract type GPKernel end

"""
    SquaredExponential(σ², ℓ)

RBF / Squared Exponential kernel: k(r) = σ²·exp(-r²/2ℓ²)
Infinitely differentiable — smooth spatial fields.
`σ²` = signal variance, `ℓ` = length-scale (km for geographic use).

Backed by `KernelFunctions.SqExponentialKernel()`.
"""
struct SquaredExponential <: GPKernel
    σ²::Float64
    ℓ ::Float64
end
SquaredExponential(; σ²=1.0, ℓ=1.0) = SquaredExponential(σ², ℓ)

(k::SquaredExponential)(r) = k.σ² * exp(-r^2 / (2k.ℓ^2))
param_names(::SquaredExponential) = ["log_σ²", "log_ℓ"]
get_params(k::SquaredExponential) = [log(k.σ²), log(k.ℓ)]
set_params(::SquaredExponential, θ) = SquaredExponential(exp(θ[1]), exp(θ[2]))

"""Return the corresponding KernelFunctions.jl kernel."""
function _to_kf_kernel(k::SquaredExponential)
    k.σ² * KernelFunctions.transform(KernelFunctions.SqExponentialKernel(), 1.0 / k.ℓ)
end

"""
    Matern32(σ², ℓ)

Matérn 3/2 kernel: k(r) = σ²(1 + √3r/ℓ)exp(-√3r/ℓ)
Once-differentiable — rougher spatial fields. Recommended for healthcare access.

Backed by `KernelFunctions.Matern32Kernel()`.
"""
struct Matern32 <: GPKernel
    σ²::Float64
    ℓ ::Float64
end
Matern32(; σ²=1.0, ℓ=1.0) = Matern32(σ², ℓ)

function (k::Matern32)(r)
    u = sqrt(3) * abs(r) / k.ℓ
    k.σ² * (1 + u) * exp(-u)
end
param_names(::Matern32) = ["log_σ²", "log_ℓ"]
get_params(k::Matern32) = [log(k.σ²), log(k.ℓ)]
set_params(::Matern32, θ) = Matern32(exp(θ[1]), exp(θ[2]))

function _to_kf_kernel(k::Matern32)
    k.σ² * KernelFunctions.transform(KernelFunctions.Matern32Kernel(), 1.0 / k.ℓ)
end

"""
    Matern52(σ², ℓ)

Matérn 5/2 kernel: k(r) = σ²(1 + √5r/ℓ + 5r²/3ℓ²)exp(-√5r/ℓ)
Twice-differentiable. Good balance between SE and Matérn 3/2.

Backed by `KernelFunctions.Matern52Kernel()`.
"""
struct Matern52 <: GPKernel
    σ²::Float64
    ℓ ::Float64
end
Matern52(; σ²=1.0, ℓ=1.0) = Matern52(σ², ℓ)

function (k::Matern52)(r)
    u = sqrt(5) * abs(r) / k.ℓ
    k.σ² * (1 + u + u^2/3) * exp(-u)
end
param_names(::Matern52) = ["log_σ²", "log_ℓ"]
get_params(k::Matern52) = [log(k.σ²), log(k.ℓ)]
set_params(::Matern52, θ) = Matern52(exp(θ[1]), exp(θ[2]))

function _to_kf_kernel(k::Matern52)
    k.σ² * KernelFunctions.transform(KernelFunctions.Matern52Kernel(), 1.0 / k.ℓ)
end

"""
    RationalQuadratic(σ², ℓ, α)

Rational Quadratic kernel: k(r) = σ²(1 + r²/2αℓ²)^(-α)
Scale mixture of SE kernels. `α` → ∞ recovers SE.
"""
struct RationalQuadratic <: GPKernel
    σ²::Float64; ℓ::Float64; α::Float64
end
RationalQuadratic(; σ²=1.0, ℓ=1.0, α=1.0) = RationalQuadratic(σ², ℓ, α)

(k::RationalQuadratic)(r) = k.σ² * (1 + r^2 / (2k.α * k.ℓ^2))^(-k.α)
param_names(::RationalQuadratic) = ["log_σ²", "log_ℓ", "log_α"]
get_params(k::RationalQuadratic) = [log(k.σ²), log(k.ℓ), log(k.α)]
set_params(::RationalQuadratic, θ) = RationalQuadratic(exp(θ[1]), exp(θ[2]), exp(θ[3]))

function _to_kf_kernel(k::RationalQuadratic)
    k.σ² * KernelFunctions.transform(KernelFunctions.RationalQuadraticKernel(α=k.α), 1.0 / k.ℓ)
end

"""
    OrnsteinUhlenbeck(σ², ℓ)

Matérn 1/2 / Ornstein-Uhlenbeck kernel: k(r) = σ²·exp(-r/ℓ)
Not differentiable — appropriate for very rough or non-stationary fields.
"""
struct OrnsteinUhlenbeck <: GPKernel
    σ²::Float64; ℓ::Float64
end
OrnsteinUhlenbeck(; σ²=1.0, ℓ=1.0) = OrnsteinUhlenbeck(σ², ℓ)

(k::OrnsteinUhlenbeck)(r) = k.σ² * exp(-abs(r) / k.ℓ)
param_names(::OrnsteinUhlenbeck) = ["log_σ²", "log_ℓ"]
get_params(k::OrnsteinUhlenbeck) = [log(k.σ²), log(k.ℓ)]
set_params(::OrnsteinUhlenbeck, θ) = OrnsteinUhlenbeck(exp(θ[1]), exp(θ[2]))

function _to_kf_kernel(k::OrnsteinUhlenbeck)
    k.σ² * KernelFunctions.transform(KernelFunctions.ExponentialKernel(), 1.0 / k.ℓ)
end

"""
    CompositeKernel

Sum or product of two kernels.
E.g., `CompositeKernel(Matern32(), SquaredExponential(), :sum)` models
slow + fast spatial variation simultaneously.
"""
struct CompositeKernel <: GPKernel
    k1  ::GPKernel
    k2  ::GPKernel
    op  ::Symbol  # :sum or :product
end

function (k::CompositeKernel)(r)
    k.op == :sum     ? k.k1(r) + k.k2(r) :
    k.op == :product ? k.k1(r) * k.k2(r) : k.k1(r) + k.k2(r)
end

"""
    kernel_matrix(k, X1, X2; dist_fn) -> Matrix{Float64}

Compute n₁ × n₂ kernel matrix K where K[i,j] = k(dist(X1[i,:], X2[j,:])).
"""
function kernel_matrix(k::GPKernel,
                        X1::AbstractMatrix,
                        X2::AbstractMatrix;
                        dist_fn::Function = (a,b) -> norm(a .- b))
    n1, n2 = size(X1,1), size(X2,1)
    K = zeros(n1, n2)
    for j in 1:n2, i in 1:n1
        K[i,j] = k(dist_fn(X1[i,:], X2[j,:]))
    end
    K
end

"""
    haversine_dist_deg(a, b) -> Float64

Haversine distance in km between two [lat, lon] points in degrees.
Use as `dist_fn` for geographic GP kernels.
"""
function haversine_dist_deg(a::AbstractVector, b::AbstractVector)::Float64
    φ1, φ2 = deg2rad(a[1]), deg2rad(b[1])
    Δφ = φ2 - φ1
    Δλ = deg2rad(b[2] - a[2])
    h  = sin(Δφ/2)^2 + cos(φ1)*cos(φ2)*sin(Δλ/2)^2
    2.0 * 6371.0 * asin(sqrt(h))
end
