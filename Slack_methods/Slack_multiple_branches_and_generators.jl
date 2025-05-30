using JuMP
using Ipopt
using PowerModels

# === GLOBAL SETTINGS ===
const slack_branch_ids = [1, 2]
const slack_branch_penalties = [1000.0, 500.0]

const gen_slack_ids = [1, 2]
const gen_slack_penalties = [10000.0, 12000.0]  # Penalty for each extra MW

# === Load MATPOWER file ===
network = PowerModels.parse_file(joinpath(@__DIR__, "case9.m"))

# === Custom model builder with branch + generator slack ===
function build_opf_with_slack(pm::AbstractPowerModel)
    build_opf(pm)

    # Branch slack variables
    @variable(pm.model, branch_slack_vars[branch_id in slack_branch_ids] >= 0)
    pm.ext[:branch_slack_vars] = branch_slack_vars

    # Generator slack variables
    @variable(pm.model, gen_slack_vars[gen_id in gen_slack_ids] >= 0)
    pm.ext[:gen_slack_vars] = gen_slack_vars

    p_var = pm.var[:it][:pm][:nw][0][:p]
    q_var = pm.var[:it][:pm][:nw][0][:q]
    pg_var = pm.var[:it][:pm][:nw][0][:pg]
    branch_data = pm.ref[:it][:pm][:nw][0][:branch]
    gen_data = pm.ref[:it][:pm][:nw][0][:gen]

    # === Branch Slack Constraints ===
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

        slack = branch_slack_vars[branch_id]

        @constraint(pm.model, p1^2 + q1^2 <= (s_max + slack)^2)
        @constraint(pm.model, p2^2 + q2^2 <= (s_max + slack)^2)

        base_obj = JuMP.objective_function(pm.model)
        @objective(pm.model, Min, base_obj + penalty * slack)
    end

    # === Generator Slack Constraints ===
    for (i, gen_id) in enumerate(gen_slack_ids)
        penalty = gen_slack_penalties[i]
        slack = gen_slack_vars[gen_id]

        pg = pg_var[gen_id]
        pmax = gen_data[gen_id]["pmax"]

        # Allow pg to go above pmax + slack
        @constraint(pm.model, pg <= pmax + slack)

        base_obj = JuMP.objective_function(pm.model)
        @objective(pm.model, Min, base_obj + penalty * slack)
    end
end

# === Instantiate and solve model ===
result = PowerModels.instantiate_model(
    network,
    ACPPowerModel,
    build_opf_with_slack;
    jump_model = JuMP.Model(Ipopt.Optimizer)
)

optimize!(result.model)

# === Report Results ===
println("\nSlack Summary:")

println("Branch Slack:")
for branch_id in slack_branch_ids
    slack_var = result.ext[:branch_slack_vars][branch_id]
    local slack_val = JuMP.value(slack_var)
    slack_display = isapprox(slack_val, 0.0; atol=1e-6) ? 0.0 : slack_val
    println("  Branch $branch_id: slack = $slack_display")
end

println("\nGenerator Slack:")
for gen_id in gen_slack_ids
    slack_var = result.ext[:gen_slack_vars][gen_id]
    local slack_val = JuMP.value(slack_var)
    slack_display = isapprox(slack_val, 0.0; atol=1e-6) ? 0.0 : slack_val
    println("  Generator $gen_id: slack = $slack_display")
end