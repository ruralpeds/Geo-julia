"""
Multi-Tenancy Support
"""

module MultiTenancy
using Dates, UUIDs

"""
    Tenant

Represents a tenant in the system
"""
struct Tenant
    id::UUID
    name::String
    domain::String
    created_at::DateTime
    max_users::Int
    storage_quota_gb::Int
    features::Vector{String}
end

"""
    create_tenant(name::String, domain::String)

Create a new tenant
"""
function create_tenant(name::String, domain::String)
    return Tenant(
        uuid4(),
        name,
        domain,
        now(),
        100,  # default max users
        1000, # default storage quota
        ["analysis", "visualization", "ml"]
    )
end

"""
    isolate_data(tenant_id::UUID, data::Dict)

Ensure data isolation per tenant
"""
function isolate_data(tenant_id::UUID, data::Dict)
    return merge(data, Dict("tenant_id" => tenant_id))
end

"""
    check_tenant_quota(tenant_id::UUID, current_usage::Int, quota::Int)

Check if tenant has exceeded quota
"""
function check_tenant_quota(tenant_id::UUID, current_usage::Int, quota::Int)
    return current_usage < quota
end

end
