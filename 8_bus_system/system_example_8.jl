# This file creates same system and saves it as json. Also, it has function system_info, which allows to see all omponents of defined types added to system
using PowerSystems
using PowerModels
using PowerSimulations
using HydroPowerSimulations
using StorageSystemsSimulations
using PowerSystemCaseBuilder
using HiGHS # solver
using Dates
using MathOptInterface
using InfrastructureSystems
using TimeSeries
using JuMP
using Plots
using CSV
using DataFrames
using HDF5

# Functions
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

function save_system_to_json(
    system:: System, #system to save
    name:: String, #name you would like to give your system
    folder:: String # folder you would like to save your system to
)
    path = joinpath(folder, join([name,".json"],""))

    # Check if the directory exists; if not, create it
    if !isdir(folder)
        mkdir(folder)
    end

    # Save the existing PowerSystems.System to JSON with force overwrite
    to_json(system, path; force=true)

    println("System saved successfully to: ", path)
end

function data_for_plotting_variables_section(
    array:: Matrix{Float64}, # input data
    n::Int, # number of interest
    start_time::DateTime, # start time for plotting
    num_steps::Int, # number of steps
    original_resolution::Period, # resolution
    system_base:: Float64 # base power
    )
    data_1d = array[:,n] * system_base

    total_duration = original_resolution * num_steps
    timestamps = collect(start_time:original_resolution:start_time + total_duration - original_resolution)
    return (timestamps,data_1d)
end

# Takes 3D array and compresses to 1D
function compress_to_1D_for_n(array::Array{Float64, 3}, n::Int) # n is number of interest 
    # Ensure n is within bounds
    _, num_cols, num_slices = size(array)
    if n > num_cols || n < 1
        error("Invalid value for n: $n. The array has $num_cols columns.")
    end

    compressed_array = Float64[]
    
    for slice in 1:num_slices
        # Extract the nth column for the current slice and append it
        append!(compressed_array, array[:, n, slice])
    end
    
    return compressed_array
end

#takes starting time, number of steps, resolution of initial data, number of points at final data 
function generate_timesteps_rescaled(start_time::DateTime, num_steps::Int, original_resolution::Period, new_num_steps::Int)
    # Calculate total duration based on the original number of steps and resolution
    total_duration = original_resolution * num_steps
    
    # Calculate the new resolution
    new_resolution_seconds = (total_duration.value / new_num_steps) * 60  # Convert minutes to seconds
    new_resolution = Millisecond(round(Int, new_resolution_seconds * 1000))  # Convert to milliseconds
    
    # Generate new timestamps
    timestamps = collect(start_time:new_resolution:start_time + total_duration - new_resolution)
    
    return timestamps, new_resolution
end

# Create time and data array in system base
function data_for_plotting(
    value_array:: Array{Float64,3}, # values
    n::Int, # element of interest (for multiple elements in system) 
    start_time:: DateTime, # start time
    num_steps::Int, #number_steps
    original_resolution::Period, # original resolution, usioally 5 min
    system_base::Float64) # MVA base, usially 100 MVA

    data_1D = compress_to_1D_for_n(value_array,n)
    #print(data_1D[1:5])
    N = length(data_1D)
    time_line,new_resolution = generate_timesteps_rescaled(start_time, num_steps, original_resolution, N)
    return time_line,data_1D*system_base

end

function create_time_and_forecast_series(
    power_data_path::String,
    forecast_data_path::String,
    forecast_resolution::Period
)
    # Load power data
    power_data = CSV.read(power_data_path, DataFrame)
    # Convert `Time` column to DateTime
    power_data.Time = DateTime.(power_data.Time)
    
    # Create TimeArray for power data
    timestamps_power = power_data.Time
    values_power = power_data[!,"Power (MW)"]  # Adjust column name if different
    power_timearray = TimeArray(timestamps_power, values_power)
    
    # Create SingleTimeSeries for time series
    time_series = SingleTimeSeries(
        name = "max_active_power",
        data = power_timearray
    )
    
    # Load forecast data
    forecast_data = CSV.read(forecast_data_path, DataFrame)
    
    # Convert `Time` column to DateTime
    forecast_data.Time = DateTime.(forecast_data.Time)
    
    # Create a dictionary for forecast data
    forecast = Dict(
        row.Time => collect(row[2:end])  # Convert each row's horizons to Vector
        for row in eachrow(forecast_data)
    )
    
    # Create Deterministic for forecast series
    forecast_series = Deterministic(
        name = "max_active_power",
        data = forecast,
        resolution = forecast_resolution
    )
    
    # Return both time_series and forecast_series
    return time_series, forecast_series
end

#Main Code

system = System(100.0, frequency = 50.0)# 100 MVA base power, 50 Hz frequency

bus1 = ACBus(;
    number = 1,
    name = "bus1",
    bustype = ACBusTypes.REF,
    angle = 0.0,
    magnitude = 1.0,
    voltage_limits = (min = 0.9, max = 1.05),
    base_voltage = 110.0,
);

