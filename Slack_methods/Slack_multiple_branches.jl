using JuMP
using Ipopt
using PowerModels

# === GLOBAL SETTINGS ===
global slack_branch_ids = [1, 2]                  # Branches to apply slack to
global slack_branch_penalties = [1000.0, 500.0]   # Corresponding penalties

# === Load MATPOWER file ===
network = PowerModels.parse_file(joinpath(@__DIR__, "case9.m"))

# === Custom model builder ===
function build_opf_with_branch_slack(pm::AbstractPowerModel)
    build_opf(pm)

    global slack_branch_ids
    global slack_branch_penalties

    @variable(pm.model, slack_vars[branch_id in slack_branch_ids] >= 0)

    p_var = pm.var[:it][:pm][:nw][0][:p]
    q_var = pm.var[:it][:pm][:nw][0][:q]
    branch_data = pm.ref[:it][:pm][:nw][0][:branch]

    for (i, branch_id) in enumerate(slack_branch_ids)
        penalty = slack_branch_penalties[i]
        branch = branch_data[branch_id]
        f_bus = branch["f_bus"]
        t_bus = branch["t_bus"]
        s_max = branch["rate_a"]

        arc1 = (branch_id, f_bus, t_bus)
        arc2 = (branch_id, t_bus, f_bus)

        p1 = p_var[arc1]
        q1 = q_var[arc1]
        p2 = p_var[arc2]
        q2 = q_var[arc2]

        slack = slack_vars[branch_id]

        if p1 !== nothing && q1 !== nothing
            @constraint(pm.model, p1^2 + q1^2 <= (s_max + slack)^2)
        end
        if p2 !== nothing && q2 !== nothing
            @constraint(pm.model, p2^2 + q2^2 <= (s_max + slack)^2)
        end

        base_obj = JuMP.objective_function(pm.model)
        @objective(pm.model, Min, base_obj + penalty * slack)
    end

    pm.ext[:branch_slacks] = slack_vars
end

# === Instantiate and solve model ===
result = PowerModels.instantiate_model(
    network,
    ACPPowerModel,
    build_opf_with_branch_slack;
    jump_model = JuMP.Model(Ipopt.Optimizer)
)

optimize!(result.model)

# === Extract and print slack values ===
println("\nSlack Summary:")
for branch_id in slack_branch_ids
    slack_var = result.ext[:branch_slacks][branch_id]
    local slack_val = JuMP.value(slack_var)
    slack_display = isapprox(slack_val, 0.0; atol=1e-6) ? 0.0 : slack_val
    println("Branch $branch_id: slack = $slack_display")
end


# === Step 1: Apply slack upgrades to network ===
for (i, branch_id) in enumerate(slack_branch_ids)
    slack_val = JuMP.value(result.ext[:branch_slacks][branch_id])
    if isnan(slack_val)
        println("Warning: slack for branch $branch_id not defined (NaN)")
        continue
    end

    # Update network["branch"][branch_id]["rate_a"]
    branch_key = string(branch_id)
    old_rate = network["branch"][branch_key]["rate_a"]
    network["branch"][branch_key]["rate_a"] = old_rate + slack_val
    println("Updated Branch $branch_id rate_a: $old_rate → $(old_rate + slack_val)")
end

# === Step 2: Solve classical AC OPF on modified network ===
classic_result = PowerModels.solve_opf(
    network,
    ACPPowerModel,
    Ipopt.Optimizer
)

println("\n=== Classic OPF on Modified Network ===")
println("Objective: ", classic_result["objective"])
for (bid, data) in classic_result["solution"]["branch"]
    println("Branch $bid: pf = $(data["pf"]), qf = $(data["qf"])")
end
