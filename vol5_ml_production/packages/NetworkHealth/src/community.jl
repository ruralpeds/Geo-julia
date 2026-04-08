# community.jl — Community detection for provider referral networks
# Chapter 36.3

"""
    label_propagation(g; max_iter=100, rng=GLOBAL_RNG) -> Vector{Int}

Raghavan et al. (2007) Label Propagation Algorithm.
Each node adopts the most frequent label among its neighbors.
Fast O(E) algorithm; non-deterministic.

Returns community labels (1-indexed integers).
"""
function label_propagation(g::ReferralNetwork;
                            max_iter::Int = 100,
                            rng::AbstractRNG = Random.GLOBAL_RNG)
    n      = g.n
    labels = collect(1:n)
    order  = randperm(rng, n)

    for _ in 1:max_iter
        changed = false
        shuffle!(rng, order)
        for v in order
            nbrs = union(g.adj[v, :].nzind, g.adj[:, v].nzind)
            isempty(nbrs) && continue
            # Count weighted label frequency
            label_count = Dict{Int,Float64}()
            for u in nbrs
                wt = g.adj[v,u] + g.adj[u,v]
                label_count[labels[u]] = get(label_count, labels[u], 0.0) + max(wt, 1.0)
            end
            best = argmax(label_count)
            if labels[v] != best
                labels[v] = best
                changed   = true
            end
        end
        !changed && break
    end

    # Re-index communities to 1..K
    unique_labels = sort(unique(labels))
    label_map = Dict(l => i for (i, l) in enumerate(unique_labels))
    [label_map[l] for l in labels]
end

"""
    louvain_communities(g; resolution=1.0, max_iter=100, rng=GLOBAL_RNG) -> Vector{Int}

Blondel et al. (2008) Louvain modularity optimisation.

Phase 1: Greedy modularity gain — move each node to the community that maximises ΔQ.
Phase 2: Contract the graph (communities → super-nodes), repeat.

Modularity: Q = (1/2m) Σ_{ij} [A_{ij} - k_i·k_j/(2m)] δ(c_i, c_j)

Returns community labels (1-indexed).
"""
function louvain_communities(g::ReferralNetwork;
                              resolution::Float64 = 1.0,
                              max_iter::Int = 100,
                              rng::AbstractRNG = Random.GLOBAL_RNG)
    n        = g.n
    n == 0   && return Int[]
    A        = g.adj + g.adj'      # symmetrise for modularity
    k        = vec(sum(A; dims=2)) # weighted degree
    m2       = sum(k)              # 2m (twice total edge weight)
    m2 < 1e-12 && return collect(1:n)

    comm = collect(1:n)            # each node starts in its own community

    for pass in 1:max_iter
        moved = false
        for v in randperm(rng, n)
            curr_c   = comm[v]
            # Compute ΔQ for moving v to each neighbouring community
            nbr_comms = Dict{Int,Float64}()  # community => Σ w(v,u) for u in comm
            for u in A[v, :].nzind
                c = comm[u]
                nbr_comms[c] = get(nbr_comms, c, 0.0) + A[v, u]
            end

            # Sum of degrees in each community
            comm_k = Dict{Int,Float64}()
            for u in 1:n
                c = comm[u]
                comm_k[c] = get(comm_k, c, 0.0) + k[u]
            end

            k_v    = k[v]
            w_curr = get(nbr_comms, curr_c, 0.0)   # weight to current community

            best_c  = curr_c
            best_dQ = 0.0
            for (c, w_to_c) in nbr_comms
                c == curr_c && continue
                K_c  = get(comm_k, c, 0.0)
                K_cc = get(comm_k, curr_c, 0.0)
                # ΔQ = [w_to_c - k_v·K_c·resolution/m2] - [w_curr - k_v·(K_cc-k_v)·resolution/m2]
                dQ = (w_to_c  - resolution * k_v * K_c  / m2) -
                     (w_curr  - resolution * k_v * (K_cc - k_v) / m2)
                if dQ > best_dQ
                    best_dQ = dQ
                    best_c  = c
                end
            end

            if best_c != curr_c
                comm[v] = best_c
                moved   = true
            end
        end
        !moved && break
    end

    # Re-index
    unique_labels = sort(unique(comm))
    label_map     = Dict(l => i for (i, l) in enumerate(unique_labels))
    [label_map[l] for l in comm]
end
