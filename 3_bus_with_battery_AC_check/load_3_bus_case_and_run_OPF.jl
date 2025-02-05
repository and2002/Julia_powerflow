#load json, replaces batteries, converts to matpower, saves. Then case by case verification (to be done)
using PowerModels
using PowerSystems
using Ipopt
using DataFrames
using CSV
using DataFrames

#Functions

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

#print system info
function system_info(system:: PowerSystems.System)

    println("SYSTEM CONFIGURATION:")
    renewables = get_components(RenewableDispatch, system)
    for (i, gen) in enumerate(renewables)
        println("Renewable Generator $i: ", gen.name, " on bus ", gen.bus.name, " which number is ", gen.bus.number)
    end

    generators = get_components(ThermalStandard, system)
    for (i, gen) in enumerate(generators)
        println("Generator $i: ", gen.name, " on bus ", gen.bus.name, " which number is ", gen.bus.number)
    end

    loads = get_components(PowerLoad, system)
    for (i, element) in enumerate(loads)
        println("Load $i: ", element.name, " on bus ", element.bus.name, " which number is ", element.bus.number)
    end

    transformers = get_components(Transformer2W, system)
    for (i, element) in enumerate(transformers)
        println("Transformer $i: ", element.name, " from bus ", element.arc.from.name, " to bus ", element.arc.to.name, " or pair: ", element.arc.from.number, "-", element.arc.to.number)
    end

    bat = get_components(EnergyReservoirStorage, system)
    for (i, element) in enumerate(bat)
        println("Battery $i: ", element.name, " on bus ", element.bus.name, " which number is ", element.bus.number)#, " on bus: $i", element.bus)
    end
    println()

end

function convert_bus_type(bus::ACBus)
    if bus.bustype == ACBusTypes.REF
        return 3  # Slack Bus
    elseif bus.bustype == ACBusTypes.PV
        return 2  # PV Bus (Generator Bus)
    else
        return 1  # PQ Bus (Load Bus)
    end
end
# parces battery as generators and loads. input vector format: battery id, charging, discharging, both absolute in pu
function generate_storage_components(sys::System, storage_operations::Array{Tuple{Int, Float64, Float64}})
    system_base_power = sys.units_settings.base_value  # System base power (MVA)

    additional_loads = PowerLoad[]
    additional_generators = ThermalStandard[]

    bat = get_components(EnergyReservoirStorage, sys)
    for (i,storage) in enumerate(bat)
        bus_name = get_component(ACBus, sys, storage.bus.name)
        storage_id = i

        # Find matching storage entry in storage_operations array
        storage_entry = filter(x -> x[1] == storage_id, storage_operations)
        if isempty(storage_entry)
            continue  # Skip if storage not listed
        end

        charge_power = storage_entry[1][2]  # MW of charging power
        discharge_power = storage_entry[1][3]  # MW of discharging power

        # **Charging Mode → Treat as Load**
        if charge_power > 0
            push!(additional_loads, PowerLoad(;
                name = "storage_load_$storage_id",
                available = true,
                bus = bus_name,  # Find bus in system
                active_power = charge_power,  # apply PU
                reactive_power = 0.0,
                base_power = system_base_power,
                max_active_power = charge_power,
                max_reactive_power = 0.0
            ))
        end

        # **Discharging Mode → Treat as Generator**
        if discharge_power > 0
            push!(additional_generators, ThermalStandard(;
                name = "storage_gen_$storage_id",
                available = true,
                status = true,
                bus = bus_name,
                active_power = discharge_power, # Per-unitized by device base_power
                reactive_power = 0.0, # Per-unitized by device base_power
                rating = discharge_power, # 300 MW per-unitized by device base_power
                active_power_limits = (min = 0.0, max = discharge_power), # 6 MW to 30 MW per-unitized by device base_power
                reactive_power_limits =(min = 0.0, max = 0.0), #nothing, # Per-unitized by device base_power
                ramp_limits = (up = 1.0, down = 1.0), # 6 MW/min up or down, per-unitized by device base_power
                operation_cost = ThermalGenerationCost(nothing),
                base_power = system_base_power, # MVA
                time_limits = (up = 8.0, down = 8.0), # Hours
                must_run = false,
                prime_mover_type = PrimeMovers.CC,
                fuel = ThermalFuels.NATURAL_GAS
                ))
        end
    end
    add_components!(sys, additional_loads)
    add_components!(sys, additional_generators)
    println(additional_loads)
    return sys
