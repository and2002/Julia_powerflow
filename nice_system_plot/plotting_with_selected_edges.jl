using CSV, DataFrames, Graphs, GraphPlot, Colors, LinearAlgebra, Random, Compose, Fontconfig

# Load the CSV file
file_path = "C:/Users/andre/Desktop/Julia_code_main_directory/Incidence_matrix/Network_matrix.csv"  # Change to your actual file path
df = CSV.read(file_path, DataFrame)

# Define column indices: [Zone_Name, Zone_Number, Line_Number, Start_Zone, End_Zone, Edge_Length, Active]
column_indices = [1, 2, 3, 4, 5, 6, 7]  

# Dynamically extract the correct columns
Zone_Name = df[!, column_indices[1]]
Zone_Number = df[!, column_indices[2]]
Line_Number = df[!, column_indices[3]]
Start_Zone = df[!, column_indices[4]]
End_Zone = df[!, column_indices[5]]
Edge_Length = df[!, column_indices[6]]
Active = df[!, column_indices[7]]  # New column (0 or 1)

# Function to extract numeric part from "a21", "a35", etc.
strip_first_char(s) = parse(Int, s[2:end])  

# Convert Zone_Number to integers
Zone_Number = strip_first_char.(Zone_Number)

# Extract unique zones and create a mapping
zones = unique(vcat(Start_Zone, End_Zone))
zone_index = Dict(z => i for (i, z) in enumerate(zones))

# **Extract edges (Only add if Active == 1)**
edges = [(zone_index[Start_Zone[i]], zone_index[End_Zone[i]]) for i in 1:length(Start_Zone) if Active[i] > 0]
edge_lengths = [Edge_Length[i] for i in 1:length(Start_Zone) if Active[i] > 0]  # Filter edge lengths

# Create a directed graph
g = SimpleDiGraph(length(zones))

# **Add edges based on "Active" column**
for i in 1:length(edges)
    start_node, end_node = edges[i]
    add_edge!(g, start_node, end_node)
end

# **Fixing Zone Labels**
zone_name_dict = Dict(Zone_Number[i] => Zone_Name[i] for i in 1:length(Zone_Name))
node_labels = [get(zone_name_dict, zones[i], string(zones[i])) for i in 1:length(zones)]

# Convert labels to string explicitly
node_labels = string.(node_labels)

# **📌 Step 1: Use `spring_layout(g, C=5.0, MAXITER=500)` for More Spacing**
x_pos, y_pos = spring_layout(g, C=5.0, MAXITER=500)  # Stronger repulsion, more iterations

# **📌 Step 2: Add Small Random Perturbations to Avoid Overlaps**
for i in 1:length(x_pos)
    x_pos[i] += randn() * 0.05  # Small horizontal perturbation
    y_pos[i] += randn() * 0.05  # Small vertical perturbation
end
# **📌 Adjust Node and Edge Visibility**
nodesize = 0.04  # Reduce node size further so edges remain visible
edgelinewidth = 3.0  # Increase edge thickness
nodestrokelw = 0  # Remove node border to prevent covering edges

# **📌 Use Transparent Nodes to Ensure Edge Visibility**
node_colors = [RGBA(0.4, 0.6, 0.8, 0.7) for _ in 1:nv(g)]  # Lighter nodes (alpha=0.7)
edge_colors = [RGB(0, 0, 0)]  # Black edges

# **📌 Improve Readability by Adjusting Layout**
plot_size1 = (12cm, 12cm)  # Bigger figure to prevent overlap
nodelabelsize = 12  # Make node labels readable
edgelabelsize = 10  # Edge length labels should be slightly smaller
nodelabeldist = 2.5  # Push labels away from nodes to avoid overlap
outangle = 120  # **Forces edges to take wider angles**
edgelabeldistx = 0.2  # Move edge labels horizontally to avoid clashing
edgelabeldisty = 0.2  # Move edge labels vertically to avoid clashing

# **📌 Final gplot Call with Improved Layout**
gplot(g, 
    x_pos, y_pos,  # Pass x and y positions separately
    nodelabel=node_labels,  
    nodefillc=node_colors,  
    edgestrokec=edge_colors,  
    edgelabel=edge_lengths,  # Show edge lengths
    plot_size=plot_size1,  
    nodelabelsize=nodelabelsize,  
    edgelabelsize=edgelabelsize,  
    nodelabeldist=nodelabeldist,
    edgelabeldistx=edgelabeldistx,  # Adjust edge label position
    edgelabeldisty=edgelabeldisty,  # Adjust edge label position
    arrowlengthfrac=0,  # Remove arrows
    nodesize=nodesize,  # Adjust node size to prevent hiding edges
    edgelinewidth=edgelinewidth,  # Make edges thicker
    nodestrokelw=nodestrokelw,  # Remove node borders to improve edge visibility
    outangle=outangle  # **Forces wider angles on edges**
)
