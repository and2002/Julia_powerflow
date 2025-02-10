using DelimitedFiles
using DataFrames
# Function to read `.m` file content
function read_matpower_mfile(file_path)
    return read(file_path, String)  # Read the file as text
end

# Function to extract `mpc.gen` and return (Bus Number, Pg, Qg)
function extract_generator_data(mfile_content)
    # Regex pattern to find `mpc.gen = [ .... ];`
    pattern = Regex("mpc\\.gen\\s*=\\s*\\[(.*?)\\];", "s")
    match_result = match(pattern, mfile_content)

    if match_result === nothing
        println("Error: `mpc.gen` not found in file!")
        return []
    end

    # Extract matrix data
    # Extract matrix data
    matrix_str = match_result[1]
    matrix_data = readdlm(IOBuffer(matrix_str))

    # Select only the **first column (Bus Number)**
    generator_buses = matrix_data[:,1]

    return generator_buses
end

function extract_branch_data(mfile_content)
    # Regex pattern to find `mpc.gen = [ .... ];`
    pattern = Regex("mpc\\.branch\\s*=\\s*\\[(.*?)\\];", "s")
    match_result = match(pattern, mfile_content)

    if match_result === nothing
        println("Error: `mpc.branch` not found in file!")
        return []
    end

    # Extract matrix data
    # Extract matrix data
    matrix_str = match_result[1]
    matrix_data = readdlm(IOBuffer(matrix_str))

    # Select only the **first column (Bus Number)**
    branch_buses = hcat(matrix_data[:,1],matrix_data[:,2])

    return branch_buses
end
# Example usage
mfile_path = "C:/Users/andre/Desktop/Julia_code_main_directory/Troubleshoot_small_case/3_bus_test/matpower_3_bus.m"  # Replace with your `.m` file path
mfile_content = read_matpower_mfile(mfile_path)
generator_matrix = extract_generator_data(mfile_content)
branch_matrix = extract_branch_data(mfile_content)
# Display results

print(generator_matrix)
print(branch_matrix)