bus2 = ACBus(;
    number = 2,
    name = "bus2",
    bustype = ACBusTypes.PV,
    angle = 0.0,
    magnitude = 1.0,
    voltage_limits = (min = 0.9, max = 1.05),
    base_voltage = 110.0,
);

bus3 = ACBus(;
    number = 3,
    name = "bus3",
    bustype = ACBusTypes.PQ,
    angle = 0.0,
    magnitude = 1.0,
    voltage_limits = (min = 0.9, max = 1.05),
    base_voltage = 110.0,
);

bus4 = ACBus(;
    number = 4,
    name = "bus4",
    bustype = ACBusTypes.PQ,
    angle = 0.0,
    magnitude = 1.0,
    voltage_limits = (min = 0.9, max = 1.05),
    base_voltage = 330.0,
);

bus5 = ACBus(;
    number = 5,
    name = "bus5",
    bustype = ACBusTypes.PQ,
    angle = 0.0,
    magnitude = 1.0,
    voltage_limits = (min = 0.9, max = 1.05),
    base_voltage = 330.0,
);

bus6 = ACBus(;
    number = 6,
    name = "bus6",
    bustype = ACBusTypes.PQ,
    angle = 0.0,
    magnitude = 1.0,
    voltage_limits = (min = 0.9, max = 1.05),
    base_voltage = 110.0,
);

bus7 = ACBus(;
    number = 7,
    name = "bus7",
    bustype = ACBusTypes.PQ,
    angle = 0.0,
    magnitude = 1.0,
    voltage_limits = (min = 0.9, max = 1.05),
    base_voltage = 110.0,
);

bus8 = ACBus(;
    number = 8,
    name = "bus8",
    bustype = ACBusTypes.PQ,
    angle = 0.0,
    magnitude = 1.0,
    voltage_limits = (min = 0.9, max = 1.05),
    base_voltage = 110.0,
);

add_components!(system, [bus1, bus2, bus3, bus4, bus5, bus6, bus7, bus8])

#add transformers
T1 = Transformer2W(;
    name = "Transformer1",
    available = true,
    arc = Arc(; from = bus3, to = bus4),
    active_power_flow = 0.0,
    reactive_power_flow = 0.0,
    r = 0.01,                 # Resistance (per unit)
    x = 0.05,                 # Reactance (per unit)
    rating = 800.0,           # Transformer MVA rating
    primary_shunt = 0.01
)

T2 = Transformer2W(;
    name = "Transformer2",
    available = true,
    arc = Arc(; from = bus5, to = bus6),
    active_power_flow = 0.0,
    reactive_power_flow = 0.0,
    r = 0.01,                 # Resistance (per unit)
    x = 0.05,                 # Reactance (per unit)
    rating = 800.0,           # Transformer MVA rating
    primary_shunt = 0.01
)

add_components!(system, [T1, T2]);

#add transmission list_parameter_names
lineA = Line(;
    name = "lineA",
    available = true,
    active_power_flow = 0.0,
    reactive_power_flow = 0.0,
    arc = Arc(; from = bus1, to = bus3),
    r = 0.00281, # Per-unit
    x = 0.0281, # Per-unit
    b = (from = 0.00356, to = 0.00356), # Per-unit
    rating = 5.0, # Line rating of 400 MVA / System base of 100 MVA
    angle_limits = (min = -0.7, max = 0.7),
)

lineB = Line(;
    name = "lineB",
    available = true,
    active_power_flow = 0.0,
    reactive_power_flow = 0.0,
    arc = Arc(; from = bus2, to = bus3),
    r = 0.00231, # Per-unit
    x = 0.0181, # Per-unit
    b = (from = 0.00356, to = 0.00356), # Per-unit
    rating = 3.0, # Line rating of 300 MVA / System base of 100 MVA
    angle_limits = (min = -0.7, max = 0.7),
)

lineC = Line(;
    name = "lineC",
    available = true,
    active_power_flow = 0.0,
    reactive_power_flow = 0.0,
    arc = Arc(; from = bus4, to = bus5),
    r = 0.00281, # Per-unit
    x = 0.0281, # Per-unit
    b = (from = 0.00356, to = 0.00356), # Per-unit
    rating = 8.0, # Line rating of 400 MVA / System base of 100 MVA
    angle_limits = (min = -0.7, max = 0.7),
)

lineD = Line(;
    name = "lineD",
    available = true,
    active_power_flow = 0.0,
    reactive_power_flow = 0.0,
    arc = Arc(; from = bus6, to = bus7),
    r = 0.00281, # Per-unit
    x = 0.00381, # Per-unit
    b = (from = 0.00356, to = 0.00356), # Per-unit
    rating = 5.0, # Line rating of 500 MVA / System base of 100 MVA
    angle_limits = (min = -0.7, max = 0.7),
)