end

function convert_to_matpower(sys::System) 
    #bat_state stores the 
    # Initialize MATPOWER dictionary
    system_base_power = sys.units_settings.base_value
    radian_converter = 57.2958 # stores how many degree in radian
    mp_data = Dict(
        "baseMVA" => system_base_power,  # System base power
        "bus" => [],       # List of buses
        "gen" => [],       # List of generators
        "branch" => [],    # List of branches (lines)
        "gencost" => [],   # Generator cost functions
    )

    # Extract Bus Data
    for bus in get_components(ACBus, sys)
        push!(mp_data["bus"], [
            bus.number,      # Bus ID
            convert_bus_type(bus),  # Correct Bus Type from bus.type
            0.0,             # Pd (Real power demand)
            0.0,             # Qd (Reactive power demand)
            0.0, 0.0,        # Gs, Bs (Shunt conductance & susceptance)
            1,               # Area (default 1)
            bus.magnitude,          # Vm (Voltage magnitude in p.u.)
            bus.angle,          # Va (Voltage angle in degrees)
            bus.base_voltage,  # Base voltage (kV)
            1,               # Zone (default 1)
            bus.voltage_limits.max, bus.voltage_limits.min       # Vmax, Vmin
        ])
    end

    for line in get_components(Line, sys)
        push!(mp_data["branch"], [
            line.arc.from.number,  # From Bus
            line.arc.to.number,    # To Bus
            line.r,            # Resistance (p.u.)
            line.x,            # Reactance (p.u.)
            (line.b.from + line.b.to)/2,            # Line charging susceptance (p.u.)
            line.rating * system_base_power,  # Rate A (default to large number if not defined)
            line.rating * system_base_power,  # Rate B
            line.rating * system_base_power,  # Rate C
            1.0,               # Transformer tap ratio (1.0 for transmission lines)
            0.0,               # Phase shift angle
            1,                 # Status (1 = in-service)
            line.angle_limits.min * radian_converter,  line.angle_limits.max * radian_converter        # Min/Max angle difference
        ])
    end

    for tf in get_components(Transformer2W, sys)
        push!(mp_data["branch"], [
            tf.arc.from.number,  # From Bus
            tf.arc.to.number,    # To Bus
            tf.r,            # Resistance (p.u.)
            tf.x,            # Reactance (p.u.)
            tf.primary_shunt,             # 
            tf.rating,  # Convert rate A to MVA if in p.u.
            tf.rating,  # Convert rate B
            tf.rating,  # Convert rate C
            tf.arc.from.base_voltage / tf.arc.to.base_voltage,  # Transformer tap ratio
            0,   # Phase shift angle (degrees)
            1,                # Status (1 = in-service)
            -360, 360         # Min/Max angle difference
        ])
    end

    #Add thermal generators
    for gen in get_components(ThermalStandard, sys)
        push!(mp_data["gen"], [
            gen.bus.number,  # Bus ID
            gen.active_power * system_base_power,  # Active power output (convert p.u. to MW)
            isnothing(gen.reactive_power) ? 0.0 : gen.reactive_power * system_base_power,  # Handle missing Qg
            isnothing(gen.reactive_power_limits) ? 9999.0 : gen.reactive_power_limits.max * system_base_power,  # Handle missing Qmax
            isnothing(gen.reactive_power_limits) ? -9999.0 : gen.reactive_power_limits.min * system_base_power,  # Handle missing Qmin
            gen.bus.magnitude,  # Voltage setpoint (p.u.)
            system_base_power,  # Generator MVA base (same as system base)
            1,  # Generator status (1 = online, 0 = offline)
            gen.active_power_limits.max * system_base_power,  # Maximum real power output (MW)
            gen.active_power_limits.min * system_base_power,  # Minimum real power output (MW)
        ])
    end

    for gen in get_components(ThermalStandard, sys)
        cost_curve = gen.operation_cost.variable # get type of curve and its details
        startup_cost = gen.operation_cost.start_up
        shutdown_cost = gen.operation_cost.shut_down
        #println(typeof(cost_curve))
        #println(cost_curve.value_curve.function_data.proportional_term)
        
        if cost_curve isa CostCurve{LinearCurve}
            #println("TRUE1")
            a, b, c = 0.0, cost_curve.value_curve.function_data.proportional_term, cost_curve.value_curve.function_data.constant_term  # Linear is C(P) = b * P
        else
            a, b, c = 0.0, 0.0, 0.0  # Default to zero-cost if undefined
        end

        push!(mp_data["gencost"], [
            2,  # Quadratic cost model
            startup_cost,  # Startup cost
            shutdown_cost,  # Shutdown cost
            3,  # Number of cost function terms (Quadratic)
            a, b, c  # Coefficients of cost function
        ])
    end

    #Add renewable generators
    for ren in get_components(RenewableDispatch, sys)
        push!(mp_data["gen"], [
            ren.bus.number,  # Bus ID
            ren.active_power * system_base_power,  # Active power output (MW)
            isnothing(ren.reactive_power) ? 0.0 : ren.reactive_power * system_base_power,  # Handle missing Qg
            isnothing(ren.reactive_power_limits) ? 9999.0 : ren.reactive_power_limits.max * system_base_power,  # Qmax
            isnothing(ren.reactive_power_limits) ? -9999.0 : ren.reactive_power_limits.min * system_base_power,  # Qmin
            ren.bus.magnitude,  # Voltage setpoint (p.u.)
            system_base_power,  # Generator MVA base (same as system base)
            1,  # Generator status (1 = online, 0 = offline)
            ren.active_power * system_base_power,  # Maximum real power output (MW)
            0,  # Minimum real power output (MW)
        ])
    end
    
    for ren in get_components(RenewableDispatch, sys)
        cost_curve = ren.operation_cost.variable.value_curve
        println(typeof(cost_curve))
        #println(cost_curve.value_curve.function_data.proportional_term)
        if cost_curve isa LinearCurve
            println("TRUE1")
            a, b, c = 0.0, cost_curve.function_data.proportional_term, cost_curve.function_data.constant_term # Linear is C(P) = b * P
        else
            a, b, c = 0.0, 0.0, 0.0  # Default to very low cost if missing
        end

        push!(mp_data["gencost"], [
            2,  # Quadratic cost model
            0.0,  # Startup cost
            0.0,  # Shutdown cost
            3,  # Number of cost function terms
            a, b, c  # Coefficients of cost function
        ])
    end

    # Dictionary to accumulate load data for each bus
    bus_loads = Dict{Int, Tuple{Float64, Float64}}()

    for load in get_components(PowerLoad, sys)
        bus_number = load.bus.number

        # Take `max_active_power` and `max_reactive_power`
        active_load = load.max_active_power * system_base_power  # Convert p.u. to MW
        reactive_load = isnothing(load.max_reactive_power) ? 0.0 : load.max_reactive_power * system_base_power  # Convert p.u. to MVAr

        # Sum multiple loads at the same bus
        if haskey(bus_loads, bus_number)
            bus_loads[bus_number] = (
                bus_loads[bus_number][1] + active_load, 
                bus_loads[bus_number][2] + reactive_load
            )
        else
            bus_loads[bus_number] = (active_load, reactive_load)
        end
    end

    # Update `mpc.bus` with load values
    for bus in mp_data["bus"]
        bus_id = bus[1]  # Bus ID
        if haskey(bus_loads, bus_id)
            bus[3] = bus_loads[bus_id][1]  # Assign total active load (Pd)
            bus[4] = bus_loads[bus_id][2]  # Assign total reactive load (Qd)
        end
    end 

    return mp_data
