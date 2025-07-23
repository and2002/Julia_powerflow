using PowerSystems
using GLMakie
using Graphs
using GraphPlot

const BUS_HALFSPAN = 0.6   # so total length ≈1.2 units; tweak as you like

function get_unique_zones(sys::System)
    buses = get_components(Bus, sys)
    zones = Set{Int}()

    for b in buses
        name = b.name
        # Extract first 1–2 digits as integer zone
        zone = parse(Int, length(name) ≥ 2 ? name[1:2] : name[1])
        push!(zones, zone)
    end

    return sort(collect(zones))
end

function extract_zone_data(sys::System, zone_code::Int)
    all_buses = get_components(Bus, sys)
    zone_buses = Dict{String, Bus}()

    for b in all_buses
        name = b.name
        zone = parse(Int, length(name) ≥ 2 ? name[1:2] : name[1])
        if zone == zone_code
            zone_buses[name] = b
        end
    end

    bus_names = keys(zone_buses)
    branches = get_components(ACBranch, sys)
    zone_branches = [
        br for br in branches if 
        get_name(get_from(get_arc(br))) in bus_names &&
        get_name(get_to(get_arc(br))) in bus_names
    ]

    # === Identify the most HV bus ===
    hv_bus = argmax([get_base_voltage(zone_buses[name]) for name in bus_names])
    hv_bus_name = collect(bus_names)[hv_bus]

    return Dict(
        :buses => zone_buses,
        :branches => zone_branches,
        :start => hv_bus_name
    )
end

function plot_zone!(ax, zone_data, x0::Float64, y0::Float64)


    buses = zone_data[:buses]
    branches = zone_data[:branches]
    vertex_names = collect(keys(buses))
    start_vertex = zone_data[:start]  # most HV bus passed in zone_data

    n = length(vertex_names)
    name_to_index = Dict(name => i for (i, name) in enumerate(vertex_names))

    # Build graph + edge list
    g = Graph(n)
    edges = Tuple{String, String}[]
    for br in branches
        f = get_name(get_from(get_arc(br)))
        t = get_name(get_to(get_arc(br)))
        add_edge!(g, name_to_index[f], name_to_index[t])
        push!(edges, (f, t))
    end

    # Spring layout (guidance)
    x_spring, y_spring = spring_layout(g, C=1.0, MAXITER=500)

    # Guided grid layout, starting at HV bus
    layout = guided_grid_layout_with_downward_start(
        vertex_names, edges, x_spring, y_spring;
        start_vertex=start_vertex
    )

    # Plot
    scale = 2.0
    bus_pos = Dict{String, Tuple{Float64, Float64}}()
    drawn_pairs = Set{Tuple{String, String}}()
    x_vals = Float64[]; y_vals = Float64[]

    for b in vertex_names
        (ix, iy) = layout[b]
        x = x0 + ix * scale
        y = y0 - iy * scale

        # HORIZONTAL BUS BAR
        lines!(ax, [x - BUS_HALFSPAN, x + BUS_HALFSPAN], [y, y], linewidth=6, color=:blue)
        text!(ax, b, position=(x - BUS_HALFSPAN - 0.3, y), align=(:right, :center), fontsize=10)

        bus_pos[b] = (x, y)
        push!(x_vals, x); push!(y_vals, y)
    end

    # Intra-zone branches
    for (f, t) in edges
        x1, y1 = bus_pos[f]; x2, y2 = bus_pos[t]
        draw_branch_circuit_style!(ax, (x1, y1), (x2, y2), linewidth=3, color=:black)
        push!(drawn_pairs, (min(f, t), max(f, t)))
    end

    # Bounding box (top-right)
    x1 = maximum(x_vals) + BUS_HALFSPAN
    y1 = maximum(y_vals) + 0.5
    return bus_pos, drawn_pairs, (x1, y1)
end

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

function draw_branch_circuit_style!(ax, p1::Tuple{Float64, Float64}, p2::Tuple{Float64, Float64}; kwargs...)
    x1, y1 = p1
    x2, y2 = p2

    dx, dy = x2 - x1, y2 - y1
    θ = atan(dy, dx)

    # --- Compute x-offset based on verticality ---
    offset1 = BUS_HALFSPAN * cos(θ)
    offset2 = -BUS_HALFSPAN * cos(θ)

    # --- Compute vertical wire length based on horizontality ---
    vertical_length = 0.0
    if abs(sin(θ)) != 0
        vertical_length = BUS_HALFSPAN * (abs(sin(θ)) + 0.1) # base + slope-dependent
    else
        vertical_length = BUS_HALFSPAN * 0.4
    end
    

    # Apply offsets to bus connection x-coordinates
    x1_conn = x1 + offset1
    x2_conn = x2 + offset2

    # Compute intermediate Y level
    ym = (y1 + y2) / 2
    ym1 = y1 > y2 ? y1 - vertical_length : y1 + vertical_length
    ym2 = y2 > y1 ? y2 - vertical_length : y2 + vertical_length
    ym_mid = (ym1 + ym2) / 2  # smooth midpoint

    # Draw three segments
    lines!(ax, [x1_conn, x1_conn], [y1, ym1]; kwargs...)          # from bus1
    lines!(ax, [x1_conn, x2_conn], [ym1, ym2]; kwargs...)         # horizontal
    lines!(ax, [x2_conn, x2_conn], [ym2, y2]; kwargs...)          # to bus2
end

function plot_interzone_connections!(ax, sys::System, bus_pos::Dict{String, Tuple{Float64, Float64}}, already_drawn::Set{Tuple{String, String}})
    branches = get_components(ACBranch, sys)

    for br in branches
        f = get_name(get_from(get_arc(br)))
        t = get_name(get_to(get_arc(br)))

        key = (min(f, t), max(f, t))

        if haskey(bus_pos, f) && haskey(bus_pos, t) && !(key in already_drawn)
            x1, y1 = bus_pos[f]
            x2, y2 = bus_pos[t]
            draw_branch_circuit_style!(ax, (x1, y1), (x2, y2), linewidth=2, color=:red, linestyle=:dot)
        end
    end
end

function draw_full_network(sys::System)

    fig = Figure(resolution=(1200, 600))
    ax = Axis(fig[1, 1], title="Power System by Zones", aspect=1)
    hidedecorations!(ax); hidespines!(ax)

    zones = get_unique_zones(sys)
    total_bus_pos = Dict{String, Tuple{Float64, Float64}}()
    drawn_branches = Set{Tuple{String, String}}()

    x0, y0 = 0.0, 0.0  # initial position

    for zone in zones
        zone_data = extract_zone_data(sys, zone)
        bus_pos, drawn, (_x1, y_top) = plot_zone!(ax, zone_data, x0, y0)
        
        # Optional: label the zone
        text!(ax, "Zone $zone", position=(x0, y_top + 1.5), align=(:center, :bottom), fontsize=12)

        merge!(total_bus_pos, bus_pos)
        union!(drawn_branches, drawn)

        # Move right for next zone
        x0 += 10.0
    end

    plot_interzone_connections!(ax, sys, total_bus_pos, drawn_branches)

    return fig
end

adress_of_system = joinpath(@__DIR__, "test_system.json") # adress of our system
sys = System(adress_of_system)
fig = draw_full_network(sys)
display(fig)