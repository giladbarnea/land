#!/usr/bin/env zsh
# sourced after util.sh

# # alias_value <ALIAS>
# Recursively resolves an alias to its final value.
function alias_value() {
  local alias_val="${aliases[$1]}"
  [[ -z "$alias_val" ]] && return 1
  until [[ ! "${aliases[$alias_val]}" ]]; do
    alias_val="${aliases[$alias_val]}"
  done
  print -- "${alias_val}"
  return 0
}

typeset -a RG_QUICK_SCAN_ARGS=(
  --color=never
  --max-count=1  # Limit the number of matching lines per file searched to 1
  --max-filesize 1M
  --no-search-zip
  --no-text
)


.search(){
  local -a positional_args
  local -a extra_rg_opts
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -*) extra_rg_opts+=("$1") ;;
      *) positional_args+=("$1") ;;
    esac
    shift
  done
  case "${#positional_args}" in
    1)
      search_query="${positional_args[1]}"
      # We don't just return ${functions_source[$search_query]} because we want to support rg extra opts.
      # shellcheck disable=SC2299
      search_location="${${functions_source[$search_query]}:-${SCRIPTS}}" 
      ;;
    2)
      search_query="${positional_args[1]}"
      search_location="${positional_args[2]}" ;;
    *) log.error "$0: Too many args or not enough args. Usage:\n$(docstring -p "$0")"; return 2; ;;
  esac
  local -a rg_args=( "${RG_QUICK_SCAN_ARGS[@]}" "${extra_rg_opts[@]}" )
  # We allow optional quotes around the search query.
  if isalias "$search_query"; then
    search_query="alias ('|\")?${search_query}('|\")?="
  elif isvariable "${search_query}"; then
    search_query="('\")?${search_query}('\")?="
  # TODO: handle functions
  elif isbuiltin "$search_query"; then
    log.error "Cannot get file of builtin: $search_query"
    return 1
  else
    # If it's "just a string", we can't assume the first match is the right one.
    rg_args=("${(@)rg_args:#'--max-count=1'}")

    is_regex_pattern "$search_query" || rg_args+=(-F)
  fi
  # If using regex mode (not -F), anchor to non-comment lines to reduce false positives
  if [[ -z "${rg_args[(r)-F]}" ]]; then
    search_query="^[[:space:]]*[^#].*${search_query}"
  fi
  rg "${rg_args[@]}" "$search_query" "$search_location"
}


# # fileof <FUNCTION/ALIAS/STRING> [DIR_OR_FILE=$SCRIPTS] [RG_ARGS...]
# Returns the file name containing STRING, if STRING is contained
# in DIR_OR_FILE (defaults to $SCRIPTS).
# ## Examples
# ```bash
# $ fileof "def pandas" $MAN
# $HOME/dev/manuals/manuals/manuals.py
# $ fileof batwhere
# $SCRIPTS/tools.sh
# ```
function fileof() {
  .search --files-with-matches "$@"
}

# # linenumof <FUNCTION/ALIAS/STRING> [DIR_OR_FILE=$SCRIPTS] [RG_ARGS...]
# Returns the line name of STRING, if STRING exists in DIR_OR_FILE (defaults to $SCRIPTS).
# ## Examples
# ```bash
# $ linenumof "def pandas" $MANPROJ
# 4366
# $ linenumof log.error
# 149
# ```
function linenumof() {
  .search --line-number --no-filename "$@" #| awk -F: '{print $1}'

}

# # linecount <EXT> [AND line...] [! OR line...] [ROOT]
# Recursively counts non-empty lines of EXT files in the current directory, or in the ROOT directory if specified.
# Skips lines that start with # or //.
# Example:
# `linecount py 'line.islower()' ! 'line.startswith(";")' ~/.config`
function linecount(){
	log.title "$0 $*"
  local ext="$1"
  shift || return 1
  ext="${ext#.}"
  local root
  local skip_if_any_condition=(
  	'not line'
  	'line.startswith("#")'
  	'line.startswith("//")'
  )
  local only_if_all_conditions=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      !) skip_if_any_condition+=("$2"); shift 2 ;;
      *) [[ ! "$root" && -d "$1" ]] && root="$1" || only_if_all_conditions+=("$1"); shift ;;
    esac
  done
  [[ ! "$root" ]] && root="$PWD"
  local skip_if_any="${(j. or .)skip_if_any_condition}"
	local only_if_all="${(j. and .)only_if_all_conditions}"
	log.debug "skip_if_any: ${Cc}${skip_if_any}${Cc0} | only_if_all: ${Cc}${only_if_all}"
  log.prompt "Counting lines of $ext files in $root..."
  local count=0
  count=$(python3 <<-EOF
	from glob import glob
	import sys
	loc = 0
	for path in glob('$root/**/*.$ext', recursive=True):
	    try:
	        with open(path) as f:
	            lines = f.readlines()
	    except Exception as e:
	        print(f"\x1b[33m{e.__class__.__qualname__}: {e} | {path}\x1b[0m", file=sys.stderr)
	        continue
	    for line in map(strip, lines):
	        if $skip_if_any:
	            continue
	        if True and $only_if_all:
	            loc += 1
	print(loc)
	EOF
	)
	log.prompt "Counted ${count} lines"
}

