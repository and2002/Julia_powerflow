using DataFrames
using CSV
using Plots

file_adress = "C:/Users/andre/Desktop/Julia_code_main_directory/Small_case_redo_forecast/optimization_results"

power_data = CSV.read(joinpath(file_adress,"AC_solution.csv"), DataFrame)
gas_genP = power_data[!,"Pgas"]
gas_genQ = power_data[!,"Qgas"]
wind_genP = power_data[!,"Pwind"]
wind_genQ = power_data[!,"Qwind"]
batP = power_data[!,"Pbat"]
batQ = power_data[!,"Qbat"]
Bat_state_of_charge = power_data[!,"State_of_charge"]

plot(gas_genP,ylabel="active power (pu)", label="Gas generator")
plot!(wind_genP,label ="wind generator")
plot!(batP, label = "battery discharge")
savefig(joinpath(file_adress,"plots","active_power.png"))

plot(gas_genQ,ylabel="reactive power (pu)", label="Gas generator")
plot!(wind_genQ,label ="wind generator")
plot!(batQ, label = "battery discharge")
savefig(joinpath(file_adress,"plots","reactive_power.png"))

plot(Bat_state_of_charge,ylabel="State of charge,(pu)", label="Bttery")
savefig(joinpath(file_adress,"plots","State of charge.png"))