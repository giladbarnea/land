#!/usr/bin/env zsh

# Sourced after tools.sh and before llm.zsh

# region ------------[ Json Yaml ]------------

# # jsonfmt <JSON_FILE / STDIN>
function jsonfmt(){
	python3.13 -OBIS -m json.tool --sort-keys "$@"
}

# # json2yaml <JSON_FILE / STDIN>
function json2yaml(){
	jsonfmt "$@" | python3.13 -OBIS -m yaml.dump
}

# # yaml2json <YAML_FILE / STDIN>
function yaml2json(){
	python3.13 -OBIS -m yaml.dump "$@" | jsonfmt
}

# # jsonclean <JSON_FILE / STDIN>
function jsonclean(){
    local -a program_lines=(
	"import sys, json"
	"def is_empty(v):"
	"    return v in ('', None) or isinstance(v, (dict, list)) and not v"
	"def prune(v):"
	"    if isinstance(v, dict):"
	"        v = {k: prune(x) for k, x in v.items()}"
	"        return {k: x for k, x in v.items() if not is_empty(x)}"
	"    if isinstance(v, list):"
	"        v = [prune(x) for x in v]"
	"        return [x for x in v if not is_empty(x)]"
	"    return v"
	"path = sys.argv[1] if len(sys.argv) > 1 else '-'"
	"with (sys.stdin if path == '-' else open(path)) as fh:"
	"    data = json.load(fh)"
	"print(json.dumps(prune(data), separators=(',', ':')))"
    )
    print -l "${program_lines[@]}" | python3.13 -OBIS - "$@" | jsonfmt
}
# endregion Json Yaml

# region ------------[ Bat ]------------

# # batw <FN_NAME> [bat options...]
function batw() {
	setopt localoptions pipefail errreturn
	local thing="$1"
	shift || return 1
	where "$thing" | bat -p -l bash "$@"
}

# # bath <EXECUTABLE>
function bath() {
	_only_argument_is_not_the_real_executable() {
		[[ $# -eq 1 ]] && [[ "$(valueof "$1")" != "$1" ]]
	}

	# shellcheck disable=SC2317
	# Push 'help' after 'npm' if there's no *help argument
	.npm_handler(){
		local -a _args=("${@}")
		[[ "${_args[(r)*help]}" || "${_args[(r)-h]}" ]] && {
			eval "${_args[@]}"
			return $?
		}
		local _npm_index="${_args[(I)npm]}"
		eval "${_args::$_npm_index} help ${_args:$_npm_index}" 
		return $?
	}

	local -a args=("$@")
	local -a special_cases=(
		npm
	)

	if is_piped; then
		bat -p -l man --color=always
		return $?
	fi

	local special_case special_case_handler
	for special_case in ${special_cases[@]}; do
		# shellcheck disable=SC2199
		if [[ "${args[(r)$special_case]}" ]]; then
			special_case_handler=".${special_case}_handler"
			log.debug "$(typeset special_case_handler args)"
			"$special_case_handler" "${args[@]}"
			return $?
		fi
	done

	if _only_argument_is_not_the_real_executable "$@"; then
		bath "$(valueof "$1")"
		return $?
	fi
	
	local double_dash_help_output
	if double_dash_help_output="$("$@" --help 2>&1)"; then
		bath <<< "$double_dash_help_output"
		return $?
	fi
	
	local single_dash_help_output
	if single_dash_help_output="$("$@" -h 2>&1)"; then
		bath <<< "$single_dash_help_output"
		return $?
	fi

	local man_output="$(man "$@" 2>&1)"
	[[ -n "$man_output" ]] && {
		bath <<< "$man_output"
		return $?
	}
	log.warn "Failed --help, help, -h and man. Trying to expand potential aliases and vars in given args."
	local arg
	local -a expanded_args=()
	for arg in ${@}; do
		if isfunction "$arg"; then
			expanded_args+=("$arg")   # Don't want function content
		else
			# shellcheck disable=SC2207
			expanded_args+=($(valueof "$arg"))  # want aliases and var values. Don't quote
		fi
	done
	if [[ "${expanded_args[*]}" == "$*" ]]; then
		log.error "Expanded args are the same as the original args (${Cc}$*${Cc0}); returning 1"
		return 1
	fi
	confirm "Expanded args: ${Cc}${expanded_args[*]}${Cc0}. Retry passing those to bath?" || return 1
	bath "${expanded_args[@]}"
	return $?
}
#endregion bat

# region ------------[ Rich ]------------

# # richsyntax <RAW / FILE_PATH / STDIN> [-x, --lexer LEXER] [-w, --width WIDTH (2/3 of COLUMNS by default)] [--no-wrap (Wraps by default)] [rich.syntax args...]
# The lexer is set by this precedence:
# - The -x LEXER option is passed.
# - A file path with an extension is passed (unless -x is passed explicitly).
# - A shebang is found in the data.
# 
# All other native rich args are passed as-is:
# - --highlight-line HIGHLIGHT_LINE_1_BASED
# - -l, --line-numbers
# - -i, --indent-guides
# - -c, --force-color
# - -b, --background-color
function richsyntax(){
	local value
	local -a rich_syntax_args
	local lexer
	local width  # Don't -i because value defaults to 0 and -z $width is always true
	local should_wrap=true
	if is_piped; then
		value="$(<&0)"
	fi
	while [[ $# -gt 0 ]]; do
		case "$1" in
		-x|--lexer) lexer="$2"; shift ;;
		-x=*|--lexer=*) lexer="${1#*=}" ;;
		-w|--width) width="$2"; shift ;;
		-w=*|--width=*) width="${1#*=}" ;;
		--no-wrap) should_wrap=false ;;
		-b|--background-color) rich_syntax_args+=(--background-color "$2"); shift ;;
		-b=*|--background-color=*) rich_syntax_args+=(--background-color "${1#*=}") ;;
		*)
			if [[ "$value" ]]; then
				rich_syntax_args+=("$1")
				shift; continue 
			fi
			if [[ -f "$1" ]]; then
				# Infer lexer from file extension.
				value="$(<"$1")"
				[[ $lexer ]] || lexer="${1%%.*}"
				shift; continue
			fi
			if [[ "$value" ]]; then
				log.warn "This clause shouldn't logically happen. Remove it."
				rich_syntax_args+=("$1")
				shift; continue
			fi
			value="$1"
			shift; continue ;;
		esac
		shift
	done

	if [[ ! "$value" ]]; then
		{ log.error "$(docstring "$0" -p): not enough args" ; return 1 ; }
	fi
	if [[ ! "$lexer" ]]; then
		lexer="$(shebang_executable "$value")" || {
			log.error "No lexer given and failed to infer from shebang"
			return 1
		}
	fi
	if [[ "$lexer" = json ]]; then
	  value="$(python3.13 -OBIS -m json.tool --sort-keys <<< "$value")"
	fi
	if [[ -z "$width" ]]; then
		width=$(( COLUMNS * 2 / 3 ))
		(( width = width > 100 ? width : 100 ))
	fi
	
	rich_syntax_args+=(
		--lexer "$lexer"
		--width "$width"
		--theme monokai
		--padding 0
	)
	[[ "$should_wrap" = true ]] && rich_syntax_args+=(--wrap)
	# [[ "$should_wrap" = false ]] && rich_syntax_args+=(--soft-wrap)
	python3.13 -m rich.syntax "${rich_syntax_args[@]}" - <<< "$value"
}

