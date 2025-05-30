using JuMP
using Ipopt
using PowerModels

# ========== STEP 1: Load MATPOWER file ==========
network = PowerModels.parse_file(joinpath(@__DIR__, "case9.m"))
network["gen"]["2"]["rate_a"] = 999.0
println(network["branch"]["1"]["rate_a"])
global gen_ids = [2]
# ========== STEP 2: Define allowed PF for generator 2 ==========
function add_pf_constraints!(
    pm::AbstractPowerModel # model
    )
    global gen_ids # array of generators
    N_gen = length(gen_ids)
    for i = 1:N_gen

    gen_id = gen_ids[i] # Integer index of generator
    pf_min = 1.0
    s_max = 100
    θmax = tan(acos(pf_min))
    println(θmax)
    pg = pm.var[:it][:pm][:nw][0][:pg]
    qg = pm.var[:it][:pm][:nw][0][:qg]

    p = pg[gen_id]
    q = qg[gen_id]

    gen_key = string(gen_id)
    #smax = sqrt(pm.ref[:gen][gen_key]["pmax"]^2 + pm.ref[:gen][gen_key]["qmax"]^2)

    @constraint(pm.model, p^2 + q^2 <= s_max^2)
    @constraint(pm.model, q <=  p * θmax)
    @constraint(pm.model, q >= -p * θmax)
    end
end

# ========== STEP 4: Solve ==========
function solve_auto(network)
    result = PowerModels.solve_model(
        network,
        ACPPowerModel,
        optimizer_with_attributes(Ipopt.Optimizer),
        build_opf_with_pf_limited_gen
    )
    return result
    end

# ========== STEP 3: Custom model builder ==========
function build_opf_with_pf_limited_gen(pm::AbstractPowerModel)
    build_opf(pm)
    add_pf_constraints!(pm)
end

result = solve_auto(network)

#result2 = solve_model(network,ACPPowerModel)
# ========== STEP 5: Output ==========
println("Objective: ", result["objective"])
println("Generator 1 output (P, Q): ", result["solution"]["gen"]["1"])
println("Generator 2 output (P, Q): ", result["solution"]["gen"]["2"])

result2 = solve_opf(network, ACPPowerModel, Ipopt.Optimizer)
println(result2["solution"]["gen"]["1"])
println(result2["solution"]["gen"]["2"])