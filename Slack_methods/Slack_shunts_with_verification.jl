using PowerModels
using JuMP
using Ipopt

function add_shunt_by_bus_number_checked(network_data::Dict{String, Any}, bus_number::Int, Q_pu::Float64)
    # Find internal bus ID matching given MATPOWER bus number
    bus_id = nothing
    for (k, bus) in network_data["bus"]
        if bus["bus_i"] == bus_number
            bus_id = k
            break
        end
    end
    bus_id === nothing && error("Bus number $bus_number not found in network.")
    println("Bus found")
    # Ensure "shunt" section exists
    if !haskey(network_data, "shunt")
        network_data["shunt"] = Dict{String, Any}()
    end

    # Search for existing shunt at this bus
    existing_shunt_id = nothing
    for (shunt_id, shunt_data) in network_data["shunt"]
        println(shunt_data)
        if shunt_data["shunt_bus"] == parse(Int, bus_id)
            existing_shunt_id = shunt_id
            println("shunt found")
            break
        end
    end

    # Create new or updated shunt entry
    shunt_entry = Dict(
        "source_id" => ["bus", parse(Int, bus_id)],
        "shunt_bus" => parse(Int, bus_id),
        "status" => 1,
        "gs" => 0.0,
        "bs" => Q_pu,
        "index" => existing_shunt_id === nothing ? length(network_data["shunt"]) + 1 : parse(Int, existing_shunt_id)
    )

    # Add or update the shunt
    if existing_shunt_id !== nothing
        network_data["shunt"][existing_shunt_id] = shunt_entry
    else
        next_shunt_id = string(length(network_data["shunt"]) + 1)
        network_data["shunt"][next_shunt_id] = shunt_entry
    end

    return network_data
end

println("START")
# === Load MATPOWER case ===
network_data  = PowerModels.parse_file(joinpath(@__DIR__,"case9.m"))
network_data_copy = deepcopy(network_data)
# === Select candidate buses ===
candidate_buses = [1, 2, 3, 4]  # bus numbers
generator_q = [] # array would store generators for q Compensation 
penalty = [10e6, 10e6, 10e6, 10e6] # penalty
Q_LIMIT = 10.0  # 1 GVAr in p.u.

# === Add reactive-only generators at selected buses ===
next_gen_id = string(maximum(parse.(Int, keys(network_data["gen"]))))
for (i, bus_id) in enumerate(candidate_buses)
    gen_id = string(parse(Int, next_gen_id) + i)
    network_data["gen"][gen_id] = Dict(
        "bus" => bus_id,
        "pg" => 0.0,
        "qg" => 0.0,
        "qmax" => Q_LIMIT,
        "qmin" => -Q_LIMIT,
        "pmax" => 0.0,
        "pmin" => 0.0,
        "gen_status" => 1,
        "gen_bus" => bus_id,
        "vg" => 1.0,
        "mbase" => 100.0,
        "startup" => 0.0,
        "shutdown" => 0.0,
        "model" => 2,
        "ncost" => 2,
        "cost" => [0.0, 0.0],  # or your actual cost
        "source_id" => ["gen", parse(Int, gen_id)],
        "index" => parse(Int, gen_id)
    )
    push!(generator_q, parse(Int, gen_id))
end
println(network_data)
println(generator_q)
# === Custom OPF model builder ===
function build_q_slack_model(pm::AbstractPowerModel)
    build_opf(pm)

    global generator_q
    global penlaty

    @variable(pm.model, slack_pos[gen_id in generator_q] >= 0)  # s⁺
    @variable(pm.model, slack_neg[gen_id in generator_q] >= 0)  # s⁻
    slack_penalty_terms = []
    q_var = pm.var[:it][:pm][:nw][0][:qg]
    println(q_var)
    for (i, gen_id) in enumerate(generator_q)

        qg = q_var[gen_id]

        # Replace qg by s⁺ - s⁻
        @constraint(pm.model, qg == slack_pos[gen_id] - slack_neg[gen_id])

        # Add both penalties (you could weight them differently)
        push!(slack_penalty_terms, penlaty[i] * (slack_pos[gen_id] + slack_neg[gen_id]))
    end

    @objective(pm.model, Min, sum(slack_penalty_terms))

    # Store for postprocessing
    pm.ext[:gen_slack_pos] = slack_pos
    pm.ext[:gen_slack_neg] = slack_neg
end


# === Solve the model ===
result = PowerModels.instantiate_model(
    network_data,
    ACPPowerModel,
    build_q_slack_model;
    jump_model = JuMP.Model(Ipopt.Optimizer)
)
optimize!(result.model)

# === Display results ===
println("\nReactive Compensation Breakdown:")

for (i, gen_id) in enumerate(generator_q)
    global network_data
    global network_data_copy
    q_val = 0 #value(result.var[:qg][gen_id])
    s_pos = value(result.ext[:gen_slack_pos][gen_id])
    s_neg = value(result.ext[:gen_slack_neg][gen_id])
    net_q = round(q_val, digits=3)
    cap = round(s_pos, digits=3)
    ind = round(s_neg, digits=3)
    println("Gen $gen_id (Bus $(network_data["gen"][string(gen_id)]["gen_bus"])): Qg = $net_q ( +Q = $cap, -Q = $ind )")
    # now, adjust original system
    q_compensation =0 
    if s_pos > 0
        q_compensation = s_pos
    else
        q_compensation = -s_neg
    end
    network_data_copy = add_shunt_by_bus_number_checked(network_data_copy, network_data["gen"][string(gen_id)]["bus"], q_compensation)
end

println(network_data_copy)
classic_result = PowerModels.solve_opf(
    network_data_copy,
    ACPPowerModel,
    Ipopt.Optimizer
)
println(classic_result)
