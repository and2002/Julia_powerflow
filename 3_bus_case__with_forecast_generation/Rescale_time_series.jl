using CSV
using DataFrames
using Interpolations
using Dates
using Random
using Statistics

function resample_time_series_with_timestamps(file_path::String, column_name::String, start_time::DateTime, new_interval::Minute, original_interval::Minute)
    # Load the CSV file into a DataFrame
    df = CSV.read(file_path, DataFrame)

    # Ensure the column exists
    if !(column_name in names(df))
        error("Column '$column_name' not found in CSV file!")
    end

    # Extract data values using the column name as a string
    time_series = df[!, column_name]

    # Generate original timestamps
    original_time = [start_time + i * original_interval for i in 0:(length(time_series)-1)]

    # Generate new timestamps for resampling
    new_time = [start_time + i * new_interval for i in 0:round(Int, (original_time[end] - start_time) / new_interval)]

    # Convert timestamps to numerical values (seconds since start)
    original_seconds = [t - start_time for t in original_time] ./ Second(1)
    new_seconds = [t - start_time for t in new_time] ./ Second(1)

    # Create a linear interpolation function
    itp = extrapolate(interpolate((original_seconds,), time_series, Gridded(Linear())),  Interpolations.Line())

    # Interpolate data at new time points
    resampled_data = itp.(new_seconds)

    # Create a DataFrame with timestamps and resampled values
    new_df = DataFrame("Time" => new_time, column_name => resampled_data)

    return new_df
end

# Function to generate forecast
function create_forecast_with_noise(data_df::DataFrame, column_name::String, horizon::Int; noise_level=0.05)
    time_series = data_df[!, column_name]
    time_values = data_df.Time

    data_std = std(time_series)

    # ✅ Allocate a 2D matrix with Time in the first column
    forecast_matrix = Matrix{Float64}(undef, length(time_series), horizon + 1)

    for i in 1:length(time_series)
        forecast_matrix[i, 1] = time_series[i]  # First column = Actual value
        for j in 1:horizon
            future_index = i + j
            if future_index <= length(time_series)
                noise = noise_level * data_std * randn()
                predicted_value = time_series[future_index] + noise
            else
                predicted_value = NaN  # If out of bounds, set NaN
            end
            forecast_matrix[i, j+1] = predicted_value
        end
    end

    # ✅ Set column names with "Time" first
    col_names = vcat(["Time"], ["Actual"], ["Horizon_$i" for i in 1:horizon])
    
    # ✅ Create DataFrame and insert timestamps as the first column
    forecast_df = DataFrame(forecast_matrix, col_names[2:end])  # Start with actual & horizons
    forecast_df[!, "Time"] = time_values  # Add timestamps

    # ✅ Ensure "Time" is the FIRST column
    select!(forecast_df, "Time", col_names[2:end]...)  

    return forecast_df
end

function process_time_series_files(directory_path::String, time_series_files::Vector{String}, forecast_files::Vector{String}, 
    column_name::String, start_time::DateTime, original_interval::Minute, 
    new_interval::Minute, horizon::Int; noise_level=0.05)

# Ensure the number of input files matches the forecast output files
if length(time_series_files) != length(forecast_files)
error("Mismatch: Number of time series files and forecast files must be the same!")
end

for (i, file) in enumerate(time_series_files)
input_file = joinpath(directory_path, file)  # Full path for input
output_file = joinpath(directory_path, forecast_files[i])  # Full path for forecast output

println("Processing file: $input_file")

# Step 1: Resample time series
resampled_df = resample_time_series_with_timestamps(input_file, column_name, start_time, new_interval, original_interval)

# Step 2: Generate forecast with noise
forecast_df = create_forecast_with_noise(resampled_df, column_name, horizon; noise_level=noise_level)

# Step 3: Save forecast to CSV
CSV.write(output_file, forecast_df)
println("Saved forecast to: $output_file")
end
end


# Define directory containing time series data
directory_path = "C:/Users/andre/Desktop/Julia_code_main_directory/Small_case_redo_forecast"

# List of input time series files
time_series_files = ["load_power_data.csv", "wind_power_data.csv", "load2_power_data.csv"]

# Corresponding forecast output filenames
forecast_files = ["load_forecast_data.csv", "wind_forecast_data.csv", "load2_forecast_data.csv"]

# Define settings
column_name = "Power (MW)"  # Column to process
start_time = DateTime("2023-06-01T00:00:00")
original_interval = Minute(5)  # Original time step
new_interval = Minute(60)  # Resample to hourly
horizon = 6  # Forecast horizon
noise_level = 0.05  # 5% noise

# Run batch processing
process_time_series_files(directory_path, time_series_files, forecast_files, 
                          column_name, start_time, original_interval, new_interval, horizon; 
                          noise_level=noise_level)