end

function save_as_matpower(mp_data, filename)
    open(filename, "w") do io
        println(io, "function mpc = case_example")
        println(io, "mpc.version = '2';")
        println(io, "mpc.baseMVA = ", mp_data["baseMVA"], ";")

        println(io, "%% Bus Data")
        println(io, "mpc.bus = [")
        for row in mp_data["bus"]
            println(io, "  ", join(row, "\t"), ";")
        end
        println(io, "];")

        println(io, "%% Generator Data")
        println(io, "mpc.gen = [")
        for row in mp_data["gen"]
            println(io, "  ", join(row, "\t"), ";")
        end
        println(io, "];")

        println(io, "%% Branch Data")
        println(io, "mpc.branch = [")
        for row in mp_data["branch"]
            println(io, "  ", join(row, "\t"), ";")
        end
        println(io, "];")

        println(io, "%% Generator Cost Data")
        println(io, "mpc.gencost = [")
        for row in mp_data["gencost"]
            println(io, "  ", join(row, "\t"), ";")
        end
        println(io, "];")

        println(io, "end")
    end
end

function extract_opf_results(result,adress) # result - output of OPF, adress - adress of m file with problem
    # Extract bus voltage magnitudes and angles
    voltage_magnitude = Dict(name => data["vm"] for (name, data) in result["solution"]["bus"])
    voltage_amplitude = Dict(name => data["va"] for (name, data) in result["solution"]["bus"])
    
    # Get sorted list of buses
    sorted_buses = sort(collect(keys(voltage_magnitude)), by=x -> parse(Int, x))

    # Create bus voltage matrix
    bus_matrix = hcat(
        [parse(Int, bus) for bus in sorted_buses],  # Bus numbers
        [voltage_magnitude[bus] for bus in sorted_buses],  # Voltage Magnitudes
        [voltage_amplitude[bus] for bus in sorted_buses]   # Voltage Angles
    )

    mfile_content = read_matpower_mfile(mfile_path)
    branch_buses = extract_branch_data(mfile_content)  # Extracts (From Bus, To Bus)
    
    # Extract branch power flows from OPF result
    branches = result["solution"]["branch"]
    
    # Ensure the correct order of branches
    sorted_branch_ids = sort(collect(keys(branches)), by=x -> parse(Int, x))
    
    # Merge branch buses with OPF power flows
    branch_matrix = hcat(
        branch_buses[:,1],  # From Bus
        branch_buses[:,2],  # To Bus
        [parse(Int, branch_id) for branch_id in sorted_branch_ids],  # Branch ID (from OPF results)
        [branches[branch_id]["pf"] for branch_id in sorted_branch_ids],  # Active Power Input (Pf)
        [branches[branch_id]["pt"] for branch_id in sorted_branch_ids],  # Active Power Output (Pt)
        [branches[branch_id]["qf"] for branch_id in sorted_branch_ids],  # Reactive Power Input (Qf)
        [branches[branch_id]["qt"] for branch_id in sorted_branch_ids]   # Reactive Power Output (Qt)
    )
    

    # Create generator bus vector (corresponding bus in each gen)
    mfile_content = read_matpower_mfile(mfile_path)
    bus_info = extract_generator_data(mfile_content)  # Vector of generator bus numbers

    # Extract OPF generator power output (Pg, Qg)
    generators = result["solution"]["gen"]

    # Ensure generator order matches `bus_info`
    generators = result["solution"]["gen"]

    # Extract values directly, keeping original order
    generator_matrix = hcat(
        bus_info,  # Correct bus numbers from MATPOWER `.m` file
        [generators[string(i)]["pg"] for i in 1:length(bus_info)],  # Pg (MW) in same order
        [generators[string(i)]["qg"] for i in 1:length(bus_info)]   # Qg (MVAr) in same order
    )
    return bus_matrix, branch_matrix, generator_matrix
