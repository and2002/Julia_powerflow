using Graphs, GraphPlot, Plots

function guided_grid_layout_with_downward_start(
    vertex_names::Vector{String},
    edges::Vector{Tuple{String,String}},
    x_spring::Vector,
    y_spring::Vector;
    start_vertex::Union{String, Nothing} = nothing
)
    name_to_index = Dict(v => i for (i, v) in enumerate(vertex_names))
    index_to_name = Dict(i => v for (v, i) in name_to_index)

    n = length(vertex_names)
    pos = Dict{String, Tuple{Int, Int}}()
    occupied = Set{Tuple{Int, Int}}()
    placed = Set{String}()
    adj = Dict(v => String[] for v in vertex_names)

    for (u, v) in edges
        push!(adj[u], v)
        push!(adj[v], u)
    end

    # 8 compass directions: (dx, dy) and their angles

    directions = [
        (1, 0), (1, 1), (0, 1), (-1, 1),
        (-1, 0), (-1, -1), (0, -1), (1, -1)
    ]

    dir_angles = [atan(d[2], d[1]) for d in directions]

    # Step 1: Choose starting vertex
    root = start_vertex === nothing ? vertex_names[1] : start_vertex
    @assert haskey(adj, root) "Starting vertex '$root' not found in graph."

    pos[root] = (0, 0)
    push!(occupied, (0, 0))
    push!(placed, root)

    # Step 2: Select closest neighbor and place it directly below
    i_root = name_to_index[root]
    root_x, root_y = x_spring[i_root], y_spring[i_root]
    best_neighbor = nothing
    best_dist = Inf

    for neighbor in adj[root]
        i_n = name_to_index[neighbor]
        dx = x_spring[i_n] - root_x
        dy = y_spring[i_n] - root_y
        dist2 = dx^2 + dy^2
        if dist2 < best_dist
            best_dist = dist2
            best_neighbor = neighbor
        end
    end

    if best_neighbor !== nothing
        down_pos = (0, 1)
        pos[best_neighbor] = down_pos
        push!(occupied, down_pos)
        push!(placed, best_neighbor)
        queue = [root, best_neighbor]
    else
        queue = [root]
    end

    current_last_layer = 0
    # Step 3: Place rest using guided BFS
    while !isempty(queue)
        current = popfirst!(queue)
        i_curr = name_to_index[current]
        (x0, y0) = pos[current]

        for neighbor in adj[current]
            if neighbor in placed
                continue
            end

            i_neigh = name_to_index[neighbor]
            dx_spring = x_spring[i_neigh] - x_spring[i_curr]
            dy_spring = y_spring[i_neigh] - y_spring[i_curr]
            angle = atan(dy_spring, dx_spring)

            best_dir = nothing
            best_angle_diff = Inf
            for (j, θ_dir) in enumerate(dir_angles)
                diff = abs(mod(θ_dir - angle + π, 2π) - π)
                candidate_pos = (x0 + directions[j][1], y0 + directions[j][2])
                if candidate_pos ∉ occupied && candidate_pos[2] >= current_last_layer && diff < best_angle_diff
                    best_angle_diff = diff
                    best_dir = directions[j]
                    current_last_layer = y0 + best_dir[2]
                end
            end

            if best_dir !== nothing
                candidate = (x0 + best_dir[1], y0 + best_dir[2])
                pos[neighbor] = candidate
                push!(occupied, candidate)
                push!(placed, neighbor)
                push!(queue, neighbor)
                current_last_layer = y0 + best_dir[2]
            end
        end
    end

    return pos
end

# Define vertices and edges by name
vertex_names = ["A", "B", "C", "D", "E"]
name_to_index = Dict(name => i for (i, name) in enumerate(vertex_names))

edges = [("A", "B"), ("B", "C"),("A", "D"), ("C", "E")]

# Create a Graphs.Graph with appropriate size
g = Graph(length(vertex_names))
for (u, v) in edges
    add_edge!(g, name_to_index[u], name_to_index[v])
end

# Get layout coordinates
x_pos, y_pos = spring_layout(g, C=1.0, MAXITER=500)  # Stronger repulsion, more iterations

# Map back to vertex names
#=
coord_dict = Dict(name => (coords[1, i], coords[2, i]) for (i, name) in enumerate(vertex_names))
println(coord_dict)
=#
#Optional: plot
gplot(g, x_pos, y_pos, nodelabel=vertex_names)

x_spring, y_spring = spring_layout(g)

# Apply guided layout
layout = guided_grid_layout_with_downward_start(vertex_names, edges, x_spring, y_spring; start_vertex="D")

# Convert to x/y vectors
x_grid = [layout[v][1] for v in vertex_names]
y_grid = [layout[v][2] for v in vertex_names]

# Plot
gplot(g, x_grid, y_grid, nodelabel=vertex_names)
