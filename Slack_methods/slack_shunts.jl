using PowerModels
using JuMP
using Ipopt

# === Load MATPOWER case ===
network_data = PowerModels.parse_file(joinpath(@__DIR__,"case9.m"))

# === Select candidate buses ===
candidate_buses = [1, 2, 3, 4]  # bus numbers
generator_q = [] # array would store generators for q Compensation 
penalties = [10e6, 10e6, 10e6, 10e6] # penalty
Q_LIMIT = 10.0  # 1 GVAr in p.u.

# === Add reactive-only generators at selected buses ===
next_gen_id = string(maximum(parse.(Int, keys(network_data["gen"])))+1)
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
    global penalties 
    
    @variable(pm.model, slack_vars[gen_id in generator_q] >= 0)

    slack_penalty_terms = []

    q_var = pm.var[:it][:pm][:nw][0][:qg]
    for (i,gen_id) in enumerate(generator_q)
        penalty = penalties[i]
        # Get corresponding generator variable
        qg = q_var[gen_id]
        # Add constraint: -s ≤ qg ≤ s
        @constraint(pm.model, qg <= slack_vars[gen_id])
        @constraint(pm.model, qg >= -slack_vars[gen_id])

        push!(slack_penalty_terms, penalty * slack_vars[gen_id])
    end

    base_obj = JuMP.objective_function(pm.model)
    @objective(pm.model, Min, base_obj + sum(slack_penalty_terms))

    pm.ext[:gen_slacks] = slack_vars
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
println("\nSlack Summary:")
for (i,gen_id) in enumerate(generator_q)
    # recall bus and fenerator
    gen_bus = candidate_buses[i]
    slack_var = result.ext[:gen_slacks][gen_id]
    slack_val = JuMP.value(slack_var)
    slack_display = isapprox(slack_val, 0.0; atol=1e-6) ? 0.0 : slack_val
    println("Bus $gen_bus: slack = $slack_display")
end
