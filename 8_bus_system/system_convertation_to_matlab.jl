# This code takes the system as json and converts it to matlab format. Note: battery is treated as load or as generator. depends on vector. vecotr hasformat listed in code
using PowerModels
using PowerSystems
using Ipopt

#Functions

function convert_bus_type(bus::ACBus)
    if bus.bustype == :REF
        return 3  # Slack Bus (Reference)
    elseif bus.bustype == :PV
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
                bus = bus_name,  # Find bus in system
                active_power = discharge_power,  # Convert MW to p.u.
                reactive_power = 0.0,
                base_power = system_base_power,
                active_power_limits = (min = 0.0, max = discharge_power),
                reactive_power_limits = (min = 0.0, max = 0.0),
                operation_cost = ThermalGenerationCost(nothing) # ADD IF REQUIRED!
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

        if cost_curve isa LinearCurve
            a, b, c = 0.0, cost_curve.a, 0.0  # Linear is C(P) = b * P
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
        if cost_curve isa LinearCurve
            a, b, c = 0.0, cost_curve.function_data.proportional_term, cost_curve.function_data.constant_term# Linear is C(P) = b * P
        else
            a, b, c = 0.0, 1e-6, 0.0  # Default to very low cost if missing
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

# Convert and Save
storage_operations = [
    (1, 3.1, 0.0),  # Battery 1 charging 3 MW, discharging 5 MW

]

system_adress = "C:/Users/andre/Desktop/Julia_code_main_directory/Large_example/test_save/test_system.json"

sys = System(system_adress)
println(fieldnames(typeof(sys)))
println(sys.units_settings.base_value)

#additional_loads, additional_generators = 
system_2 = generate_storage_components(sys, storage_operations)

println(sys.bus_numbers)

mp_data = convert_to_matpower(system_2)
save_as_matpower(mp_data, "C:/Users/andre/Desktop/Julia_code_main_directory/Large_example/test_save/system_bat1.m")
println("Saved MATPOWER file")
