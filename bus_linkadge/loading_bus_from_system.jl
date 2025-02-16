using PowerSystems
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
# the idea of this code is to set busses first and then import them from system to assign lines, transformers to them inderectly by numbers
system_base_power = 100.0
system = System(system_base_power, frequency = 50.0)# 100 MVA base power

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

add_components!(system, [bus1, bus2, bus3])

# Function to find a bus by its number
function find_bus_by_number(sys::System, bus_number::Int)
    for bus in get_components(ACBus, sys)
        if bus.number == bus_number
            return bus
        end
    end
    error("Bus with number $bus_number not found")
end

# Bus numbers to connect
bus_number_from = 1
bus_number_to = 2

# Find the actual bus objects
from_bus = find_bus_by_number(system, bus_number_from)
to_bus = find_bus_by_number(system, bus_number_to)

new_line = Line(
    name="Line_1_2",
    available=true,
    active_power_flow=0.0,
    reactive_power_flow=0.0,
    arc=Arc(;from = from_bus,to = to_bus),
    r=0.01,  # Resistance (p.u.)
    x=0.1,   # Reactance (p.u.)
    b=(from=0.0, to=0.0), # Shunt susceptance
    rating=1.0,  # MVA rating
    angle_limits=(min=-30.0, max=30.0) # Angle limit in degrees
)

# Add the new line to the system
add_component!(system, new_line)
file_path = joinpath(@__DIR__,"test_system.json")
to_json(system, file_path; force=true)  # `force=true` allows overwriting an existing file
