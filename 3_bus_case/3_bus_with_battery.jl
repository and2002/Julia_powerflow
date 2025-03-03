using PowerSystems
using PowerSimulations
using StorageSystemsSimulations
using HydroPowerSimulations
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
function dispatch_to_array(dispatch_data::Array{Float64, 3}, start_time::DateTime, resolution::Period, base_power::Float64)
    # Number of intervals (horizons) and time steps
    num_steps, _, num_intervals = size(dispatch_data)
    # Prepare output data
    timestamps = Vector{DateTime}(undef, num_steps * num_intervals)
    power_values = Vector{Float64}(undef, num_steps * num_intervals)
    
    # Flatten the data into a 2D array
    for interval in 1:num_intervals
        for step in 1:num_steps
            idx = (interval - 1) * num_steps + step
            timestamps[idx] = start_time + (step - 1) * resolution + (interval - 1) * Hour(1)
            power_values[idx] = dispatch_data[step, 1, interval] * base_power  # Convert to MW
        end
    end
    
    # Return as a tuple of arrays
    return (timestamps, power_values)
end

# Takes 3D array and compresses to 1D
function compress_to_1D_for_n(array::Array{Float64, 3}, n::Int)
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

system = System(100.0)# 100 MVA base power

bus1 = ACBus(;
    number = 1,
    name = "bus1",
    bustype = ACBusTypes.REF,
    angle = 0.0,
    magnitude = 1.0,
    voltage_limits = (min = 0.9, max = 1.05),
    base_voltage = 230.0,
);

bus2 = ACBus(;
    number = 2,
    name = "bus2",
    bustype = ACBusTypes.PQ,
    angle = 0.0,
    magnitude = 1.0,
    voltage_limits = (min = 0.9, max = 1.05),
    base_voltage = 230.0,
);

bus3 = ACBus(;
    number = 3,
    name = "bus3",
    bustype = ACBusTypes.PQ,
    angle = 0.0,
    magnitude = 1.0,
    voltage_limits = (min = 0.9, max = 1.05),
    base_voltage = 230.0,
);

