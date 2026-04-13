"""
Role-Based Access Control
"""

module RBAC

"""
    Role

Define user roles
"""
struct Role
    name::String
    permissions::Set{String}
    description::String
end

# Predefined roles
const ROLES = Dict(
    "admin" => Role("admin", Set(["all"]), "Administrator"),
    "analyst" => Role("analyst", Set(["read", "analyze", "visualize"]), "Data Analyst"),
    "viewer" => Role("viewer", Set(["read"]), "Viewer"),
    "developer" => Role("developer", Set(["read", "write", "debug"]), "Developer"),
    "operator" => Role("operator", Set(["manage", "monitor", "deploy"]), "Operator")
)

"""
    check_permission(user_roles::Vector{String}, required_permission::String)

Check if user has required permission
"""
function check_permission(user_roles::Vector{String}, required_permission::String)
    for role_name in user_roles
        if haskey(ROLES, role_name)
            role = ROLES[role_name]
            if "all" in role.permissions || required_permission in role.permissions
                return true
            end
        end
    end
    return false
end

end