end

function beutiful_result_display(bus_matrix, branch_matrix, generator_matrix)
    # Display as DataFrames for better visualization
    df_bus = DataFrame(Bus=bus_data[:,1], Vm=bus_data[:,2], Va=bus_data[:,3])
    df_branch = DataFrame(
        From_Bus = branch_matrix[:,1],
        To_Bus = branch_matrix[:,2],
        Branch_ID = branch_matrix[:,3],
        Pf = branch_matrix[:,4],
        Pt = branch_matrix[:,5],
        Qf = branch_matrix[:,6],
        Qt = branch_matrix[:,7]
    )
    df_gen = DataFrame(Bus=generator_data[:,1], Pg=generator_data[:,2], Qg=generator_data[:,3])

    println("Bus Data:\n", df_bus)
    println("\nBranch Power Flow Data:\n", df_branch)
    println("\nGenerator Production Data:\n", df_gen)
end

# Read data from optimization
# Read CSV file into a DataFrame
main_direct_with_data = "C:/Users/andre/Desktop/Julia_code_main_directory/Troubleshoot_small_case/optimization_results"
DF_load1 = CSV.read(joinpath(main_direct_with_data,"DF_load1.csv"), DataFrame)
DF_load2 = CSV.read(joinpath(main_direct_with_data,"DF_load2.csv"), DataFrame)
DF_wind1 = CSV.read(joinpath(main_direct_with_data,"DF_wind1.csv"), DataFrame)
DF_battery_out = CSV.read(joinpath(main_direct_with_data,"DF_battery_out.csv"), DataFrame)
# Convert a single column to an array
load1_array = abs.(DF_load1[:, 1])  # Extract first column as an array
load2_array = abs.(DF_load2[:, 1])  # Extract first column as an array
wind1_array = abs.(DF_wind1[:, 1])  # Extract first column as an array
battery_out_array = abs.(DF_battery_out[:, 1])  # Extract first column as an array