# # richjson <RAW_JSON / FILE_PATH / STDIN> [rich.syntax args...]
function richjson(){
	richsyntax -x json "$@"
}

# # richmd <MARKDOWN / FILE_PATH / STDIN> [rich.markdown args...]
# Always enabled:
# - -c, --force-color
# - -y, --hyperlinks
function richmd(){
	local markdown theme=monokai
	local -i width
	if [[ "$COLUMNS" -gt 0 ]]; then
		width=$(( COLUMNS * 2 / 3 ))
		(( width = width > 100 ? width : 100 ))
	fi
	local -a rich_markdown_args
	while [[ $# -gt 0 ]]; do
		case "$1" in
			# Options with values
			-t=*|--code-theme=*) theme="${1#*=}" ;;
			-t|--code-theme) theme="$2"; shift ;;

			-i=*|--inline-code-lexer=*) rich_markdown_args+=(-i "${1#*=}") ;;
			-i|--inline-code-lexer) rich_markdown_args+=(-i "$2"); shift ;;

			-w=*|--width=*) width="${1#*=}" ;;
			-w|--width) width="$2"; shift ;;

			# Boolean flags
			-y|--hyperlinks) : ;;  # Always enabled regardless.

			-j|--justify) rich_markdown_args+=(-j) ;;

			-p|--page) rich_markdown_args+=(-p) ;;

			-c|--force-color) : ;;  # Always enabled regardless.

			-h|--help)
				python3.13 -m rich.markdown --help
				return $? ;;
			-) : ;;  # Marks stdin - but this is handled automatically if $markdown is empty. So leave it empty.
			
			-*) log.error "Unknown option: $1" ; return 1 ;;
			
			*)
				if [[ "$markdown" ]]; then
					log.error "Only one markdown argument is allowed"
					return 1
				fi
				markdown="$1"
				;;
		esac
		shift
	done
	if [[ ! "$markdown" ]]; then
		if is_piped && is_interactive; then
			markdown="$(<&0)"
		else
			log.error "No markdown provided"
			return 1
		fi
	fi
	[[ -f "$markdown" ]] && {
		markdown="$(<"$markdown")"
	}
	# log.debug "\n#markdown=${#markdown}\n$(typeset rich_markdown_args width)"
	python3.13 -m rich.markdown \
		-t "$theme" \
		-w "$width" \
		--hyperlinks \
		"${rich_markdown_args[@]}" \
		--force-color \
		- <<< "$markdown"
}

# # mdx2md <MDX_FILE / STDIN>
# Strips MDX comments from input and outputs clean markdown
function mdx2md() {
	local mdx_content
	if [[ ! "$1" ]] && is_piped; then
		mdx_content="$(<&0)"
	else
		if [[ -f "$1" ]]; then
			mdx_content="$(<"$1")"
		else
			mdx_content="$1"
		fi
	fi
	[[ "$mdx_content" ]] || { log.error "$0: Not enough args. Usage:\n$(docstring "$0")"; return 2; }

	# Remove MDX import statements and export declarations
	echo "$mdx_content" | sed -E \
		-e '/^import.*$/d' \
		-e '/^export.*$/d' \
		-e '/{\/\*.*\*\/}/d'
}

#endregion Rich
