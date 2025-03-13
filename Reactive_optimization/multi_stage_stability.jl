using PowerModels
using JuMP
using Ipopt
using NLopt
using Revise
# Step 1: Initial OPF Attempt with Enhanced Feasibility Check
function initial_opf_attempt(network_data)
    result = solve_opf(network_data, ACPPowerModel, Ipopt.Optimizer)
    println(result["termination_status"])
    # Improved feasibility check to handle "LOCALLY_SOLVED"
    if string(result["termination_status"]) in ["OPTIMAL", "LOCALLY_SOLVED"]
        println("✅ OPF Feasible on First Try — No Further Action Needed")
        return result  # Problem solved without adjustments
    else
        println("❗️ OPF Infeasible — Proceeding with Generator Q Expansion...")
        return nothing  # Continue to step 2
    end
end

# Step 2: Increase Generator Limits for Feasibility Recovery
function increase_generator_limits!(network_data)
    for (_, gen) in network_data["gen"]
        gen["qmax"] = 10.0
        gen["qmin"] = -10.0
    end
end

# Step 3: Identify Initial Bs Values Based on Generator Q Output and Limits
function determine_initial_bs(network_data, feasible_result)
    total_ΔQ = 0.0
    generator_buses = Set{String}()

    # Step 1: Calculate total ΔQ only for generator buses
    for (gen_id, gen) in network_data["gen"]
        q_actual = feasible_result["solution"]["gen"][gen_id]["qg"]
        q_max = gen["qmax"]
        q_min = gen["qmin"]
        bus_id = string(gen["gen_bus"])

        # Track generator buses for compensation placement
        push!(generator_buses, bus_id)

        # Determine required ΔQ for this generator bus
        if q_actual > 0  # Positive Q → Check proximity to Qmax
            ΔQ = q_actual - q_max
        elseif q_actual < 0  # Negative Q → Check proximity to Qmin
            ΔQ = q_actual - q_min
        else
            ΔQ = 0.0
        end

        # Accumulate total ΔQ
        total_ΔQ += abs(ΔQ)
    end

    # Step 2: Spread total ΔQ across all buses (even distribution)
    num_buses = length(network_data["bus"])
    initial_Bs = Dict(b => total_ΔQ / num_buses for b in keys(network_data["bus"]))

    println("📊 Improved Initial `Bs` Vector (Based on Spread Q Demand): ", initial_Bs)
    return initial_Bs
end

# Step 4: Final Optimization Near Initial Bs Values
function final_bs_optimization(network_data, initial_Bs; max_iter=50, tolerance=1e-5)
    initial_Bs_vec = [initial_Bs[string(b)] for b in keys(network_data["bus"])]

    lb = fill(0.0, length(initial_Bs_vec))     
    ub = fill(0.15, length(initial_Bs_vec))    

    # Objective Function (Minimize Total Bs)
    function objective_function(Bs_vec, grad)
    # Update Bs values in the network
    for (i, b) in enumerate(keys(network_data["bus"]))
        network_data["bus"][b]["bs"] = Bs_vec[i]
    end

    # Run OPF with updated Bs
    result = solve_opf(network_data, ACPPowerModel, Ipopt.Optimizer)

    # Adaptive penalty system
    penalty = 0.0
    if result["termination_status"] != MathOptInterface.OPTIMAL
        for (g, gen_data) in result["solution"]["gen"]
            q_actual = gen_data["qg"]
            q_min = network_data["gen"][g]["qmin"]
            q_max = network_data["gen"][g]["qmax"]

            # Penalize deviation from limits
            if q_actual < q_min
                penalty += abs(q_min - q_actual)  # Exceeded lower limit
            elseif q_actual > q_max
                penalty += abs(q_actual - q_max)  # Exceeded upper limit
            end
        end
    end

    # Objective: Minimize total Bs + scaled penalty
    return sum(Bs_vec) + 10 * penalty
    end
    # NLopt Setup
    opt = Opt(:LN_COBYLA, length(initial_Bs_vec))  
    opt.lower_bounds = lb
    opt.upper_bounds = ub
    opt.min_objective = objective_function

    # Run the optimizer
    (final_Bs, min_cost, ret) = optimize(opt, initial_Bs_vec)

    println("✅ Final Optimized Bs Values: ", final_Bs)
    println("🔎 Final Cost (Total Bs): ", min_cost)
end

# Step 5: Combined Function to Manage the Full Process
function optimize_susceptance_adjustment(network_data)
    # Step 1: Try OPF with Original Limits
    feasible_result = initial_opf_attempt(deepcopy(network_data))
    if feasible_result !== nothing  # Problem solved, exit early
        return
    end

    # Step 2: Expand Generator Limits to Force Feasibility
    increase_generator_limits!(network_data)

    # Step 3: Solve OPF with Expanded Limits
    expanded_result = solve_opf(network_data, ACPPowerModel, Ipopt.Optimizer)
    if expanded_result["termination_status"] != "OPTIMAL"
        println("❌ Even Expanded Limits Failed — System Likely Unsalvageable")
        return
    end

    # Step 4: Determine Bs Adjustments
    initial_Bs = determine_initial_bs(network_data, expanded_result)

    # Step 5: Refine Bs Values with Optimizer
    final_bs_optimization(network_data, initial_Bs)
end
revise()
# Load the network data
network_data1 = PowerModels.parse_file("C:/Users/andre/Desktop/Julia_code_main_directory/case9.m")
println(network_data1)

# Run the optimization
optimize_susceptance_adjustment(network_data1)

println("_____")
results = solve_opf(network_data1 ,ACPPowerModel, Ipopt.Optimizer)
println(results)
