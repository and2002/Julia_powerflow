
using PowerModels
using JuMP
using Ipopt

function optimize_susceptance_adjustment(network_data)
    model = Model(Ipopt.Optimizer)

    # Initialize 'bs' if missing in the dataset
    for b in keys(network_data["bus"])
        if !haskey(network_data["bus"][b], "bs")
            network_data["bus"][b]["bs"] = 0.0  # Initialize 'bs' to zero
        end
    end

    # Add variables for additional susceptance (Bs) at each bus
    @variable(model, Bs[b in keys(network_data["bus"])] >= 0)

    # Add Bs to the bus data directly (PowerModels will now use these)
    for b in keys(network_data["bus"])
        network_data["bus"][b]["bs"] += Bs[b]
    end

    # Instantiate the PowerModels model
    PowerModels.instantiate_model(network_data, ACPPowerModel, model, build_opf)

    # Objective: Minimize total added susceptance
    @objective(model, Min, sum(Bs[b] for b in keys(network_data["bus"])))

    optimize!(model)

    # Extract results
    results = value.(Bs)
    return results
end

# Load the network data

network_data = PowerModels.parse_file("C:/Users/andre/Desktop/Julia_code_main_directory/case9.m")

# Run the compensation optimization
compensation_results = optimize_reactive_compensation(network_data)
println("Optimal Reactive Compensation per Bus: ", compensation_results)
