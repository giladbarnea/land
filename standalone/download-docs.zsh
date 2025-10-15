#!/usr/bin/env zsh

# # html_to_markdown DIR [OUTPUT_DIR=DIR/md]
function html_to_markdown(){
  setopt localoptions errreturn
  local dir="$1"
  local output_dir="${2:-$dir/md}"
  mkdir -p "$output_dir"
  local f
  for f in "$dir"/*.html; do good_html2text "$f" > "${dir}/md/${f%.html}.md"; done
}

# # good_html2text [OPTIONS]
# Calls html2text alias if it exists, otherwise calls html2text with good options
function good_html2text(){
  [[ "${aliases[html2text]}" ]] && {
    html2text "$@"
    return $?
  }
  html2text --no-wrap-links --ignore-images --asterisk-emphasis --unicode-snob --single-line-break --dash-unordered-list --mark-code "$@"
}

# # is_real_content FILE
function is_real_content(){
  local file="$1"
  local response
  # shellcheck disable=SC2034
  response="$(head -1000 "$file" | sgpt "Reading the file '$file' above, does it look like it does not contain real content, but instead is an index / table of contents / references or anything else that does not have real content but simply references to real content? answer only with 'yes' or 'no'")"
  if [[ "${(L)response}" == *"no"* ]]
}

# # get_nontext_files DIR [FD_ARGS...]
function get_nontext_files(){
  local dir="$1"
  shift
  local -a fd_args=("$@")
  fd -t f "$dir" --exclude='*.md' --exclude='*.text' --exclude='*.html' "${fd_args[@]}" \
    | filter '[[ {} == *.* ]]'  # Only files with extension
}

# # flatten_files DIR_TO_FLATTEN [MOVE_THEM_HERE=DIR_TO_FLATTEN]
# Recursively brings all files in a directory to the top level, whilst prepending dot-separated directory parts to the filename, e.g.:
#   path/to/file.txt -> path.to.file.txt
function flatten_files(){
  local dir_to_flatten="$1"
  local move_them_here="${2:-$dir_to_flatten}"
  local f
  local new_name
  for f in "$dir_to_flatten"/*; do
    if [[ -d "$f" ]]; then
      flatten_files "$f" "$move_them_here"
    else
      new_name="${f/$dir_to_flatten/}"
      new_name="${new_name#.}"
      new_name="${new_name#/}"
      new_name="${new_name%/}"
      new_name="${new_name//\//.}"
      mv "$f" "$move_them_here/$new_name"
    fi
  done
}


# # get_file_title FILE --filename-ok=BOOL
# Get the title of a file based on precedence rules:
# 1. First markdown heading if present
# 2. Filename if no heading
# 3. Use GPT to determine title if neither above works
function get_file_title() {
    local file
    local filename_ok
    while (( $# )); do
      case "$1" in
        --filename-ok=*) filename_ok=${1#*=} ;;
        --filename-ok) filename_ok=${2}; shift ;;
        *) file=$1 ;;
      esac
      shift
    done

    local first_10_lines="$(head -n 10 "$file")"
    # Try to find h1 markdown heading (# ) in first 10 lines
    local md_heading="$(echo "$first_10_lines" | grep -m 1 '^#\s.*' | sed 's/^#\s*//')"
    if [[ -n "$md_heading" ]]; then
        echo "$md_heading"
        return
    fi

    # Try to find h2 markdown heading (## ) in first 10 lines
    local md_heading="$(echo "$first_10_lines" | grep -m 1 '^##\s.*' | sed 's/^##\s*//')"
    if [[ -n "$md_heading" ]]; then
        echo "$md_heading"
        return
    fi

    # Try to find underlined headers in first 10 lines
    # We use a temp file to handle multiline matching easily
    local temp_file="$(mktemp)"
    echo "$first_10_lines" > "$temp_file"

    # Look for text followed by --- or === (minimum 3 chars)
    local md_heading=$(awk '
        NR > 1 && /^[-]{3,}$/ { print prev_line; exit }
        NR > 1 && /^[=]{3,}$/ { print prev_line; exit }
        { prev_line = $0 }
    ' "$temp_file")
    rm "$temp_file"

    if [[ -n "$md_heading" ]]; then
        echo "$md_heading"
        return
    fi

    if [[ "$filename_ok" == true ]]; then
        local filename="$(basename "$file")"
        local name_without_ext="${filename%.*}"
        if [[ -n "$name_without_ext" ]]; then
            echo "$name_without_ext"
            return
        fi
    fi

    sgpt "What is a short and fitting markdown title to the file?" < "$file"
}


function get_token_count() {
    ttok < "$1"
}

function get_char_count() {
    wc -c < "$1"
}

# # strip_numbers_from_filename FILENAME
# Strips numbers from filename and returns newline-separated characters
function strip_numbers_from_filename() {
    local filename="$1"
    # Remove extension and numbers, split into chars
    echo ${${filename%.*}//[0-9]/} | fold -w1
}

# # are_filenames_very_similar FILE1 FILE2
# Compare two filenames and determine if they are very similar
# Output: 0 if very similar, 1 if not
function are_filenames_very_similar() {
    local file1="$1"
    local file2="$2"

    # Get char arrays
    local chars1=($(strip_numbers_from_filename "$file1"))
    local chars2=($(strip_numbers_from_filename "$file2"))

    # Get lengths
    local len1="${#chars1}"
    local len2="${#chars2}"

    # If lengths differ too much, not similar
    if (( len1 == 0 || len2 == 0 || ${len1:-0} * 2 < ${len2:-0} || ${len2:-0} * 2 < ${len1:-0} )); then
        return 1
    fi

    # Compare characters
    local min_len=$(( len1 < len2 ? len1 : len2 ))
    local matching=0
    local i
    for (( i = 1; i <= min_len; i++ )); do
        if [[ "${chars1[i]}" == "${chars2[i]}" ]]; then
            (( matching++ ))
        fi
    done

    # Consider very similar if at least 75% of characters match
    (( matching * 100 / min_len >= 75 ))
}

# # is_filename_meaningless FILENAME ALL_FILES_IN_DIR...
# Check if a filename is meaningless in the context of its directory
# Output: 0 if meaningless, 1 if meaningful
function is_filename_meaningless() {
    local target_file=$1
    shift
    local all_files_in_dir=("$@")
    local file

    # Count similar files
    local similar_count=0
    for file in "${all_files_in_dir[@]}"; do
        if [[ "$file" != "$target_file" ]]; then
            if are_filenames_very_similar "$file" "$target_file"; then
                (( similar_count++ ))
            fi
        fi
    done

    # Get minimum threshold
    local file_count=${#all_files_in_dir}
    local min_threshold=$(( file_count < 2 ? file_count : 2 ))

    # Return 0 (true) if we have enough similar files
    (( similar_count >= min_threshold ))
}

# merge_files_with_titles OUTPUT_FILE FILE1 FILE2 ...
function merge_files_with_titles() {
    local output_file=$1
    shift
    local files=("$@")
    local file title base_name

    # Clear output file if it exists
    : > "$output_file"

    local basenames=()
    for file in "${files[@]}"; do
        basenames+=("$(basename "$file")")
    done

    for file in "${files[@]}"; do
        base_name="$(basename "$file")"
        if is_filename_meaningless "$base_name" "${basenames[@]}"; then
          title="$(cached get_file_title "$file" --filename-ok=false)"
        else
          title="$(cached get_file_title "$file" --filename-ok=true)"
        fi

        {
          printf "%s\n\n\n" "# ${title}"
          cat "$file"
          echo -e "\n\n"
        } >> "$output_file"
    done

}

# # merge_files DIRECTORY MINIMUM_TOKEN_COUNT
function merge_files() {
    local dir=$1
    local min_tokens=$2

    # Validate input
    if [[ $# -ne 2 ]]; then
        echo "Usage: merge_files DIRECTORY MINIMUM_TOKEN_COUNT"
        return 1
    fi

    if [[ ! -d "$dir" ]]; then
        echo "Error: Directory '$dir' does not exist"
        return 1
    fi

    # Create associative array for character counts
    typeset -A char_counts
    local files=("${dir}"/*)
    local file
    for file in "${files[@]}"; do
        char_counts[$file]="$(get_char_count "$file")"
    done

    # Calculate tokens per character using first file
    local first_file="${files[1]}"
    local first_tokens="$(get_token_count "$first_file")"
    local first_chars="${char_counts[$first_file]}"
    # Use floating point arithmetic for better precision
    local tokens_per_char=$(( first_tokens / first_chars ))

    # Process files in batches
    local output_counter=1
    # shellcheck disable=SC2206
    local remaining_files=(${files[@]})

    while (( ${#remaining_files} > 0 )); do
        # Estimate how many chars we need for min_tokens
        local target_chars=$(( min_tokens / tokens_per_char ))

        # Count files needed to reach target_chars
        local total_chars=0
        local files_needed=0
        for file in "${remaining_files[@]}"; do
            (( total_chars += char_counts[$file] ))
            (( files_needed++ ))
            if (( total_chars >= target_chars )); then
                break
            fi
        done

        # Prepare batch of files
        local current_batch=("${(@)remaining_files[1,$files_needed]}")

        # Create temporary merged file
        local temp_output="merged_${output_counter}.md"
        merge_files_with_titles "$temp_output" "${current_batch[@]}"

        # Verify token count
        local actual_tokens="$(get_token_count "$temp_output")"

        if (( actual_tokens < min_tokens )) && (( ${#remaining_files} > files_needed )); then
            # Add one more file if we're under target and have files available
            (( files_needed++ ))
            rm "$temp_output"
            continue
        elif (( actual_tokens >= min_tokens )) && (( files_needed > 1 )); then
            # Try removing files one by one while still meeting minimum tokens
            while (( files_needed > 1 )); do
                local temp_trial="temp_trial.md"
                merge_files_with_titles "$temp_trial" "${(@)current_batch[1,$((files_needed-1))]}"
                local trial_tokens="$(get_token_count "$temp_trial")"
                rm "$temp_trial"

                if (( trial_tokens >= min_tokens )); then
                    (( files_needed-- ))
                    current_batch=("${(@)current_batch[1,$files_needed]}")
                else
                    break
                fi
            done
            rm "$temp_output"
            continue
        fi

        # Accept current batch
        (( output_counter++ ))
        remaining_files=(${(@)remaining_files[$((files_needed + 1)),-1]})
    done

    echo "Merged files created successfully"
}

# Check if sourced (not executed)
if [[ $ZSH_EVAL_CONTEXT =~ :file$ ]]; then
    cat <<EOF
merge_files
├── merge_files_with_titles
│   ├── get_file_title
│   │   └── sgpt (external)
│   └── is_filename_meaningless
│       └── are_filenames_very_similar
│           └── strip_numbers_from_filename
├── get_token_count
└── get_char_count

html_to_markdown
└── good_html2text

flatten_files
└── flatten_files (recursive)

is_real_content
└── sgpt (external)

get_nontext_files
EOF
fi