gas = ThermalStandard(;
    name = "gas1",
    available = true,
    status = true,
    bus = bus1,
    active_power = 2.0, # Per-unitized by device base_power
    reactive_power = 0.0, # Per-unitized by device base_power
    rating = 3.0, # 300 MW per-unitized by device base_power
    active_power_limits = (min = 0, max = 3.0), # 6 MW to 30 MW per-unitized by device base_power
    reactive_power_limits = nothing, # Per-unitized by device base_power
    ramp_limits = (up = 1.0, down = 1.0), # 6 MW/min up or down, per-unitized by device base_power
    operation_cost = ThermalGenerationCost(nothing),
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

storage1 = EnergyReservoirStorage(
    name = "Battery1",
    available = true,
    bus = bus3,
    prime_mover_type = PrimeMovers.BA,  # Example prime mover type
    storage_technology_type = StorageTech.LIB,  # Battery storage type
    storage_capacity = 500.0,  # 100 MWh capacity
    storage_level_limits = (min = 0.1, max = 1.0),  # Min and max storage levels (10% to 100%)
    initial_storage_capacity_level = 0.11,  # Initially 50% full
    rating = 100.0,  # Max output power rating (MW)
    active_power = 0.0,  # Initial active power (MW)
    input_active_power_limits = (min = 0.0, max =50.0),  # Charging limits (MW)
    output_active_power_limits = (min = 0.0, max = 50.0),  # Discharging limits (MW)
    efficiency = (in = 0.95, out = 0.95),  # Charging/discharging efficiencies
    reactive_power = 0.0,  # Initial reactive power (MVAR)
    reactive_power_limits = (min = -10.0, max = 10.0),  # Reactive power limits (MVAR)
    base_power = 100.0,  # Base power of the unit (MVA)
    operation_cost = StorageCost(nothing),  # Default operation cost
    conversion_factor = 0.95,  # Conversion factor for storage capacity
    storage_target = 0.0,  # No specific target
    cycle_limits = 100000,  # Maximum cycles per year
)

load1 = PowerLoad(;
    name = "load1",
    available = true,
    bus = bus2,
    active_power = 0.0, # Per-unitized by device base_power
    reactive_power = 0.0, # Per-unitized by device base_power
    base_power = 100.0, # MVA
    max_active_power = 2.0, # 10 MW per-unitized by device base_power
    max_reactive_power = 0.0,
);

load2 = PowerLoad(;
    name = "load2",
    available = true,
    bus = bus3,
    active_power = 0.5, # Per-unitized by device base_power
    reactive_power = 0.0, # Per-unitized by device base_power
    base_power = 100.0, # MVA
    max_active_power = 1.0, # 10 MW per-unitized by device base_power
    max_reactive_power = 0.0,
);

line1 = Line(;
    name = "line1",
    available = true,
    active_power_flow = 0.0,
    reactive_power_flow = 0.0,
    arc = Arc(; from = bus1, to = bus2),
    r = 0.00281, # Per-unit
    x = 0.0281, # Per-unit
    b = (from = 0.00356, to = 0.00356), # Per-unit
    rating = 5.0, # Line rating of 200 MVA / System base of 100 MVA
    angle_limits = (min = -0.7, max = 0.7),
)

line2 = Line(;
    name = "line2",
    available = true,
    active_power_flow = 0.0,
    reactive_power_flow = 0.0,
    arc = Arc(; from = bus2, to = bus3),
    r = 0.00281, # Per-unit
    x = 0.0281, # Per-unit
    b = (from = 0.00356, to = 0.00356), # Per-unit
    rating = 5.0, # Line rating of 200 MVA / System base of 100 MVA
    angle_limits = (min = -0.7, max = 0.7),
)

add_components!(system,[bus1, bus2, bus3, line1, line2, wind1, load1,load2, gas, storage1])


power_data_load = "C:/Users/andrey.gorbunov/Sienna/Andrei_experiments/Julia_powerflow/3_bus_case/load_power_data.csv";  # Replace with actual file path
forecast_data_load = "C:/Users/andrey.gorbunov/Sienna/Andrei_experiments/Julia_powerflow/3_bus_case/load_forecast_data.csv";

power_data_wind = "C:/Users/andrey.gorbunov/Sienna/Andrei_experiments/Julia_powerflow/3_bus_case/wind_power_data.csv";  # Replace with actual file path
forecast_data_wind = "C:/Users/andrey.gorbunov/Sienna/Andrei_experiments/Julia_powerflow/3_bus_case/wind_forecast_data.csv";

power_data_load2 = "C:/Users/andrey.gorbunov/Sienna/Andrei_experiments/Julia_powerflow/3_bus_case/load2_power_data.csv";  # Replace with actual file path
forecast_data_load2 = "C:/Users/andrey.gorbunov/Sienna/Andrei_experiments/Julia_powerflow/3_bus_case/load2_forecast_data.csv";

#Get time time series and forecast for load
load_time_series, load_forecast_series = create_time_and_forecast_series(power_data_load, forecast_data_load, Dates.Minute(5))
wind_time_series, wind_forecast_series = create_time_and_forecast_series(power_data_wind, forecast_data_wind, Dates.Minute(5))
load2_time_series, load2_forecast_series = create_time_and_forecast_series(power_data_load2, forecast_data_load2, Dates.Minute(5))

add_time_series!(system, load1, load_time_series)
add_time_series!(system, load1, load_forecast_series)

add_time_series!(system, wind1, wind_time_series)
add_time_series!(system, wind1, wind_forecast_series)

add_time_series!(system, load2, load2_time_series)
add_time_series!(system, load2, load2_forecast_series)

system


print("try to solve")
solver = optimizer_with_attributes(
    HiGHS.Optimizer,
    "presolve" => "on",           # Enable presolve
    "time_limit" => 300.0         # Set a time limit of 300 seconds
)
println("Solver configured.")

# Step 1: Define the Problem Template
template_uc = ProblemTemplate()
set_device_model!(template_uc, Line, StaticBranch)
set_device_model!(template_uc, Transformer2W, StaticBranch)
set_device_model!(template_uc, TapTransformer, StaticBranch)

set_device_model!(template_uc, ThermalStandard, ThermalStandardUnitCommitment)
set_device_model!(template_uc, RenewableDispatch, RenewableFullDispatch)
set_device_model!(template_uc, PowerLoad, StaticPowerLoad)
set_device_model!(template_uc, HydroDispatch, HydroDispatchRunOfRiver)
set_device_model!(template_uc, RenewableNonDispatch, FixedOutput)
set_service_model!(template_uc, VariableReserve{ReserveUp}, RangeReserve)
set_service_model!(template_uc, VariableReserve{ReserveDown}, RangeReserve)
set_network_model!(template_uc, NetworkModel(CopperPlatePowerModel))
println("Problem template configured.")


# Addition of storage model
storage_model = DeviceModel(
    EnergyReservoirStorage,
    StorageDispatchWithReserves;
    attributes=Dict(
        "reservation" => true,
        "energy_target" => false,
        "cycling_limits" => false,
        "regulatization" => true,
    ),
)
set_device_model!(template_uc, storage_model)

# Step 2: Create the Decision Model
problem = DecisionModel(
    template_uc,
    system;
    optimizer = solver,
    horizon = Hour(1)  # 1-hour optimization horizon
)
println("Decision model created.")

# Step 3: Define the Simulation
start_time = DateTime("2023-06-01T00:00:00")  # Simulation start time
steps = 240  # Number of steps (e.g., simulate for 15 hours)
output_dir = mktempdir()

sim = Simulation(
    sequence = SimulationSequence(
        models = SimulationModels(decision_models = [problem])
    ),
    name = "My Simulation",
    steps = steps,  # Number of steps to simulate
    models = SimulationModels(decision_models = [problem]),
    initial_time = start_time,
    simulation_folder = mktempdir(cleanup = true)  # Temporary directory
)

# Step 4: Build and Run the Simulation
println("Building simulation in directory: $output_dir")
build!(sim)
println("Executing simulation...")
execute!(sim; enable_progress_bar = true)

# Step 5: Extract Results
results = SimulationResults(sim)

# Accessing simulation data
println(fieldnames(typeof(results)))
# Extract decision problem results

println(results.path)

DATApath = joinpath(results.path,"data_store","simulation_store.h5")
h5file = h5open(DATApath, "r") #Access model data
println(h5file)
renewable_dispatch_data = read(h5file["/simulation/decision_models/GenericOpProblem/variables/ActivePowerVariable__RenewableDispatch"]);
load_dispatch_data = read(h5file["/simulation/decision_models/GenericOpProblem/parameters/ActivePowerTimeSeriesParameter__PowerLoad"]);
thermal_dispatch_data =  read(h5file["/simulation/decision_models/GenericOpProblem/variables/ActivePowerVariable__ThermalStandard"])
renewable_with_battery_in = read(h5file["/simulation/decision_models/GenericOpProblem/variables/ActivePowerInVariable__EnergyReservoirStorage"]) 
renewable_with_battery_out = read(h5file["/simulation/decision_models/GenericOpProblem/variables/ActivePowerOutVariable__EnergyReservoirStorage"])


start_time = DateTime("2023-06-01T00:00:00")
resolution = Minute(5)  # 5-minute resolution
base_power = 100.0

time_line1,data_dispatch_wind = data_for_plotting(renewable_dispatch_data, 1, start_time,steps,resolution,base_power)
time_line2,data_dispatch_load1 = data_for_plotting(load_dispatch_data, 2, start_time,steps,resolution,base_power)
time_line3,data_dispatch_thermal = data_for_plotting(thermal_dispatch_data, 1, start_time,steps,resolution,base_power)
time_line4,data_dispatch_load2 = data_for_plotting(load_dispatch_data, 1, start_time,steps,resolution,base_power)
time_line5,data_storage_in = data_for_plotting(renewable_with_battery_in, 1, start_time,steps,resolution,base_power)
time_line6,data_storage_out = data_for_plotting(renewable_with_battery_out, 1, start_time,steps,resolution,base_power)
#plotting

plot(time_line1,data_dispatch_wind, xrotation = 90, xlabel="Time", ylabel="Power (MW)", label="wind")
plot!(time_line2,data_dispatch_load1, label = "load1")
plot!(time_line4,data_dispatch_load2, label = "load2")
plot!(time_line3,data_dispatch_thermal, label = "thermal")

plot(time_line5,data_storage_in, label = "storage_in", xrotation = 90, xlabel="Time", ylabel="Power (MW)")
plot!(time_line6, data_storage_out, label = "storage_out")
