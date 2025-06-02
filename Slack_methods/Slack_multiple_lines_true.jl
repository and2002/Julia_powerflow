using JuMP
using HiGHS       # Use HiGHS for LP
using PowerModels

# === GLOBAL SETTINGS ===
const slack_branch_ids = [1, 2, 3]                     # Branches to apply slack to
const slack_branch_penalties = [1e6, 1e6, 1e6]         # Flat high penalties to discourage slack

# === Load MATPOWER file ===
network_original = PowerModels.parse_file(joinpath(@__DIR__, "case9.m"))

function update_network_branches(network) # function takes network and updates selected branches with higher ratings
    global slack_branch_ids
    network_m = network
    for (id,branch) in enumerate(network_m["branch"])
        println(id)
        if id in slack_branch_ids
            
            network_m["branch"][string(id)]["rate_a"] = network_m["branch"][string(id)]["rate_a"] + 10 # update its capacity
        end
    end
    return network_m
end
# === Custom model builder ===
function build_opf_with_branch_slack(pm::AbstractPowerModel)
    build_opf(pm)

    @variable(pm.model, slack_vars[branch_id in slack_branch_ids] >= 0)

    p_var = pm.var[:it][:pm][:nw][0][:p]
    branch_data = pm.ref[:it][:pm][:nw][0][:branch]

    slack_penalty_terms = []

    for (i, branch_id) in enumerate(slack_branch_ids)
        penalty = slack_branch_penalties[i]
        branch = branch_data[branch_id]

        f_bus = branch["f_bus"]
        t_bus = branch["t_bus"]
        s_max = branch["rate_a"] - 10

        arc1 = (branch_id, f_bus, t_bus)
        arc2 = (branch_id, t_bus, f_bus)
        println(arc1)
        println(arc2)
        println(s_max)
        if haskey(p_var, arc1)
            @constraint(pm.model, p_var[arc1] <= s_max + slack_vars[branch_id])
            @constraint(pm.model, p_var[arc1] >= -s_max - slack_vars[branch_id])
        end
        if haskey(p_var, arc2)
            @constraint(pm.model, p_var[arc2] <= s_max + slack_vars[branch_id])
            @constraint(pm.model, p_var[arc2] >= -s_max - slack_vars[branch_id])
        end

        push!(slack_penalty_terms, penalty * slack_vars[branch_id])
    end

    base_obj = JuMP.objective_function(pm.model)
    @objective(pm.model, Min, base_obj + sum(slack_penalty_terms))

    pm.ext[:branch_slacks] = slack_vars
end

raw_result = PowerModels.solve_opf(
    network_original,
    DCPPowerModel,
    HiGHS.Optimizer
)
println(raw_result)

network_modified = update_network_branches(network_original) # create copy for with relaxed power flow
# === Instantiate and solve model ===
result = PowerModels.instantiate_model(
    network_modified,
    DCPPowerModel,
    build_opf_with_branch_slack;
    jump_model = JuMP.Model(HiGHS.Optimizer)
)
println("\n=== Decision Variables Before Solve ===")
for constr in all_constraints(result.model; include_variable_in_set_constraints=true)
    println("Name: ", name(constr))
    println("  Expression: ", constraint_object(constr).func)
    println("  Set: ", constraint_object(constr).set)
end


optimize!(result.model)

# === Extract and print slack values ===
println("\nSlack Summary:")
for branch_id in slack_branch_ids
    slack_var = result.ext[:branch_slacks][branch_id]
    slack_val = JuMP.value(slack_var)
    slack_display = isapprox(slack_val, 0.0; atol=1e-6) ? 0.0 : slack_val
    println("Branch $branch_id: slack = $slack_display")
end

# === Apply slack upgrades to network ===
for branch_id in slack_branch_ids
    slack_val = JuMP.value(result.ext[:branch_slacks][branch_id])
    if isnan(slack_val)
        println("Warning: slack for branch $branch_id is NaN")
        continue
    end
    branch_key = string(branch_id)
    old_rate = network_original["branch"][branch_key]["rate_a"]
    network_original["branch"][branch_key]["rate_a"] = old_rate + slack_val
    println("Updated Branch $branch_id rate_a: $old_rate → $(old_rate + slack_val)")
end

# === Solve classic OPF on updated network ===
classic_result = PowerModels.solve_opf(
    network_original,
    DCPPowerModel,
    HiGHS.Optimizer
)

println("\n=== Classic OPF on Modified Network ===")
println("Objective: ", classic_result["objective"])
for (bid, data) in classic_result["solution"]["branch"]
    println("Branch $bid: pf = $(data["pf"])")
end
