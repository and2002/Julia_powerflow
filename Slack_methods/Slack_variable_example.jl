using JuMP
using Ipopt
using PowerModels

# === Load MATPOWER file ===
network = PowerModels.parse_file(joinpath(@__DIR__, "case9.m"))

# === Custom model builder ===
function build_opf_with_branch_slack(pm::AbstractPowerModel)
    build_opf(pm)

    branch_id = 1
    penalty = 1000.0

    # Access full model variable tree
    p_var = pm.var[:it][:pm][:nw][0][:p]
    q_var = pm.var[:it][:pm][:nw][0][:q]
    branch = pm.ref[:it][:pm][:nw][0][:branch][branch_id]
    f_bus = branch["f_bus"]
    t_bus = branch["t_bus"]
    s_max = branch["rate_a"]
    println(p_var)
    # Access real and reactive flow variables
    p1 = p_var[(branch_id, f_bus, t_bus)]
    q1 = q_var[(branch_id, f_bus, t_bus)]
    p2 = p_var[(branch_id, t_bus, f_bus)]
    q2 = q_var[(branch_id, t_bus, f_bus)]

    # Add slack and constraint
    slack = @variable(pm.model, slack >= 0, base_name="branch_slack")
    pm.ext[:branch_slack] = slack  # <=== store it for later access

    @constraint(pm.model, p1^2 + q1^2 <= (s_max + slack)^2)
    @constraint(pm.model, p2^2 + q2^2 <= (s_max + slack)^2)

    base_obj = objective_function(pm.model)
    @objective(pm.model, Min, base_obj + penalty * slack)
end

# === Solve OPF ===
result = PowerModels.instantiate_model(
    network,
    ACPPowerModel,
    build_opf_with_branch_slack;
    optimizer=Ipopt.Optimizer
)

optimize!(result["model"])
slack_val = JuMP.value(result["ext"][:branch_slack])
println("Slack used: ", slack_val)
