using PlotlyJS

function parse_eta_log(filepath::String)
    eta_seconds = Int[]
    open(filepath, "r") do file
        for line in eachline(file)
            if occursin("ETA:", line)
                # Remove "ETA:" prefix and any trailing text
                content = match(r"ETA:\s*([^|\n\r]+)", line)
                if content !== nothing
                    eta_str = strip(content.captures[1])
                    
                    # Case 1: "1 days, 22:00:45"
                    if occursin("days,", eta_str)
                        m = match(r"(\d+)\s+days,\s*(\d+):(\d+):(\d+)", eta_str)
                        if m !== nothing
                            d, h, m_, s = parse.(Int, m.captures)
                            total = d * 86400 + h * 3600 + m_ * 60 + s
                            push!(eta_seconds, total)
                        end

                    # Case 2: "12.8 days"
                    elseif occursin("days", eta_str)
                        m = match(r"([\d\.]+)\s+days", eta_str)
                        if m !== nothing
                            d = parse(Float64, m.captures[1])
                            total = round(Int, d * 86400)
                            push!(eta_seconds, total)
                        end

                    # Case 3: "13:34:44" or "0:00:43"
                    else
                        m = match(r"(\d+):(\d+):(\d+)", eta_str)
                        if m !== nothing
                            h, m_, s = parse.(Int, m.captures)
                            total = h * 3600 + m_ * 60 + s
                            push!(eta_seconds, total)
                        end
                    end
                end
            end
        end
    end
    return eta_seconds
end

etas = parse_eta_log("C:/Users/andre/Desktop/Julia_code_main_directory/Example_of_log.txt")
println(etas)
iterations = 1:length(etas)
etas_hours = etas ./ 3600  # convert to hours for readability

# Create the trace
trace = scatter(
    x = iterations,
    y = etas_hours,
    mode = "lines+markers",
    name = "ETA (hours)"
)

# Layout with scrollable x-axis (interactive pan & zoom)
layout = Layout(
    title = "Estimated Time Remaining Over Iterations",
    xaxis = attr(
        title = "Iteration",
        rangeslider = attr(visible = true),  # Enables the scroll bar
        type = "linear"
    ),
    yaxis = attr(title = "ETA (hours)"),
    autosize = true
)

# Show plot
plot(trace, layout)
