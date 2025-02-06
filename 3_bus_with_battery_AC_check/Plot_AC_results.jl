using DataFrames
using CSV
using Plots

file_adress = "C:/Users/andre/Desktop/Julia_code_main_directory/Troubleshoot_small_case/optimization_results/AC_solution.csv"

power_data = CSV.read(file_adress, DataFrame)
gas_genP = power_data["Pgas"]