lineE = Line(;
    name = "lineE",
    available = true,
    active_power_flow = 0.0,
    reactive_power_flow = 0.0,
    arc = Arc(; from = bus6, to = bus8),
    r = 0.00281, # Per-unit
    x = 0.00381, # Per-unit
    b = (from = 0.00356, to = 0.00356), # Per-unit
    rating = 5.0, # Line rating of 500 MVA / System base of 100 MVA
    angle_limits = (min = -0.7, max = 0.7),
)

add_components!(system, [lineA, lineB, lineC, lineD, lineE])
# add generation

gas = ThermalStandard(;
    name = "gas1",
    available = true,
    status = true,
    bus = bus1,
    active_power = 2.0, # Per-unitized by device base_power
    reactive_power = 0.0, # Per-unitized by device base_power
    rating = 5.0, # 300 MW per-unitized by device base_power
    active_power_limits = (min = 0.5, max = 5.0), # 6 MW to 30 MW per-unitized by device base_power
    reactive_power_limits =(min = -1.0, max = 1.0), #nothing, # Per-unitized by device base_power
    ramp_limits = (up = 0.3, down = 0.3), # 6 MW/min up or down, per-unitized by device base_power
    operation_cost = ThermalGenerationCost(
            CostCurve(LinearCurve(1400.0)),
            0.0,
            4.0,
            2.0,
        ),
    base_power = 100.0, # MVA
    time_limits = (up = 8.0, down = 8.0), # Hours
    must_run = false,
    prime_mover_type = PrimeMovers.CC,
    fuel = ThermalFuels.NATURAL_GAS,
);

wind1 = RenewableDispatch(;
    name = "wind1",
    available = true,
    bus = bus2,
    active_power = 0.0, # Per-unitized by device base_power
    reactive_power = 0.0, # Per-unitized by device base_power
    rating = 1.0, # 10 MW per-unitized by device base_power
    prime_mover_type = PrimeMovers.WT,
    reactive_power_limits = (min = 0.0, max = 0.0), # per-unitized by device base_power
    power_factor = 1.0,
    operation_cost = RenewableGenerationCost(nothing),
    base_power = 100.0, # MVA
);

#solar 
solar1 = RenewableDispatch(;
    name = "solar1",
    available = true,
    bus = bus7,
    active_power = 0.0, # Per-unitized by device base_power
    reactive_power = 0.0, # Per-unitized by device base_power
    rating = 4.0, # 10 MW per-unitized by device base_power
    prime_mover_type = PrimeMovers.PVe,
    reactive_power_limits = (min = 0.0, max = 0.0), # per-unitized by device base_power
    power_factor = 1.0,
    operation_cost = RenewableGenerationCost(; variable = CostCurve(; value_curve = LinearCurve(22.0))),
    base_power = 100.0, # MVA
);
#Add storage
storage1 = EnergyReservoirStorage(
    name = "Battery1",
    available = true,
    bus = bus8,
    prime_mover_type = PrimeMovers.BA,  # Example prime mover type
    storage_technology_type = StorageTech.LIB,  # Battery storage type
    storage_capacity = 500.0,  # 100 MWh capacity
    storage_level_limits = (min = 0.1, max = 1.0),  # Min and max storage levels (10% to 100%)
    initial_storage_capacity_level = 0.11,  # Initially 50% full
    rating = 100.0,  # Max output power rating (MW)
    active_power = 0.0,  # Initial active power (MW)
    input_active_power_limits = (min = 0.0, max =90.0),  # Charging limits (MW)
    output_active_power_limits = (min = 0.0, max = 90.0),  # Discharging limits (MW)
    efficiency = (in = 0.95, out = 0.95),  # Charging/discharging efficiencies
    reactive_power = 0.0,  # Initial reactive power (MVAR)
    reactive_power_limits = (min = -10.0, max = 10.0),  # Reactive power limits (MVAR)
    base_power = 100.0,  # Base power of the unit (MVA)
    operation_cost = StorageCost(nothing),  # Default operation cost
    conversion_factor = 0.95,  # Conversion factor for storage capacity
    storage_target = 0.3,  # No specific target
    cycle_limits = 100000,  # Maximum cycles per year
)

add_components!(system, [gas, wind1, solar1, storage1])

#loads 
load1 = PowerLoad(;
    name = "load1",
    available = true,
    bus = bus7,
    active_power = 0.0, # Per-unitized by device base_power
    reactive_power = 0.0, # Per-unitized by device base_power
    base_power = 100.0, # MVA
    max_active_power = 1.0, # 10 MW per-unitized by device base_power
    max_reactive_power = 0.0,
);

load2 = PowerLoad(;
    name = "load2",
    available = true,
    bus = bus8,
    active_power = 0.0, # Per-unitized by device base_power
    reactive_power = 0.0, # Per-unitized by device base_power
    base_power = 100.0, # MVA
    max_active_power = 2.0, # 10 MW per-unitized by device base_power
    max_reactive_power = 0.0,
);

add_components!(system, [load1,load2])

system_info(system)
current_folder = "C:/Users/andre/Desktop/Julia_code_main_directory/Large_example"
save_system_to_json(system,"test_system",joinpath(current_folder,"test_save"))