# Convert and Save
storage_operations = [
    (1, 0.0, 2.0),  # Battery 1 charging 0 MW, discharging 100 MW
]

system_adress = "C:/Users/andre/Desktop/Julia_code_main_directory/Troubleshoot_small_case/3_bus_test/test_system.json"

sys = System(system_adress)
println(fieldnames(typeof(sys)))
println(sys.units_settings.base_value)

#additional_loads, additional_generators = 
system_2 = generate_storage_components(sys, storage_operations)

println(sys.bus_numbers)

mp_data = convert_to_matpower(system_2)
system_info(system_2)
adress_m_system = "C:/Users/andre/Desktop/Julia_code_main_directory/Troubleshoot_small_case/3_bus_test/matpower_3_bus.m"
save_as_matpower(mp_data, adress_m_system)
println("Saved MATPOWER file")

###SOLVE!
network_data = PowerModels.parse_file(adress_m_system)
interest = 1
println("Available Bus Keys: ", keys(network_data["bus"]))
println("Available Load Keys: ", keys(network_data["load"]))

network_data["load"]["1"]["pd"] = load1_array[interest]
network_data["load"]["2"]["pd"] = load2_array[interest]

network_data["gen"]["3"]["pmax"] = wind1_array[interest]
network_data["gen"]["1"]["pmax"] = battery_out_array[interest]

result = solve_opf(network_data, ACPPowerModel, Ipopt.Optimizer)
bus_data, branch_data, generator_data = extract_opf_results(result, adress_m_system)
beutiful_result_display(bus_data, branch_data, generator_data)