# # docstring <FN_NAME> [FILEPATH] [-p, --pretty]
# Faster if FILEPATH is provided (doesn't need to rg).
function docstring(){
	local fn filepath pretty=false
	while [[ $# -gt 0 ]]; do
	  case "$1" in
	    -p|--pretty) pretty=true;;
	    *) [[ "$fn" && "$filepath" ]] && { log.error "Too many args"; return 1; };
	    	 [[ "$fn" ]] && filepath="$1" || fn="$1";;
	  esac
	  shift
	done
	local doc_string
	[[ "$filepath" ]] || {
	  filepath="$(fileof "$fn")" || {
	    log.error "Failed finding file of ${fn}. Consider specifying the file path explicitly."
      return 1
    }
  }
  if ! doc_string="$(awk -v fn="${fn}" '
  BEGIN { RS = ""; FS = "\n"; found = 0 }
  {
    for (i = 1; i <= NF; i++) {
      if ($i ~ "^[[:space:]]*(function[[:space:]]+" fn ")|("fn"[[:space:]]*\\(\\))") {
        for (j = i-1; j > 0; j--) {
          if ($j ~ "^[[:space:]]*# # " fn) {
            for (k = j; k < i; k++) {
              sub(/^[[:space:]]*# ?/, "", $k)
              print $k
            }
            found = 1
            exit 0
          }
        }
        break
      }
    }
  }
  END { exit found ? 0 : 1 }
  ' "$filepath")"; then
    log.error "Failed extracting docstring of $fn from $filepath"
    return 1
  fi
  if [[ $pretty = true ]]; then
    richmd "$doc_string"
  else
    echo "$doc_string"
  fi
  return 0
}

# # docstring.getopts <FN_NAME/DOCSTRING/STDIN> [FILEPATH]
function docstring.getopts(){
  # r'(?<=\[)(-[a-z]+)?[, ]*(--[a-z\-_]+)?( [A-Z_]+)?(?=])'
  local string
  if [[ ! "$1" ]] && is_piped; then
    string="$(<&0)"
  else
    string="$1"
    shift || { log.error "$0: Not enough args (got ${#$}). Usage:\n$(docstring "$0")"; return 2; }
  fi
  local doc_string
  if isfunction "$string"; then
    doc_string="$(docstring "$string" "$@")"
  else
    doc_string="$string"
  fi

  # [^[:alnum:]] makes tests fail :shrug:
  command grep -Po --color=never '([[:alnum:]]{0}-[a-zA-Z0-9_]{1}|---?[a-zA-Z0-9-_]{2,})' <<< "$doc_string" | sort -u
}

# # # build_declaration_regex <FUNCTION NAME OR ALIAS>
# # Checks whether passed name is a function or an alias, and
# # returns a literal regex to match its declaration.
# function build_declaration_regex(){
# 	# dollar sign at the end rules out 1-line functions, usually shims
#   local fn_regex="^[[:space:]]*(function +)?${1}( *\(\))? *\{ *$"
#   local query
# 	if isfunction "$1"; then
# 		query="${fn_regex}"
# 	elif isalias "$1"; then
# 		query="alias $1="
# 	else
# 		log.warn "Not a function nor alias: $1"
# 		query="${fn_regex}|alias $1="
# 	fi
# 	echo "$query"
# }


# # isfunction <FUNCTION_NAME>
function isfunction() {
  [[ "${functions[$1]}" ]]
}

# # isalias <ALIAS_NAME>
function isalias(){
  [[ "${aliases[$1]}" ]]
}

function isvariable(){
  [[ "${parameters[$1]}" ]]
}

function isbuiltin(){
  [[ "${builtins[$1]}" ]]
}

# # valueof <FUNCTION/ALIAS/STRING>
# Returns the value of variable, function, or alias.
# If it's a function, returns its content.
# If it's a recursive alias, recursively gets the value of the alias.
# ```bash
# myvar=42; valueof myvar                 # 42
# alias myalias=echo; valueof myalias     # echo
# myfunc(){ echo 42; }; valueof myfunc    # myfunc(){ echo 42; };
# ```
# shellcheck disable=SC2207  # No quotes on purpose, to split on spaces
function valueof() {
  if isfunction "$1"; then
    print -r -- "${functions[$1]}"
    return $?
  elif isalias "$1"; then
    setopt localoptions errreturn
    print -r -- "$(alias_value "$1")"
    return $?
  elif isbuiltin "$1"; then
    print -r -- "builtin $1"
    return 0
  elif isvariable "$1"; then
    # shellcheck disable=SC2300  # Parameter expansion is safe here.
    print -r -- "${$(typeset -p "$1")#*$1=}"
    return $?
  fi
  print -r -- "$1"
  return 1
}


function fnnames(){
  print -- -l -m "[^_→/\.\-\+][[:alnum:]]*~*power*~*zvm*" ${(k)functions}
}

function aliasnames(){
  print -- -l -m "[^_→/\.\-\+][[:alnum:]]*" ${(k)aliases}
}

function varnames(){
  print -- -l -m "[^_→/\.\-\+][[:alnum:]]*~*POWER*~*P9*" ${(k)parameters}
}

function commandnames(){
  print -- -l -m "[^_→/\.\-\+][[:alnum:]]*" ${(k)commands}
}


# # aliasestable
# Prints the alias names and values in two padded columns.
function aliasestable(){
  .table aliases
}

# # variablestable
# Prints the variable names and values in two padded columns.
function variablestable(){
  .table parameters
}

# # commandstable
# Prints the command names and values in two padded columns.
function commandstable(){
  .table commands
}

# # functions_in_file <FILE> [--no-nested] [--only-function-keyword]
function functions_in_file(){
	local filename="$1"
	shift 1 || { log.error "$0: Not enough args (expected at least 1, got ${#$}). Usage:\n$(docstring "$0")"; return 2; }
  local no_nested only_function_keyword
  zparseopts -D -E - \
    -no-nested=no_nested \
    -only-function-keyword=only_function_keyword

	local function_name_re="[\w\-\.]+(?=\s*\(\)\s*\{)"
	local function_prefix_re
	if [[ $no_nested ]]; then
	  if [[ $only_function_keyword ]]; then
      function_prefix_re="(?<=^function )"
    else
      function_prefix_re="((?<=^function )|^)"
    fi
  else
    if [[ $only_function_keyword ]]; then
      function_prefix_re="(?<=\bfunction )"
    else
      function_prefix_re="(?<=\bfunction )?"
    fi
  fi
	command grep -oP --color=never "${function_prefix_re}${function_name_re}" "$filename"
}

# # aliases_in_file <file_path>
# Does this and that
# ## Examples:
# ```bash
# aliases_in_file
# ```
function aliases_in_file(){
  local file_path
  if [[ -z "$1" ]]; then
    log.fatal "$0 requires 1 arg"
    docstring -p "$0"
    return 1
  fi
  file_path="$1"
  awk '/^[[:space:]]*alias[[:space:]]+/ {
    # Remove leading spaces:
    sub(/^[[:space:]]*alias /, "");
    # Remove trailing spaces:
    sub(/[[:space:]]*$/, "");
    # Remove everything after (and including) the equal sign:
    sub(/=.*/, ""); 
    print
  }' "$file_path"
}

