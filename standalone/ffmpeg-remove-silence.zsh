#!/usr/bin/env zsh

# Exit on error, treat unset variables as an error (optional, be cautious), and error on pipe failures.
set -e
# set -u # Uncomment if you are sure all variables will be set before use.
set -o pipefail

# Input and output filenames
local input_file="$1"
local output_file="$2"
local threshold="${3}"
local duration="${4:-10}"
shift 3 # only 3 are required
# silencedetect output provided by the user
local ffmpeg_output
ffmpeg_output="$(ffmpeg -i "$input_file" -af "silencedetect=noise=-${threshold}dB:d=${duration}" -f null - 2>&1 | grep 'silence_start\|silence_end' | tee /dev/stderr)"

local -a starts ends
integer s_idx=1 e_idx=1 # Zsh arrays are 1-indexed

# Parse silence start and end times
while IFS= read -r line; do
    if [[ $line == *silence_start:* ]]; then
        starts[s_idx++]=${line##*silence_start: }
    elif [[ $line == *silence_end:* ]]; then
        local end_val_part=${line##*silence_end: }
        ends[e_idx++]=${end_val_part%% |*}
    fi
done <<< "$ffmpeg_output"

local -a select_parts
local select_filter_content

if (( ${#starts[@]} > 0 )); then
    local current_sound_start=0.0
    for i in {1..${#starts[@]}}; do
        # Add sound segment before current silence period
        # Using bc for floating point comparison
        if (( $(echo "${starts[i]} > ${current_sound_start}" | bc -l) )); then
            select_parts+=("between(t,${current_sound_start},${starts[i]})")
        fi
        current_sound_start=${ends[i]} # Next sound segment starts after this silence ends
    done
    # Add sound segment after the last silence period
    select_parts+=("gte(t,${current_sound_start})")

    if (( ${#select_parts[@]} > 0 )); then
        select_filter_content=$(IFS=+; echo "${select_parts[*]}")
    else
        # This case implies the entire video was marked as silence by the logic
        # (e.g. one silence period covering S=0 to E=duration)
        # The last "gte(t,current_sound_start)" would handle this.
        # If select_parts is still empty, it's an unexpected state,
        # but we can default to selecting nothing or everything.
        # Given the logic, if starts is not empty, select_parts should not be empty.
        # For safety, if it somehow ends up empty, make it select nothing to be safe.
        # However, `gte(t, last_silence_end)` should correctly produce an empty stream if all is silent.
        # If starts is not empty, select_parts will contain at least one "gte" part.
        # This else branch should ideally not be reached if starts is non-empty.
        # If it were, it means no sound segments were found.
        # An empty filter string is invalid.
        # If the whole video is silence, `select_filter_content` will be like `gte(t,TOTAL_DURATION)`.
        print -u2 "Warning: Could not determine sound segments correctly, filter might be ineffective."
        select_filter_content="1" # Fallback to select all to avoid error, though output might be wrong.
                                  # A better fallback might be to select nothing: "0" or "lt(t,0)"
    fi
else
    # No silence detected in the input, or input was empty. Select all frames/samples.
    print "No silence periods found in the input. The output file will be a copy of the input."
    select_filter_content="1"
fi

# Construct ffmpeg filter strings
local vf_filter="select='${select_filter_content}',setpts=N/FRAME_RATE/TB"
local af_filter="aselect='${select_filter_content}',asetpts=N/SR/TB"

# Prepare the ffmpeg command
# Using an array for the command is robust, especially with complex arguments.
local -a cmd
cmd=(ffmpeg -y -i "$input_file") # -y to overwrite output without asking

# If select_filter_content is "1", we can optimize by just copying.
# However, for consistency and to handle cases where "1" might be part of a complex filter,
# we apply the filters. If it's just "1", ffmpeg handles it efficiently.
cmd+=(-vf "$vf_filter" -af "$af_filter")

cmd+=("$output_file")

# Print the command to be executed (for verification)
print "Executing ffmpeg command:"
print -r -- ${(qqq)cmd} # qqq for better quoting if there are tricky characters
echo # Newline for readability

# Execute the command
"${cmd[@]}"

print "Processing complete. Output saved to: $output_file"

