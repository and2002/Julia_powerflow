using DataFrames
using CSV
using Plots

input_adress = "C:/Users/andre/Desktop/Julia_code_main_directory/Troubleshoot_small_case"
output_adress = "C:/Users/andre/Desktop/Julia_code_main_directory/Troubleshoot_small_case/optimization_results"

load1_input = CSV.read(joinpath(input_adress,"load_power_data.csv"),DataFrame)
load1_output = CSV.read(joinpath(output_adress,"DF_load1.csv"),DataFrame)
load1_input_array = load1_input[:,2]
load1_output_array = load1_output[:,1]
delta_load1_array = load1_input_array[1:240] - load1_output_array
relative_delta1 = delta_load1_array ./ load1_input_array[1:240]

load2_input = CSV.read(joinpath(input_adress,"load2_power_data.csv"),DataFrame)
load2_output = CSV.read(joinpath(output_adress,"DF_load2.csv"),DataFrame)
load2_input_array = load2_input[:,2]
load2_output_array = load2_output[:,1]
delta_load2_array = load2_input_array[1:240] - load2_output_array
relative_delta2 = delta_load2_array ./ load2_input_array[1:240]

plot(relative_delta1)