# # shebang_executable <FILE>
function shebang_executable(){
  local target="$1"
  shift 1 || { log.error "$0: No file specified"; return 1; }
  local shebang_program exitcode
  # If a shebang is present, extract the program name
  # Remove everything up to and including the last space, '!' or '/'.
  # This accounts for the '#!/bin/bash', '#!/usr/bin/env bash' etc.
  # shellcheck disable=SC2300  # Parameter expansion can't be applied to command substitution.
  shebang_program="${$(command grep -m 1 -Po '^#\![^ ]+.+$' "$target")##*(\!| |/)}"
	if [[ -n "$shebang_program" ]]; then
		echo -n "$shebang_program"
		return 0
	fi
	return 1

  # local first_non_empty_line
  # # Filters out empty/whitespace-only lines from the first 5 lines and returns the first one
  # if first_non_empty_line="$(head -n 5 "$target" | command grep -vE '^\s*$' | head -n 1)"; then
  #
  #   local shebang_program
  #   # Matches if shebang is #!sh, #!/bin/bash, #!/usr/bin/zsh and returns sh, bash, zsh etc
  #   if shebang_program="$(command grep -Po '((?<=\#\!/usr/bin/)|(?<=\#\!/bin/)|(?<=\#\!))(ba|z)?sh\b' <<< "$first_non_empty_line")"
  #   then
  #     if [[ -n "$shebang_program" ]]; then
  #       echo -n "$shebang_program"
  #       return 0
  #     fi
  #   fi
  # fi
  # return 1
}


# # .table <ASSOCIATIVE_ARRAY_NAME>
# Prints the item names and values in two padded columns.
function .table(){
  local assoc_array_name="$1"
  local -A items=("${(@kvP)assoc_array_name}")
  local -i longest_item_name
  local item

  # Find the longest item value
  for item in ${(k)items}; do
    if [[ $((${#items[$item]} + ${#item} + 1)) -gt longest_item_name ]]; then
      longest_item_name=$((${#items[$item]} + ${#item} + 1))
    fi
  done

  # Print the item names and values in two columns
  for item in ${(kio)items}; do
    printf "%s%$((longest_item_name-${#item}))s%s\n" "$item" "${items[$item]}"
  done
}
