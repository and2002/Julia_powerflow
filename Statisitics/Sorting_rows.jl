using DataFrames, Statistics
function threshold_zero(df::DataFrame; threshold::Float64 = 1e-6)
    col_range = names(df)[2:end-1]  # exclude first and last columns

    for col in col_range
        for i in 1:nrow(df)
            val = df[i, col]
            if !ismissing(val) && abs(val) < threshold
                df[i, col] = 0.0
            end
        end
    end

    return df
end

function split_by_row_sign( # function takes data frame; formes three datasets: positive, negative, mixed
    df::DataFrame
)
    col_range = names(df)[2:end-1]  # exclude first and last columns

    df_pos = DataFrame()
    df_neg = DataFrame()
    df_mix = DataFrame()

    for row in eachrow(df)
        vals = [row[c] for c in col_range]

        has_pos = any(x -> x > 0, vals)
        has_neg = any(x -> x < 0, vals)

        if has_pos && has_neg
            push!(df_mix, row)
        elseif has_pos
            push!(df_pos, row)
        elseif has_neg || all(x -> x == 0, vals)
            push!(df_neg, row)
        end
    end

    return df_pos, df_neg, df_mix
end

function next_best_row( # function takes data frame, set of rows already selected. returns next row
    df::DataFrame, # data frame
    selected_rows::Vector{Int} # rows already selected
    )
    all_rows = collect(1:nrow(df))
    unselected_rows = setdiff(all_rows, selected_rows)

    # Get numeric columns (exclude first and last)
    numeric_cols = names(df)[2:end-1]

    # Current subset
    current_subset = df[selected_rows, numeric_cols]

    # Current max per column
    current_max = isempty(selected_rows) ? fill(-Inf, length(numeric_cols)) :
                  [maximum(skipmissing(current_subset[!, col])) for col in numeric_cols]

    best_row = -1
    min_increase = Inf

    for r in unselected_rows
        candidate_row = df[r, numeric_cols]
        candidate_max = [max(current_max[i], candidate_row[i]) for i in 1:length(numeric_cols)]
        increase = sum(candidate_max) - sum(current_max)

        if increase < min_increase
            min_increase = increase
            best_row = r
        end
    end

    return best_row
end

function greedy_sort_df_by_max_increase( # sorts fata frame from min to max 
    df::DataFrame # data frame 
)
    selected_rows = Int[]
    all_rows = collect(1:nrow(df))

    # Choose initial row — e.g., the one with the smallest sum of values in numeric columns
    numeric_cols = names(df)[2:end-1]
    row_sums = [sum(skipmissing(df[i, numeric_cols])) for i in all_rows]
    first_row = argmin(row_sums)
    push!(selected_rows, first_row)

    # Iteratively select the next best row
    while length(selected_rows) < nrow(df)
        next_row = next_best_row(df, selected_rows)
        push!(selected_rows, next_row)
    end

    # Return a new DataFrame sorted according to this greedy strategy
    return df[selected_rows, :]
end

df = DataFrame(ID = 1:5,
               A = [0.0000001, -2.0, 3.0, -1e-7, 1.5],
               B = [1.0, -1.0, 0.0, 2.0, -3.0],
               Label = ["a", "b", "c", "d", "e"])
df_filtered = threshold_zero(df, threshold = 1e-3)
df_pos, df_neg, df_mix = split_by_row_sign(df_filtered)

println("Positive:")
display(df_pos)

println("Negative:")
display(df_neg)

println("Mixed:")
display(df_mix)

df = DataFrame(ID=1:5, A=[2,5,1,6,3], B=[3,4,2,7,1], Label=["a","b","c","d","e"])
selected = [2, 4]

#row = next_best_row(df, selected)
#println("Next best row index: ", row)
greedy_sort_df_by_max_increase(df)
