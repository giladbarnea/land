#!/usr/bin/env zsh
# Sourced fourth, after term.zsh
# Env vars: ZPP_LOG_LEVEL, LOG_SHOW_TRACE, LOG_SHOW_LEVEL, LOG_APPEND_NEWLINE, LOG_TRACE_OFFSET


# -------------[ Log ]-------------


declare -A -x LEVELS_COLORS=(
	[debug]="${Cd}"
	[info]="${C0}"
	[warn]="${Cylw}"
	[error]="${Cred}"
	[fatal]="${CbrRed}"
	[success]="${Cgrn}"
	# Could be cool to use Kitty's text sizing protocol: https://sw.kovidgoyal.net/kitty/text-sizing-protocol/
	[notice]="${h2}"  # printf "\e]66;s=2;Double sized text\a\n\n"
	[title]="${h1}"   # printf "\e]66;s=3;Triple sized text\a\n\n\n"
	# [prompt]="${CbrCyn}${Cb}"
	[prompt]="${h2}"
)

# # _get_caller [OFFSET=3]
function _get_caller(){
	# There's also these: funcfiletrace, functsourcetrace
	local offset
	# Assuming myfn (3) called `log.debug` (2) which called `log` (1) which called `_get_caller` (0)
	if [[ -n "$1" ]]; then
		offset="$1"
	elif [[ -n "$LOG_TRACE_OFFSET" ]]; then
		offset="$LOG_TRACE_OFFSET"
	else
		offset=3
	fi
	# shellcheck disable=SC2154
	local fn_and_linenum="${functrace[$offset]}"
	# local caller_fn="$(echo "$fn_and_linenum" | cut -d : -f 1)"
	# local linenum="$(echo "$fn_and_linenum" | cut -d : -f 2)"
	# echo -n "${caller_fn}():${linenum}"
	printf "%s" "${fn_and_linenum}"
	[[ -n "${fn_and_linenum}" ]]
}

# # log <ARG...> [-x / --no-trace] [-L / --no-level] [-n / --no-newline] [--offset <OFFSET>]
# ### log <MESSAGE> [-x / --no-trace] [-L / --no-level] [-n / --no-newline] [--offset <OFFSET>]
# ### log <LEVEL> <MESSAGE> [-x / --no-trace] [-L / --no-level] [-n / --no-newline] [--offset <OFFSET>]
# Respects `LOG_SHOW_TRACE`, `LOG_SHOW_LEVEL`, and `LOG_APPEND_NEWLINE`, `LOG_TRACE_OFFSET`,
# but passed args override env vars.
function log(){
	local show_trace=true
	local show_level=true
	local append_newline=true

	[[ "$LOG_SHOW_TRACE" == 0 || "$LOG_SHOW_TRACE" == false ]] && show_trace=false
	
	[[ "$LOG_SHOW_LEVEL" == 0 || "$LOG_SHOW_LEVEL" == false ]] && show_level=false

	[[ "$LOG_APPEND_NEWLINE" == 0 || "$LOG_APPEND_NEWLINE" == false ]] && append_newline=false

	local caller message string level offset

	local -a positional=()
	while [[ $# -gt 0 ]]; do
		case "$1" in
			-x|--no-trace) show_trace=false ;;
			-L|--no-level) show_level=false ;;
			-n|--no-newline) append_newline=false ;;
			--offset=*) offset="${1#*=}" ;;
			--offset) offset="$2" ; shift ;;
			*) positional+=("$1") ;;
		esac
		shift
	done
	set -- "${positional[@]}"

	# string is [caller][level]
	if [[ $show_trace = true ]] && caller="$(_get_caller "$offset")"; then
		string+="[${caller}]"
	fi

	level="${1}"
	
	local level_color="${LEVELS_COLORS[$level]}"
	if [[ -n "$level_color" ]]; then
		if [[ $show_level = true ]]; then
			string+="[${(U)level}]"
		fi
		message+="${level_color}"
		shift  # Shift here so that the level isn't included in the message
	fi

	message+="$*"
	if [[ -n "$level_color" ]]; then
		# Append the level's color open tag to any "code reset" codes to allow e.g. $Cc ... $Cc0 in middle of message:
		message="${message//"${C0}"/"${C0}${level_color}"}"
		message="${message//"${Cc0}"/"${Cc0}${level_color}"}"
		message="${message//"${Cfg0}"/"${Cfg0}${level_color}"}"
	fi
	
	# Dim caller and level string if it exists.
	if [[ -n "$string" ]]; then
		string="${CbrBlk}${string}${C0} ${message}"
	else
		string="${message}"
	fi

	local template="%b${C0}"
	if [[ $append_newline = true ]]; then template+="\n"; else template+=" "; fi
	# shellcheck disable=SC2059
	printf "$template" "${string}" 1>&2
	return $?
}

if [[ "${ZPP_LOG_LEVEL:-4}" -ge 4 ]]; then
	function log.debug() { log debug "$@" ; }
else
	function log.debug() { : ; }
fi

