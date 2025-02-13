using CSV, DataFrames, Graphs, GraphPlot, Colors, LinearAlgebra, Random, Compose

# Load CSV file
file_path = joinpath(@__DIR__, "Network_matrix.csv")
df = CSV.read(file_path, DataFrame, header=true)  # No header

# Define column indices: [Zone_Name, Zone_Number, Line_Number, Start_Zone, End_Zone, Edge_Length, Active]
column_indices = [1, 2, 3, 4, 5, 6, 7]  

# Extract necessary columns
Zone_Name = df[!, column_indices[1]]
Zone_Number = df[!, column_indices[2]]
Line_Number = df[!, column_indices[3]]
Start_Zone = df[!, column_indices[4]]
End_Zone = df[!, column_indices[5]]
Edge_Length = df[!, column_indices[6]]
Active = df[!, column_indices[7]]  # 1 = Active, 0 = Ignore

# Convert Zone_Number to integers
strip_first_char(s) = parse(Int, s[2:end])  
Zone_Number = strip_first_char.(Zone_Number)

# **Step 1: Detect All Unique Zones from Active Edges**
edges = [(Start_Zone[i], End_Zone[i]) for i in 1:length(Start_Zone) if Active[i] > 0]
edge_lengths = [Edge_Length[i] for i in 1:length(Start_Zone) if Active[i] > 0]

# **Get unique nodes that appear in edges**
connection_zones = unique(vcat([e[1] for e in edges], [e[2] for e in edges]))
println(connection_zones)
# **Step 2: Create a Mapping for Filtered Nodes**
node_index = Dict(n => i for (i, n) in enumerate(connection_zones))

# **Step 3: Rebuild Graph with Only Connected Nodes**
g_filtered = SimpleDiGraph(length(connection_zones))
filtered_edges = [(node_index[e[1]], node_index[e[2]]) for e in edges]

for e in filtered_edges
    add_edge!(g_filtered, e[1], e[2])
end

# **Fix Zone Labels**
zone_name_dict = Dict(Zone_Number[i] => Zone_Name[i] for i in 1:length(Zone_Name))
node_labels = [get(zone_name_dict, connection_zones[i], string(connection_zones[i])) for i in 1:length(connection_zones)]
node_labels = string.(node_labels)

# **Step 4: Check for Empty Graph Before Layout**
if nv(g_filtered) > 0
    x_pos, y_pos = spring_layout(g_filtered, C=5.0, MAXITER=500)
else
    println("Warning: The graph is empty! No connected nodes remain after filtering.")
    return  # Stop execution since there's nothing to plot
end

# **Step 6: Plot the Graph**
gplot(g_filtered, 
    x_pos, y_pos,
    nodelabel=node_labels,  
    nodefillc=[RGBA(0.4, 0.6, 0.8, 0.7) for _ in 1:nv(g_filtered)],  
    edgestrokec=[RGB(0, 0, 0)],  
    edgelabel=edge_lengths,  
    plot_size=(12cm, 12cm),  
    nodelabelsize=12,  
    edgelabelsize=10,  
    nodelabeldist=2.5,
    edgelabeldistx=0.2,  
    edgelabeldisty=0.2,  
    arrowlengthfrac=0,  
    nodesize=0.04,  
    edgelinewidth=3.0,  
    nodestrokelw=0,  
    outangle=120
)
