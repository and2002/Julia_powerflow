using PowerSystems

system_base_power = 100.0
system = System(system_base_power, frequency = 50.0)# 100 MVA base power

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

system = System(100.0, frequency = 50.0)# 100 MVA base power, 50 Hz frequency

bus1 = ACBus(;
    number = 102,
    name = "102",
    bustype = ACBusTypes.REF,
    angle = 0.0,
    magnitude = 1.0,
    voltage_limits = (min = 0.9, max = 1.05),
    base_voltage = 110.0,
);

bus2 = ACBus(;
    number = 103,
    name = "103",
    bustype = ACBusTypes.PV,
    angle = 0.0,
    magnitude = 1.0,
    voltage_limits = (min = 0.9, max = 1.05),
    base_voltage = 110.0,
);

bus3 = ACBus(;
    number = 104,
    name = "104",
    bustype = ACBusTypes.PQ,
    angle = 0.0,
    magnitude = 1.0,
    voltage_limits = (min = 0.9, max = 1.05),
    base_voltage = 110.0,
);

bus4 = ACBus(;
    number = 101,
    name = "101",
    bustype = ACBusTypes.PQ,
    angle = 0.0,
    magnitude = 1.0,
    voltage_limits = (min = 0.9, max = 1.05),
    base_voltage = 330.0,
);

bus5 = ACBus(;
    number = 201,
    name = "201",
    bustype = ACBusTypes.PQ,
    angle = 0.0,
    magnitude = 1.0,
    voltage_limits = (min = 0.9, max = 1.05),
    base_voltage = 330.0,
);

bus6 = ACBus(;
    number = 202,
    name = "202",
    bustype = ACBusTypes.PQ,
    angle = 0.0,
    magnitude = 1.0,
    voltage_limits = (min = 0.9, max = 1.05),
    base_voltage = 110.0,
);

bus7 = ACBus(;
    number = 203,
    name = "203",
    bustype = ACBusTypes.PQ,
    angle = 0.0,
    magnitude = 1.0,
    voltage_limits = (min = 0.9, max = 1.05),
    base_voltage = 110.0,
);

bus8 = ACBus(;
    number = 204,
    name = "204",
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
    arc = PowerSystems.Arc(; from = bus3, to = bus4),
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
    arc = PowerSystems.Arc(; from = bus5, to = bus6),
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
    arc = PowerSystems.Arc(; from = bus1, to = bus3),
    r = 0.0001, # Per-unit
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
    arc = PowerSystems.Arc(; from = bus2, to = bus3),
    r = 0.0001, # Per-unit
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
    arc = PowerSystems.Arc(; from = bus4, to = bus5),
    r = 0.0001, # Per-unit
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
    arc = PowerSystems.Arc(; from = bus6, to = bus7),
    r = 0.0001, # Per-unit
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
    arc = PowerSystems.Arc(; from = bus6, to = bus8),
    r = 0.0001, # Per-unit
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

save_system_to_json(system,"test_system",@__DIR__)