function log.megasuccess() {
	log "${Cb}${LEVELS_COLORS[success]}$(box "${1}")${Cb0}" "${@:2}"
}
function log.megatitle() {
	log "${Cb}${LEVELS_COLORS[title]}$(box "$1")${Cb0}" "${@:2}"
}
function log.megawarn() {
	log "${Cb}${LEVELS_COLORS[warn]}$(box "$1")${Cb0}" "${@:2}"
}
function log.megaerror() {
	log "${Cb}${LEVELS_COLORS[error]}$(box "$1")${Cb0}" "${@:2}"
}

function log.megafatal() {
	log "${Cb}${LEVELS_COLORS[fatal]}$(box "$1")${Cb0}" "${@:2}"
}

function log.info() {
	log info "$@"
}

function log.notice() {
	# local notice_symbol="\033[38;5;45m›\033[0m"
	local notice_symbol="\033[38;5;45m✦\033[0m"
	log notice " ${notice_symbol} ${LEVELS_COLORS[notice]}$1" --no-trace --no-level "${@:2}"
}

function log.success() {
	log success "$@"
}
function log.title() {
	log title " $1 " --no-level "${@:2}"
}
function log.warn() {
	log warn "$@"
}
function log.error() {
	log error "$@"
}
function log.fatal() {
	log fatal "$@"
}
function log.prompt() {
	log prompt "$@" --no-trace --no-level
}


# # input <PROMPT> [-s SYMBOL] [--choices=CHOICES] [--no-validate]
# `CHOICES` can be in one of the following forms:
# - y,n (comma-separated)
# - "[y]es [n]o" (actual choices are in brackets)
# - "(foo bar)" (choose index of regular array)
# - "( [j]='jupyter ipython rich' [i]='ipython rich' )" (choose key of associative array)
# - "1..6" (choose a number in range)
# ## Examples:
# ```bash
# input "Favorite icecream:"
# input "Overwrite?" --choices='y,n'
# input "File exists;" --choices='[o]verwrite [q]uit [s]kip'
# input "Which version?" --choices "( current ${node_versions[*]} )"
# input "Which lib to install?" --choices "( [j]='jupyter ipython rich' [i]='ipython rich' )"
# input "Best number:" --choices "1..42"
# input "Choose:" --choices=${(j.,.)${(s..):-smurf}}
# ```
function input() {
	local message string choices_formatted specified_choices
	local symbol='❯'
	local -a valid_choices=()
	local -a choices_values=()
	local choosing_from_array=false  # Pseudo-array, e.g --choices="(foo bar)"
	local choosing_from_assoc_array=false  # Pseudo-associative-array, e.g. --choices="( [j]='jupyter ipython rich' [i]='ipython rich' )"
	local validate_choice=true
	local colored_left_square_bracket="${Cd}[${Cd0}"
	local colored_right_square_bracket="${Cd}]${Cd0}"
	while [[ $# -gt 0 ]]; do
		case "$1" in
			-s) symbol="$2" ; shift ;;
			--choices*)
				if [[ "$1" = --choices=* ]]; then
					specified_choices="${1#*=}"
				else
					specified_choices="$2"
					shift
				fi
				
				# Associative array, e.g. '( [j]='jupyter ipython rich' [i]='ipython rich' )'
				# valid choices are keys, and are displayed as-is
				if [[ "$specified_choices" = '(['*')' || "$specified_choices" = '( ['*')' ]]; then
					choosing_from_assoc_array=true
					local no_parens="${specified_choices//[()]/}"
					typeset -A choices_aa
					eval "choices_aa=(${no_parens})"
					valid_choices=( ${(k)choices_aa} )
					choices_values=( ${(v)choices_aa} )
					choices_formatted="${no_parens//'['/\n${colored_left_square_bracket}${Cb}}"
					choices_formatted="${choices_formatted//]/${Cb0}${colored_right_square_bracket}}\n"

				# Has brackets, e.g '[c]ontinue, [q]uit'
				# valid choices are in brackets, and are displayed as-is
				elif [[ "$specified_choices" = *\[* ]]; then
					choices_formatted="$specified_choices"
					choices_formatted="${choices_formatted//'['/\n${colored_left_square_bracket}${Cb}}"
					choices_formatted="${choices_formatted//]/${Cb0}${colored_right_square_bracket}}\n"
					# in zsh: read -A valid_choices <<< $(grep -Poz '(?<=\[)[^]]+' <<< "$specified_choices") # the z is important
					# valid_choices=( $(echo "$specified_choices" | grep -Po '(?<=\[).(?=\])') )
					valid_choices=( $(command grep -Po '(?<=\[)[^]]+' <<< "$specified_choices") )

				# Pseudo-array, e.g '(foo bar)'
				# valid choices are indices, and are displayed like [1] foo, [2] bar
				elif [[ "$specified_choices" = '('*')' ]]; then
					choosing_from_array=true
					choices_values=( ${(s: :)${specified_choices//[()]/}} )
					valid_choices=( {1..$#choices_values} )
					choices_formatted+="\n"
					for index in "${valid_choices[@]}"; do
						choices_formatted+="${colored_left_square_bracket}${Cb}${index}${Cb0}${colored_right_square_bracket} ${choices_values[$index]}\n"
					done
					choices_formatted+="\n"

				# Range, e.g. '1..3'
				# valid choices are displayed e.g [1, 2, ..., 5], [1, 2, 3] etc
				elif [[ "$specified_choices" = [[:digit:]]..[[:digit:]] ]]; then
					local range_start="${specified_choices%..*}"
					local range_end="${specified_choices#*..}"
					valid_choices=( ${(f)"$(seq -s ' ' "$range_start" "$range_end")"} )
					if [[ "${#valid_choices}" -gt 3 ]]; then
						choices_formatted="${colored_left_square_bracket}${range_start}, $((range_start+1)), ..., $range_end}${colored_right_square_bracket}"
					elif [[ "${#valid_choices}" -eq 3 ]]; then
						choices_formatted="${colored_left_square_bracket}${range_start}, $((range_start+1)), $range_end}${colored_right_square_bracket}"
					else
						choices_formatted="${colored_left_square_bracket}${range_start}, $range_end}${colored_right_square_bracket}"
					fi
				
				# E.g. --choices=y,n -> [y/n]
				# Valid choices are the values themselves, e.g. y or n.
				else
					choices_formatted="${colored_left_square_bracket}${specified_choices//,//}${colored_right_square_bracket}"
					valid_choices=( ${(s.,.)specified_choices} )
				fi ;;
			
			--no-validate) validate_choice=false ;;
			
			*) [[ -n "$message" ]] && message+=" $1" || message="$1" ;;
		esac
		shift
	done
	string="${message}"
	[[ -n "$valid_choices" ]] && string+=" ${C0}${CbrCyn}${choices_formatted}"
	[[ -n "$symbol" ]] && {
		# Pretty but requires the whole thing to use print -P:
		# local colored_symbol="$(print -P "%B%F39${symbol}%f%b")"
		# string+=" ${C0}${colored_symbol}}"
		string+=" ${C0}${CbrBlu}${Cd}${symbol}" 
	}
	local is_yes_no=false
	[[ "${valid_choices[*]}" = 'y n' || "${valid_choices[*]}" = 'n y' ]] && is_yes_no=true
	
	string="\n${CbrGrn}${colored_left_square_bracket}?${colored_right_square_bracket}${C0} ${LEVELS_COLORS[prompt]}${string}"
	
	log "${string}" -n --no-trace --no-level
	
	local user_choice
	if [[ "$is_yes_no" = true ]]; then
		# Special case for confirmation where exit code is expected to match user choice.
		local -i confirmed_code
		read -q -s user_choice
		confirmed_code=$?
		local user_choice_color feedback_symbol
		if [[ $confirmed_code = 0 ]]; then
			user_choice_color="${CbrGrn}"
			feedback_symbol='✔'
		else
			user_choice_color="${CbrRed}"
			feedback_symbol='✘'
		fi
		# shellcheck disable=SC2028
		echo "\b\b\b\b\b\b${user_choice_color}${Cb}${feedback_symbol}${C0}     "
		return $confirmed_code
	else
		read user_choice
	fi
	if [[ $validate_choice = true && -n ${valid_choices} ]]; then
		if [[ ! "${valid_choices[(r)$user_choice]}" ]]; then
			log.warn "Invalid choice: '${user_choice}'. Available choices: ${(j., .)valid_choices}" -L -x
			local input_args=(
				"${message}"
				--choices "${specified_choices}"
			)
			if [[ -n "$symbol" ]]; then
				input_args+=(-s "$symbol")
			fi
			input "${input_args[@]}"
			return $?
		fi
	fi
	if [[ $choosing_from_array = true ]]; then
		print -- "${choices_values[$user_choice]}"
	elif [[ $choosing_from_assoc_array = true ]]; then
		printf "%s" "${choices_aa[$user_choice]}"
	else
		printf "%s" "$user_choice"
	fi
	return $?
}

# # confirm <PROMPT>
# Returns 0 if answer is y,Y,yes,Yes,YES
# ## Examples:
# ```bash
# confirm 'are you sure?' || return 1
# ```
function confirm() {
	# if [[ ! tty -s ]]; then
	#   return 1
	# fi
	if [[ $- != *i* ]]; then
		log.warn "Not interactive. Returning 1"
		return 1
	fi
	input "$@" --choices y,n -s ''
}


{
	complete -o default \
					 -W '-n --no-newline -x --no-trace -L --no-level --offset' \
					 log log.debug log.info log.notice \
					 log.success log.warn log.error log.fatal
	complete -o default \
					 -W '-s --choices --no-validate' \
					 input
	complete -o default \
					 -W '-n --no-newline' \
					 log.prompt
	complete -o default \
					 -W '-n --no-newline -x --no-trace --offset' \
					 log.title log.megasuccess log.megatitle log.megawarn log.megafatal

} 2>/dev/null
