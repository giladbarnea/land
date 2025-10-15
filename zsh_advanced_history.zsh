#!/usr/bin/env zsh

#[[ "$OS" = macos ]] && {
#	! isdefined gsed && {
#		log.error "$0: gsed is required but not found"
#		return 1
#	}
#	[[ "$(realpath "${commands[sed]}")" != "$(realpath "${commands[gsed]}")" ]] && {
#		log.error "$0: 'sed' should be 'gsed' on macOS. sed: $(realpath ${commands[sed]}), gsed: $(realpath ${commands[gsed]})"
#		return 1
#	}
#}
if ! is_interactive && ! is_zunit; then
  log.warn "Not interactive, not loading $0"
  return 1
fi
is_pycharm && {
  return 1
}
[[ "$TERM_PROGRAM" = vscode ]] && {
  return 1
}

if [[ ! -f "$HISTFILE" ]]; then
	log.error "HISTFILE doesn't exist: $HISTFILE. Aborting."
	return 1
fi
export ZSH_ADVANCED_HISTFILE="${ZSH_ADVANCED_HISTFILE:-"$HOME/.zsh_advanced_history"}"
if [[ ! -f "$ZSH_ADVANCED_HISTFILE" ]]; then
	log.error "ZSH_ADVANCED_HISTFILE doesn't exist: $ZSH_ADVANCED_HISTFILE. Aborting."
	return 1
fi

export ZSH_ADVANCED_HIST_TEMPLATE="${ZSH_ADVANCED_HIST_TEMPLATE:-"%s⋮%s⋮%s⋮%s"}"
export HISTFILE="${HISTFILE:-"$HOME/.zsh_history"}"
typeset -g -r ORIG_HISTFILE="$HISTFILE"
typeset -g -r ORIG_ZSH_ADVANCED_HISTFILE="$ZSH_ADVANCED_HISTFILE"
export ZSH_ADVANCED_PINNED_HISTFILE="${ZSH_ADVANCED_PINNED_HISTFILE:-"${ZSH_ADVANCED_HISTFILE}.pinned"}"
export HISTORY_IGNORE="${${HISTORY_IGNORE:-()}:0:-1}|hoff|hon|hdel*|hsub*|hfind*|hclean*|_zah*|_zsh_advanced_history*|_hmode*|hclean.remove_trial_and_error)"
export ZAH_SAVE_ONCE=(
  'paste | base64 -d'
  'cd *'
  'bat pyproject.toml'
  'open *'
  'poe lint*'
  'poe start*'
  'loadnvm'
)
typeset -A -g ZAH_LAST_COMMAND
ZAH_LAST_COMMAND=(
  command ''
  directory ''
  start_timestamp ''
  end_timestamp ''
  exitcode ''
  handled false
)




local CTRL_C=130
local CMD_NOT_FOUND=127

# E.g. ` 2445  1716117024  hoff`
#  1: History line number
#  2: Timestamp — Requires -t %s
local FC_LINE_PREFIX_RE='^[[:space:]]([[:digit:]]{0,5})[[:space:]]{2}([[:digit:]]{10})[[:space:]]{2}'
# E.g. ` 2445  1716117024  0:00  hoff`
#  3: Duration — 0:00. Requires -D
local FC_LINE_W_DURATION_PREFIX_RE="${FC_LINE_PREFIX_RE}([[:digit:]\:]+)[[:space:]]{2}"
#  3: Command
local FC_LINE_RE="${FC_LINE_PREFIX_RE}(.*)$"
#  4: Command
local FC_LINE_W_DURATION_RE="${FC_LINE_W_DURATION_PREFIX_RE}(.*)$"

# E.g. `1716117024⋮/tmp⋮0⋮hoff`
#  1: Timestamp
#  2: Path
#  3: Exit code
#  4: Command
local ZSH_ADVANCED_HIST_LINE_PREFIX_RE='^([[:digit:]]{10})⋮([^⋮]+)⋮([[:digit:]]+|EXITCODE)⋮'
local ZSH_ADVANCED_HIST_LINE_RE="${ZSH_ADVANCED_HIST_LINE_PREFIX_RE}(.+)$"

# E.g. `: 1716117024:0;hoff`
#  1: Timestamp
#  2: Exit code
#  3: Command
local REGULAR_HIST_LINE_PREFIX_RE='^: ([[:digit:]]{10}):([[:digit:]]+);'
local REGULAR_HIST_LINE_RE="${REGULAR_HIST_LINE_PREFIX_RE}(.+)$"




_zah.has_unescaped_exmark(){
	# local exmark_count=0 escaped_exmark_count=0
	# local exmark_count="${#$(command grep --color=never -oF '!' <<< "${1}")}"
	# local escaped_exmark_count="${#$(command grep --color=never -oF '\!' <<< "${1}")}"
  local string="$1"
  local -a exmark_split=("${(s:!:)string}")
  local -a escaped_exmark_split=("${(s:\!:)string}")
	local exmark_count=$(("${#exmark_split}" - 1))
	local escaped_exmark_count=$(("${#escaped_exmark_split}" - 1))
	[[ "$exmark_count" -gt "$escaped_exmark_count" ]]
}

_zah.has_escaped_exmark(){
  local string="$1"
  local -a escaped_exmark_split=("${(s:\!:)string}")
	local escaped_exmark_count=$(("${#escaped_exmark_split}" - 1))
	[[ "$escaped_exmark_count" -gt 0 ]]
}

# # _zah.backup [-v]
# Backs up the history files to $HISTFILE.backup.$(date +%s).
# If the latest backup file is significantly larger than the history file, the backup is aborted.
_zah.backup(){
  local ts="$EPOCHREALTIME"
  local verbose
  zparseopts -F -E - v=verbose|| return $?
  local -a cp_args
  local -a rm_args
  [[ "$verbose" ]] && cp_args+=(-v) && rm_args+=(-v)
  local -a backup_files=()
  local -i total_backup_files_count
  local hist_file
	for hist_file in "${ORIG_HISTFILE}" "${ORIG_ZSH_ADVANCED_HISTFILE}"; do
		backup_files=( "${hist_file}".backup.* )

    command cp "${cp_args[@]}" "${hist_file}" "${hist_file}.backup.${ts}" || return 1

		total_backup_files_count="${#backup_files[@]}"
		((total_backup_files_count++))  # We just created another backup, so +1
	done
	return 0
}

# glob -> extended regex; . -> \. and * -> .*
_zah.matches_HISTORY_IGNORE(){
  #  emulate -L zsh
  #  # setopt extendedglob  # uncomment if HISTORY_IGNORE should use EXTENDED_GLOB syntax
  #  # [[ $1 != ${~HISTORY_IGNORE} ]]
	command grep --color=never -qxE ${${HISTORY_IGNORE//./\\.}//\*/.*} <<< "$1"
}

# # _zah.is_sed_extended_re_opt <ARG>
# Checks if the argument is a sed extended regex option (-E, -r, or --regexp-extended).
_zah.is_sed_extended_re_opt(){
  [[ "$1" = -E || "$1" = -r || "$1" == --regexp-extended ]]
}

_zah.is_positive_number(){
  [[ "$1" =~ ^[0-9]+$ ]]
}

_zah.is_pos_or_neg_number(){
  [[ "$1" =~ ^-?[0-9]+$ ]]
}

# # _zah.is_timestamp <TIMESTAMP>
# Checks if the input 10-digit long and is a positive number.
_zah.is_timestamp() {
  [[ "${#1}" == 10 ]] && _zah.is_positive_number "$1"
}


# # _zah.match_any_reversed <FILE> <PATTERNS...> [--max-lines MAX_LINES=20]
# Prints the first pattern that matches any line in FILE, starting from the end.
# Returns 0 if a match was found, 1 otherwise.
# If MAX_LINES is specified, will stop after MAX_LINES lines from the end.
_zah.match_any_reversed(){
  local file="$1"
  shift
  local -i max_lines=20
  local -a patterns
  while (( $# )); do
    case $1 in
      --max-lines=*) max_lines="${1#--max-lines=}" ;;
      --max-lines) max_lines="$2";  shift ;;
      *) patterns+=("$1") ;;
    esac
    shift
  done

  local pattern
  # Quick optimization: try the last 10 lines
  # local last_10_lines="$(tail -n 10 "$file")"
  for pattern in "${patterns[@]}"; do
    if _zah.sed_matches_batched_reversed "${pattern}" "${file}" -E --max-lines 10; then
      printf "%s" "${pattern}"
      return 0
    fi
    # if [[ -n "$(gsed -nE "/${pattern}/p" <<<"$last_10_lines")" ]] {
    #   printf "%s" "${pattern}"
    #   return 0
    # }
  done
  log.debug "$0 ${Cc}${file}${Cc0} <PATTERNS...> second 10"
  # That didn't work, so let's try the next 10 lines.
  for pattern in "${patterns[@]}"; do
    if _zah.sed_matches_batched_reversed "${pattern}" "${file}" -E --max-lines ${max_lines} --offset 10; then
      printf "%s" "${pattern}"
      return 0
    fi
  done
  log.debug "$0 ${Cc}${file}${Cc0} returning 1"
  return 1
}

# # _zah.sed_matches_batched_reversed <PATTERN> <FILE_OR_STRING> [-E, -r, --regexp-extended] [--offset OFFSET=0] [--batch-size BATCH_SIZE=1000] [--max-lines MAX_LINES]
# Tries to match from end to start, one batch at a time.
# Returns 0 if there are matches, 1 otherwise. Does not print anything.
# OFFSET is the number of lines to skip from the end.
# If MAX_LINES is specified, will stop after MAX_LINES lines from the end.
_zah.sed_matches_batched_reversed() {
  if [[ $# -lt 2 ]]; then
    log.error "$0: Not enough args (expected at least 2, got: $*). Usage:\n$(docstring "$0" -p)"
    return 1
  fi
  local pattern file_or_string
  local -i offset=0
  local -i batch_size=1000
  local -i max_lines
  local sed_args=(-n)
  while [[ $# -gt 0 ]]; do
    if _zah.is_sed_extended_re_opt "$1"; then
      sed_args+=(-E)
    elif [[ "$1" == --offset ]]; then
      offset="$2"
      shift
    elif [[ "$1" = --offset=* ]]; then
      offset="${1#--offset=}"
    elif [[ "$1" == --batch-size ]]; then
      batch_size="$2"
      shift
    elif [[ "$1" = --batch-size=* ]]; then
      batch_size="${1#--batch-size=}"
    elif [[ "$1" = --max-lines=* ]]; then
      max_lines="${1#--max-lines=}"
    elif [[ "$1" = --max-lines ]]; then
      max_lines="$2"
      shift
    else
      if [[ ! "$pattern" ]]; then
        pattern="$1"
      else
        file_or_string="$1"
      fi
    fi
    shift
  done

  local -i line_count=$(command wc -l "$file_or_string" | awk '{print $1}')
  [[ "$offset" -gt "$line_count" ]] && {
    log.warn "$(typeset offset) is greater than the number of lines in the file (${line_count}). Returning 1."
    return 1
  }
  [[ "$max_lines" && "$max_lines" -gt "$line_count" ]] && max_lines="$line_count"
  if [[ "$max_lines" && "$batch_size" -gt $((max_lines - offset)) ]] {
    batch_size=$((max_lines - offset))
  }
  if [[ -f "$file_or_string" ]]; then
    local batch
    local -i i
    local -i start_index
    local -i from_end
    local should_die=false
    for ((i = 1; i <= $((line_count/batch_size)); i++)); do
      from_end="$((i * batch_size + offset))"
      if [[ "$max_lines" && "$from_end" -gt "$max_lines" ]]; then
        start_index="$max_lines"
        should_die=true
      else
        start_index=$((line_count - from_end))
      fi
      batch="$(tail -n ${start_index} "$file_or_string" | head -n "$batch_size")"
      [[ -n "$(gsed "${sed_args[@]}" "/${pattern}/p" <<<"$batch")" ]] && return 0
      [[ "$should_die" = true ]] && return 1
    done
    local -i remainder=$((line_count % batch_size))
    [[ $remainder -gt 0 ]] && {
      batch="$(head -n $remainder "$file_or_string")"
      [[ -n "$(gsed "${sed_args[@]}" "/${pattern}/p" <<<"$batch")" ]] && return 0
    }
    return 1
  else
    [[ "$line_count" -gt 2000 ]] && {
      log.warn "String has ${line_count} lines. Batching is not implemented for strings, should consider."
    }
    [[ -n "$(gsed "${sed_args[@]}" "/${pattern}/p" <<<"$file_or_string")" ]]
  fi
}

# # _zah.sed_matches <PATTERN> <FILE_OR_STRING> [-E, -r, --regexp-extended]
# Convenience wrapper. Returns 0 if there are matches, 1 otherwise. Does not print anything.
_zah.sed_matches(){
  if [[ "$#" -lt 2 || "$#" -gt 3 ]]; then
    log.error "$0: Not enough args (expected betweem 2 and 3). Usage:\n$(docstring "$0")"
    return 1
  fi
  local pattern file_or_string
  local sed_args=(-n)
  while [[ $# -gt 0 ]]; do
    if _zah.is_sed_extended_re_opt "$1"; then
      sed_args+=(-E)
    else
      if [[ ! "$pattern" ]]; then
        pattern="$1"
      else
        file_or_string="$1"
      fi
    fi
    shift
  done
  if [[ -f "$file_or_string" ]]; then
    [[ -n "$(gsed "${sed_args[@]}" "/${pattern}/p" "$file_or_string")" ]]
  else
    [[ -n "$(gsed "${sed_args[@]}" "/${pattern}/p" <<< "$file_or_string")" ]]
  fi
}

_zah.humanize_timestamps() {
  python3 -c '
from datetime import datetime
import sys
def convert_timestamp_to_readable(line):
  if line.strip().startswith(":"):
      # : 1692811800
      parts = line.strip()[1:].strip().split(":")
  else:
      parts = line.split("⋮")
  timestamp = int(parts[0])
  readable_date = datetime.utcfromtimestamp(timestamp).strftime("%Y-%m-%d %H:%M:%S")
  new_line = line.replace(parts[0], readable_date)
  return new_line
input_lines = sys.stdin.readlines()
humanized_timestamps = [convert_timestamp_to_readable(line) for line in input_lines]
print("".join(humanized_timestamps))'
}

# # _zah.get_timestamp_by_line_num <LINE_NUMBER / TIMESTAMP>
# LINE_NUMBER can be positive or negative.
_zah.get_timestamp_by_line_num() {
  local pattern="$1"
  if _zah.is_timestamp "${pattern}"; then
    printf "${pattern}"
    return 0
  fi
  local index="$pattern"
  local timestamp history_exact_match_by_line_number

  # e.g '1693739946  stern eta-job-controller --timestamps'
  history_exact_match_by_line_number=$(vex ---log-only-errors builtin fc -t %s -ln "$index" "$index") || return 1
  timestamp="${history_exact_match_by_line_number%% *}"  # 1693739946
  printf "${timestamp}"
}

# # _zah.extract_command_from_history_line <ADVANCED_HISTORY_LINE/REGULAR_HISTORY_LINE/FC_LINE>
# The following formats will print 'tw bash sed':
# '1716109945⋮/tmp⋮0⋮tw bash sed'
# ' 2445  1716109945  tw bash sed'
# ': 1716109945:0;tw bash sed'
# Returns 0 if result is non-empty, 1 otherwise.
_zah.extract_command_from_history_line() {
  if [[ "$#" -ne 1 ]]; then
    log.error "$0: Not enough args (expected 1). Usage:\n$(docstring "$0")"
    return 1
  fi
  local history_line="$1"
  typeset -A patterns_groups=(
    ["$ZSH_ADVANCED_HIST_LINE_RE"]=_zah.extract_command_from_zah_line
    ["$REGULAR_HIST_LINE_RE"]=_zah.extract_command_from_regular_history_line
    ["$FC_LINE_RE"]=_zah.extract_command_from_fc_line
  )
  local pattern extracting_function extracted_command
  for pattern in "${(k)patterns_groups[@]}"; do
    extracting_function="${patterns_groups[${pattern}]}"
    if extracted_command="$($extracting_function "$history_line")"; then
      printf "${extracted_command}"
      return 0
    fi
  done
  log.warn "No match found for $(typeset history_line)"
  return 1
}

# # _zah.extract_command_from_zah_line <ADVANCED_HISTORY_LINE>
# _zah.extract_command_from_zah_line '1716109945⋮/tmp⋮0⋮tw bash sed'  # 'tw bash sed'
# Returns 0 if result is non-empty, 1 otherwise.
_zah.extract_command_from_zah_line() {
  local history_line="$1"
  shift || { log.error "$0: Not enough args (expected 1). Usage:\n$(docstring "$0")"; return 1; }
  local extracted_command
  # extracted_command="$(gsed -nE "s/${ZSH_ADVANCED_HIST_LINE_RE}/\\4/p" <<<"$history_line")"
  extracted_command="$(awk -F'⋮' '{print $4}' <<<"$history_line")"
  if [[ -n "${extracted_command}" ]] {
    printf "%s" "${extracted_command}"
    return 0
  }
  return 1
}

# # _zah.extract_command_from_regular_history_line <REGULAR_HISTORY_LINE>
# _zah.extract_command_from_regular_history_line ': 1716109945:0;tw bash sed'  # 'tw bash sed'
# Returns 0 if result is non-empty, 1 otherwise.
_zah.extract_command_from_regular_history_line() {
  local history_line="$1"
  shift || { log.error "$0: Not enough args (expected 1). Usage:\n$(docstring "$0")"; return 1; }
  local extracted_command
  extracted_command="$(awk -F';' '{print $2}' <<< "$history_line")"
  if [[ -n "${extracted_command}" ]] {
    printf "%s" "${extracted_command}"
    return 0
  }
  return 1
}

# # _zah.extract_command_from_fc_line <FC_LINE>
# _zah.extract_command_from_fc_line ' 2445  1716109945  tw bash sed'  # 'tw bash sed'
# Returns 0 if result is non-empty, 1 otherwise.
_zah.extract_command_from_fc_line() {
  local history_line="$1"
  shift || { log.error "$0: Not enough args (expected 1). Usage:\n$(docstring "$0")"; return 1; }
  local extracted_command
  extracted_command="$(gsed -nE "s/${FC_LINE_RE}/\\3/p" <<<"$history_line")"
  if [[ -n "${extracted_command}" ]] {
    printf "%s" "${extracted_command}"
    return 0
  }
  return 1
}

# # _zah.pin <COMMAND> [TIMESTAMP]
_zah.pin(){
  local cmd="${1%\#*}"  # Remove #!pin suffix.
  _zah.has_escaped_exmark "$cmd" && log.warn "$(typeset cmd) contains escaped '!'. It will be escaped twice."
  cmd="${cmd//\!/\\!}"  # Escape '!' for sed.
  cmd="${cmd# }"        # Remove leading space if exists.
  cmd="${cmd% }"        # Remove trailing space if exists.
  local start_ts="${2}"
  [[ ! "$start_ts" ]] && start_ts="$EPOCHSECONDS"
  local whole_line_pattern="${ZSH_ADVANCED_HIST_LINE_PREFIX_RE}${cmd}$"
  [[ -n "$(gsed -n -E '\!'"${whole_line_pattern}"'!p' "$ZSH_ADVANCED_PINNED_HISTFILE")" ]] && {
    log.info "${Cgrn}✔${C0} Already pinned: ${Cc}${cmd}" -L -x
    return 0
  }
  printf "${ZSH_ADVANCED_HIST_TEMPLATE}\n" "$start_ts" "$PWD" "$cmd" >> "${ZSH_ADVANCED_PINNED_HISTFILE}"
  log.success "${Cgrn}✔${C0} Pinned: ${Cc}${cmd}" -L -x
  return $?
}


# ---------------------------
# ---------[ Hooks ]---------
# ---------------------------

# Hook! no need to add-zsh-hook, just implement it, or add-zsh-hook zshaddhistory _my_function
#zshaddhistory() {
#  emulate -L zsh
#  ## uncomment if HISTORY_IGNORE should use EXTENDED_GLOB syntax
#  # setopt extendedglob
#  # [[ $1 != ${~HISTORY_IGNORE} ]]
#  local last_exit_code=$?
#  echo "[zshaddhistory] last_exit_code: $last_exit_code | 0: $0 | 1: $1 | 2: $2 | #: $# | *: $*"
#}

# function _history_filter() {
#   # Executed 1st
#   local ts=$(date +%s)
#   local last_exit_code=$?
#   echo "[zshaddhistory] last_exit_code: $last_exit_code | ts: $ts | 0: $0 | 1: $1 | 2: $2 | #: $# | *: $*"
#   # return $last_exit_code
# }

# https://github.com/MichaelAquilina/zsh-history-filter/blob/master/zsh-history-filter.plugin.zsh
# https://github.com/jgogstad/passwordless-history/blob/master/passwordless-history.plugin.zsh
#add-zsh-hook zshaddhistory _history_filter

_zsh_advanced_history_write_line_metadata_preexec() {
  # Invoked 2nd, before the command is executed
  #  Has access to the command itself, but not to the command exit code (hasn't exited yet).
  #  Sets global ZAH_LAST_COMMAND command, directory, and start timestamp.
  #  Sets handled=true if:
  #  - current command is the same as the one before it
  #  - current command matches history ignore.
  #  Note: history[$((HISTCMD - 1))] contains the previous command. It is updated AFTER this hook exits.
  _hmode || return 0
  local start_ts="$EPOCHSECONDS"  # Like date +%s
  local cmd="$1"

  _zah.matches_HISTORY_IGNORE "$cmd" && {
    ZAH_LAST_COMMAND[handled]=true
    return 0
  }

  [[ "${ZAH_LAST_COMMAND[command]}" = "$cmd" ]] && {
    # Make room for more recent entry.
    gsed -i '$d' "$ZSH_ADVANCED_HISTFILE"  # No -n is needed.
  }
  ZAH_LAST_COMMAND=(
    [command]="$cmd"
    [directory]="$PWD"
    [start_timestamp]="$start_ts"
    [end_timestamp]=""
    [exitcode]=""
    [handled]=false
  )
  [[ "${ZAH_LAST_COMMAND[command]}" && "${ZAH_LAST_COMMAND[command]}" =~ '^.*#!pin *' ]] && _zah.pin "${ZAH_LAST_COMMAND[command]}" "$start_ts"

  local previous_command_from_zsh_memory="${history[$((HISTCMD - 1))]}"
  [[ "$$previous_command_from_zsh_memory" = "${ZAH_LAST_COMMAND[command]}" ]] && {
    # Not sure when this happens?
    ZAH_LAST_COMMAND[handled]=true
    return 0
  }
}

_zsh_advanced_history_replace_exitcode_placeholder_precmd() {
  # Invoked 3rd, after the command is done executing.
  #  Has access to the command's exitcode, but not to the command itself.
  #  Appends to ZSH_ADVANCED_HISTFILE, having acquired the command's exit code and end timestamp.
  ZAH_LAST_COMMAND[exitcode]="$?"
  ZAH_LAST_COMMAND[end_timestamp]="$EPOCHSECONDS"
  _hmode || return 0

  # On a new terminal session, ZAH_LAST_COMMAND is empty. We assume it has been handled, so we exit. Trivia: $history has the previous session's last command.
  [[ ! "${ZAH_LAST_COMMAND[command]}" ]] && return 0
  [[ ${ZAH_LAST_COMMAND[handled]} = true ]] && return 0
  if [[ "${ZAH_LAST_COMMAND[exitcode]}" = "${CTRL_C}" || "${ZAH_LAST_COMMAND[exitcode]}" = "${CMD_NOT_FOUND}" ]] && return 0
  printf "${ZSH_ADVANCED_HIST_TEMPLATE}\n" "${ZAH_LAST_COMMAND[start_timestamp]}" "${ZAH_LAST_COMMAND[directory]}" "${ZAH_LAST_COMMAND[exitcode]}" "${ZAH_LAST_COMMAND[command]}" >> "${ZSH_ADVANCED_HISTFILE}"
}

_zah.register_hooks(){
  # https://github.com/xav-b/zsh-extend-history/blob/master/extend-history.plugin.zsh
  # [[ ! " ${precmd_functions[*]} " =~ " _zsh_advanced_history_replace_exitcode_placeholder_precmd " ]] && \
  #   precmd_functions+=(_zsh_advanced_history_replace_exitcode_placeholder_precmd)
  # [[ ! " ${preexec_functions[*]} " =~ " _zsh_advanced_history_write_line_metadata_preexec " ]] && \
  #   preexec_functions+=(_zsh_advanced_history_write_line_metadata_preexec)
  add-zsh-hook precmd _zsh_advanced_history_replace_exitcode_placeholder_precmd
  add-zsh-hook preexec _zsh_advanced_history_write_line_metadata_preexec
}

_zah.unregister_hooks(){
  # https://github.com/xav-b/zsh-extend-history/blob/master/extend-history.plugin.zsh
  # precmd_functions=( ${precmd_functions[@]/_zsh_advanced_history_replace_exitcode_placeholder_precmd} )
  # preexec_functions=( ${preexec_functions[@]/_zsh_advanced_history_write_line_metadata_preexec} )
  add-zsh-hook -d precmd _zsh_advanced_history_replace_exitcode_placeholder_precmd
  add-zsh-hook -d preexec _zsh_advanced_history_write_line_metadata_preexec
}

# ------------------------------------
# ---------[ History Switch ]---------
# ------------------------------------

hoff() {
  local quiet=false
  [[ "$1" = -q || "$1" = --quiet ]] && quiet=true
  local histfile_before="$HISTFILE"
  local zsh_advanced_histfile_before="$ZSH_ADVANCED_HISTFILE"
  export HISTFILE=/dev/null
  export ZSH_ADVANCED_HISTFILE=/dev/null
  _zah.unregister_hooks
  [[ "$quiet" = false ]] && log.success "HISTFILE: ${Cc}${histfile_before}${Cc0} and ZSH_ADVANCED_HISTFILE: ${Cc}${zsh_advanced_histfile_before}${Cc0} -> ${Cc}/dev/null${Cc0}"
}
hon() {
  local quiet=false
  [[ "$1" = -q || "$1" = --quiet ]] && quiet=true
  export HISTFILE="$ORIG_HISTFILE"
  export ZSH_ADVANCED_HISTFILE="$ORIG_ZSH_ADVANCED_HISTFILE"
  _zah.register_hooks
  [[ "$quiet" = false ]] && log.success "HISTFILE: ${Cc}${HISTFILE}${Cc0} and ZSH_ADVANCED_HISTFILE: ${Cc}${ZSH_ADVANCED_HISTFILE}${Cc0}"
}


# Make sure POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS includes 'history_mode' in ~/.p10k.zsh
prompt_history_mode() {
	! _hmode && p10k segment -f 208 -t 'hist off'
}

# # _hmode
# Returns 0 if history is on, 1 otherwise.
_hmode() {
  ! [[ "$HISTFILE" == /dev/null && "$ZSH_ADVANCED_HISTFILE" == /dev/null ]]
}

# -------------------------------------------------
# ---------[ History Manipulation (User) ]---------
# -------------------------------------------------

# # hdel <PATTERN / TIMESTAMP / POSITIVE_OR_NEGATIVE_INDEX / LINE_NUMBER> [-E, -r, --regexp-extended] [-a, --all]
# Delete matching lines from history files.
# If -a/--all is specified, deletes from backup files as well.
hdel(){
	log.debug "hdel: $*"
  local pattern  # Can be a timestamp, a line number, or a pattern
  local delete_in_backups=false
  local -a sed_args

  while [[ $# -gt 0 ]]; do
    if _zah.is_sed_extended_re_opt "$1"; then
      sed_args+=(-E)
    elif [[ "$1" = -a || "$1" = --all ]]; then
      delete_in_backups=true
    else
      pattern="$1"
    fi
    shift
  done

  if [[ ! "$pattern" ]]; then
    log.fatal "$0: Missing required PATTERN argument. Usage:"
    docstring "$0" -p
    return 1
  fi

  _zah.has_unescaped_exmark "$pattern" && { log.error "Pattern contains unescaped '!'. Rerun and escape '!'" ; return 1 ; } ;

  if _zah.is_pos_or_neg_number "${pattern}"; then
    pattern="$(_zah.get_timestamp_by_line_num "${pattern}")"
  elif [[ ! ${sed_args[(r)-E]} ]] && is_regex_pattern "${pattern}"; then
    confirm "$(typeset pattern) looks like a regex pattern. Add -E to sed_args?" && sed_args+=(-E)
  fi

  local hist_file hist_line
  local hist_files=("${ORIG_HISTFILE}" "${ORIG_ZSH_ADVANCED_HISTFILE}")
  if "$delete_in_backups"; then
    hist_files+=("${ORIG_HISTFILE}.backup".*)
    hist_files+=("${ORIG_ZSH_ADVANCED_HISTFILE}.backup".*)
  fi

  # First, print lines that would be deleted.
  for hist_file in "${hist_files[@]}"; do
  	log.title "Lines in ${hist_file} that would be deleted:" -x
    while read -r hist_line; do
      gsed -n "${sed_args[@]}" "\!${hist_line}! {=;p}" "${hist_file}"
      printf "\n"
    done < <(gsed "${sed_args[@]}" -n "\!${pattern}!p" "${hist_file}")  # Whole line, not only matching part, for exact matches
	done


	confirm "Continue? (backing up files first)" || return 1
	_zah.backup || { log.error "Backup failed. Aborting." ; return 1 ; }

  # Then, delete the lines.
  for hist_file in ${hist_files}; do
  	gsed "${sed_args[@]}" -i "\!${pattern}!d" "${hist_file}" || {
      confirm "Failed to delete lines from ${hist_file}. Continue to next files?" || return 1
    }
  done

}

# # hsub <SEARCH> <REPLACE> [-E, -r, --regexp-extended]
# Currently, works blindly on the whole line, not just the command part.
hsub(){
	log.debug "1: ${1} | 2: ${2}"
  local search replace
  local -a sed_args
  while (( $# )); do
    if _zah.is_sed_extended_re_opt "$1"; then
      sed_args+=(-E)
    else
			if [[ ! "$search" ]]; then
				search="$1"
			elif [[ ! "$replace" ]]; then
        replace="$1"
			else
			  log.fatal "$0: Too many pos args (expected at least 2). Usage:\n$(docstring "$0")"
        return 1
			fi
    fi
    shift
  done
  if [[ ! "$search" || ! "$replace" ]]; then
  	log.fatal "$0: Not enough args (expected at least 2). Usage:\n$(docstring "$0")" ; return 1
  fi
  _zah.has_unescaped_exmark "$search" && { log.error "Search pattern contains unescaped '!'. Rerun and escape '!'" ; return 1 ; } ;
  _zah.has_unescaped_exmark "$replace" && { log.error "Replace pattern contains unescaped '!'. Rerun and escape '!'" ; return 1 ; } ;
  if [[ ! "${sed_args[(r)-E]}" ]] && is_regex_pattern "${search}" || is_regex_pattern "${replace}"; then
    confirm "Either $(typeset search) or $(typeset replace) look like a regex pattern. Add -E to sed_args?" && sed_args+=(-E)
  fi

	local _histfile
	for _histfile in "$ORIG_HISTFILE" "$ORIG_ZSH_ADVANCED_HISTFILE"; do
		log.title "Matching lines in ${_histfile}:" -x
		cat -n "${_histfile}" | gsed "${sed_args[@]}" -n "\!${search}!p" || return 1
	done
  confirm "Continue? (backing up files first)" || return 1
	_zah.backup || { log.error "Backup failed. Aborting." ; return 1 ;}

  for _histfile in "$ORIG_HISTFILE" "$ORIG_ZSH_ADVANCED_HISTFILE"; do
  	gsed "${sed_args[@]}" -i "s!${search}!${replace}!g" "${_histfile}" || return 1
  done
  log.success "${Cgrn}✔${C0} Replaced ${Cc}${search}${C0} with ${Cc}${replace}${C0} in ${Cc}${ORIG_HISTFILE}${C0} and ${Cc}${ORIG_ZSH_ADVANCED_HISTFILE}${C0}." -L -x
}

# hfind [-d DIR=.+] [-x EXITCODE=.+] [-f ADV_HIST_FILE] [--fc] [-p,--pretty] [-a, --all] [-e, --exact-match] [COMMAND_PATTERN=.*]
# For the regular history file: matches COMMAND_PATTERN with the part after the `;`.
# For advanced zsh history files: $dir⋮$exitcode⋮COMMAND_PATTERN.
# -d DIR              Filter for where the command was executed.
# -x EXITCODE         Filter for EXITCODE. Can be a pattern, e.g "\[^0\]+"
# -f ADV_HIST_FILE    Search this file instead of $ORIG_ZSH_ADVANCED_HISTFILE.
# -a, --all           Search in backup files as well. If `--fc` is used, regular history backups are skipped.
# --fc                When searching $HISTFILE, use `builtin fc -t %s -l 0 | gsed /digits and spaces ${pattern} digits and spaces/` instead of `gsed /${pattern}/`.
# -p, --pretty        Humanize timestamps.
# -e, --exact-match   COMMAND_PATTERN is the whole command – `⋮${pattern}$` – not a substring – `⋮.*${pattern}.*`.
hfind(){
  setopt localoptions null_glob
  [[ "$*" = *--help* || "$*" = -h ]] && { docstring "$0" 1>&2 ; return 0 ; } ;
  local find_in_backups=false
  local exact_match=false
	local dir exitcode pattern complete_pattern use_fc advanced_histfile pretty pager
	local -a advanced_histfiles
  local -a regular_histfiles=("${ORIG_HISTFILE}")
  zparseopts -D -E - d:=dir x:=exitcode -fc=use_fc f:=advanced_histfile p=pretty -pretty=pretty a=find_in_backups -all=find_in_backups e=exact_match -exact-match=exact_match
  dir="${${dir[2]}:-.+}"
  exitcode="${${exitcode[2]}:-.+}"
  advanced_histfile="${${advanced_histfile[2]}:-${ORIG_ZSH_ADVANCED_HISTFILE}}"
  advanced_histfiles+=("${advanced_histfile}" "${ZSH_ADVANCED_PINNED_HISTFILE}")
  if [[ "$find_in_backups" ]]; then
    advanced_histfiles+=("${ORIG_ZSH_ADVANCED_HISTFILE}.backup".*)
    regular_histfiles+=("${ORIG_HISTFILE}.backup".*)
  fi
  [[ "$pretty" ]] && pager=_zah.humanize_timestamps || pager=cat
  pattern=${1:-.*}
  [[ "$exact_match" ]] && complete_pattern="${pattern}" || complete_pattern=".*${pattern}.*"
  log.debug "dir=${dir} │ exitcode=${exitcode} │ pattern='${pattern}' │ complete_pattern='${complete_pattern}' │ use_fc=${use_fc} │ advanced_histfiles=(${advanced_histfiles[*]}) │ pager=${pager}"
  local arg
  for arg in "${dir}" "${exitcode}" "${pattern}"; do
		_zah.has_unescaped_exmark "$arg" && { log.error "${Cc}${arg}${Cc0} contains unescaped ${Cc}!${Cc0}. Rerun and escape ${Cc}!${Cc0}" ; return 1 ; } ;
	done

  local regular_histfile whole_line_pattern search_results any_result_found=false
  if [[ "$use_fc" ]]; then
  	[[ ! -f "$HISTFILE" ]] && log.warn "HISTFILE ($HISTFILE) does not exist, fc may behave weirdly"
    if _zah.is_timestamp "$pattern"; then
      whole_line_pattern="^[[:space:]][[:digit:]]+[[:space:]]{2}${pattern}[[:space:]]{2}"
    else
      whole_line_pattern="${FC_LINE_PREFIX_RE}${complete_pattern}$"
    fi
    search_results="$(builtin fc -t %s -l 0 | gsed -n -E "/${whole_line_pattern}/p")"
    [[ -z "$search_results" ]] && continue
    any_result_found=true
    log.megatitle "Matches in ${ORIG_HISTFILE}:" -x
    echo "${search_results}"
  else
    for regular_histfile in "${regular_histfiles[@]}"; do
      whole_line_pattern="${REGULAR_HIST_LINE_PREFIX_RE}${complete_pattern}$"
      search_results="$(gsed -n -E '\!'"${whole_line_pattern}"'!p' "${regular_histfile}")"
      [[ -z "$search_results" ]] && continue
      any_result_found=true
      log.megasuccess "Matches in ${regular_histfile}:" -x
      $pager <<< "${search_results}"
    done
  fi

  local adv_histfile whole_line_pattern_zah
  for adv_histfile in "${advanced_histfiles[@]}"; do
    whole_line_pattern_zah=".+⋮${dir}⋮${exitcode}⋮${complete_pattern}$"
    search_results="$(gsed -n -E '\!'"${whole_line_pattern_zah}"'!p' "$adv_histfile")"
    [[ -z "$search_results" ]] && continue
    any_result_found=true
	  log.megatitle "Matches in ${adv_histfile}:" -x
    $pager <<< "${search_results}"
  done
  
  [[ "$any_result_found" = false ]] && log.warn "No matches found."
}

hclean(){
  # Remove consecutive duplicates. Lines are considered duplicates if they have the same path, exitcode and command (not timestamp).
  confirm "Start an interactive cleanup of ${ORIG_ZSH_ADVANCED_HISTFILE}?" || return 0
  hclean.remove_consecutive_duplicates
  # hclean.remove_invalid_format
  hclean.remove_hist_ignore_matches
  # hclean.pin_marked_commands
  # hclean.remove_pinned_duplicates
  # hclean.remove_trial_and_error

}

hclean.remove_consecutive_duplicates(){
  setopt localoptions errreturn
  local temp_clean_file="${ORIG_ZSH_ADVANCED_HISTFILE}.clean.tmp"
  log.prompt "Removing consecutive duplicates from ${ORIG_ZSH_ADVANCED_HISTFILE} into ${temp_clean_file}"
  awk -F '⋮' 'NR==1 {print; prev=$2 FS $3 FS $4; next} {curr=$2 FS $3 FS $4} curr != prev {print; prev=curr}' "${ORIG_ZSH_ADVANCED_HISTFILE}" > "${temp_clean_file}"
  log.prompt "Showing diff in 2 seconds..."
  sleep 2
  delta "${ORIG_ZSH_ADVANCED_HISTFILE}" "${temp_clean_file}" || true
  local line_count_diff="$(($(command wc -l < "${ORIG_ZSH_ADVANCED_HISTFILE}") - $(command wc -l < "${temp_clean_file}")))"
  if [[ "$line_count_diff" -eq 0 ]]; then
    log.success -x -L "No consecutive duplicates found."
    return 0
  fi
  confirm "Apply changes to ${ORIG_ZSH_ADVANCED_HISTFILE}? (${line_count_diff} lines will be removed)" || return 1
  local backup_file="${ORIG_ZSH_ADVANCED_HISTFILE}.backup.${EPOCHREALTIME}"
  cp -v "${ORIG_ZSH_ADVANCED_HISTFILE}" "${backup_file}"
  mv -v "${temp_clean_file}" "${ORIG_ZSH_ADVANCED_HISTFILE}" || {
    log.error "Failed to move ${temp_clean_file} to ${ORIG_ZSH_ADVANCED_HISTFILE}. Backup is at ${backup_file}"
    return 1
  }
  log.prompt "Verifying changes..."
  awk -F '⋮' 'NR==1 {print; prev=$2 FS $3 FS $4; next} {curr=$2 FS $3 FS $4} curr != prev {print; prev=curr}' "${ORIG_ZSH_ADVANCED_HISTFILE}" >"${temp_clean_file}"
  local line_count_diff="$(($(command wc -l <"${ORIG_ZSH_ADVANCED_HISTFILE}") - $(command wc -l <"${temp_clean_file}")))"
  if [[ "$line_count_diff" -eq 0 ]]; then
    log.success -x -L "No consecutive duplicates found in ${ORIG_ZSH_ADVANCED_HISTFILE} after cleanup."
    return 0
  else
    log.warn "${line_count_diff} consecutive duplicates found in ${ORIG_ZSH_ADVANCED_HISTFILE} after cleanup. Backup is at ${backup_file}"
    return 1
  fi
}

hclean.remove_hist_ignore_matches(){
  local temp_clean_file="${ORIG_ZSH_ADVANCED_HISTFILE}.clean.tmp"
  confirm "Remove lines with commands matching HISTORY_IGNORE from ${ORIG_ZSH_ADVANCED_HISTFILE} into ${temp_clean_file}? Takes a few good minutes." || return 0
  local zah_line extracted_command
  local -a matching_histignore_lines
  local -a lines_failed_command_extraction
  local -i count=0
  while read -r zah_line; do
    if extracted_command="$(_zah.extract_command_from_zah_line "$zah_line")"; then
      _zah.matches_HISTORY_IGNORE "$extracted_command" && matching_histignore_lines+=("$zah_line")
      ((count++))
      [[ $((count % 500)) -eq 0 ]] && log.info "Processed ${count} lines" -L
    else
      lines_failed_command_extraction+=("$zah_line")
    fi
  done <"${ORIG_ZSH_ADVANCED_HISTFILE}"
  print -l "${(v)matching_histignore_lines[@]}" > /tmp/hist_ignore_matches
  print -l "${(v)lines_failed_command_extraction[@]}" > /tmp/hist_ignore_failed_command_extraction
  command grep -v -F -x -f /tmp/hist_ignore_matches "${ORIG_ZSH_ADVANCED_HISTFILE}" > "${temp_clean_file}"
  log.prompt "Found ${#matching_histignore_lines} lines matching HISTORY_IGNORE; wrote to ${temp_clean_file}"
  if [[ -s /tmp/hist_ignore_failed_command_extraction ]] {
    log.warn "Failed to extract command from ${#lines_failed_command_extraction} lines. " \
             "See /tmp/hist_ignore_failed_command_extraction"
  }
}

hclean.remove_trial_and_error() {
  sgpt <<EOF
above are a few lines of shell history. the format is TIMESTAMP⋮PATH⋮EXITCODE⋮COMMAND. sometimes a command fails because of a human mistake: maybe the arguments were not specified correctly, or there was a typo, etc. this will always result in a non-zero exit code. finally, after a few tries, the programmer manages to get the command right, which is always a 0 exit code.
find instances where it looks like the developer got a command wrong at least once before getting it right.
EOF
  # This is also a trial-and-error scenario, without errors.
  # 1666478043⋮/Users/gilad/dev/buildingblocksrepo⋮0⋮docker compose up --help | grep build
  # 1666478074⋮/Users/gilad/dev/buildingblocksrepo⋮0⋮docker compose up --help | grep -Po '(?<=--build)\s*[^$]+'
  # 1666478089⋮/Users/gilad/dev/buildingblocksrepo⋮0⋮docker compose up --help | grep -Po '(?<=--build)(?<=\s)*[^$]+'
  # 1666478095⋮/Users/gilad/dev/buildingblocksrepo⋮1⋮docker compose up --help | grep -Po '(?<=--build)(?<=\s)+[^$]+'
  # 1666478104⋮/Users/gilad/dev/buildingblocksrepo⋮0⋮docker compose up --help | grep -Po '(?<=--build)[^$]+'
  # 1666478125⋮/Users/gilad/dev/buildingblocksrepo⋮0⋮docker compose up --help | grep -Po '(?<=--force)[^$]+'

  # This is another scenario, where the hardcoded path is constant but everything else changes (printers, editors, grep etc).
  #1667799817⋮/Users/gilad/dev/buildingblocksrepo⋮0⋮bat /Users/gilad/dev/queryservice/job_orchestration/.venv/lib/python3.8/site-packages/IPython/core/extensions.py
  #1667799885⋮/Users/gilad/dev/buildingblocksrepo⋮0⋮sed '/Loading extensions/,+4d' /Users/gilad/dev/queryservice/job_orchestration/.venv/lib/python3.8/site-packages/IPython/core/extensions.py
  #1667799937⋮/Users/gilad/dev/buildingblocksrepo⋮0⋮sed '/if mod.__file__.startswith\(self.ipython_extension_dir\)/,+5d' /Users/gilad/dev/queryservice/job_orchestration/.venv/lib/python3.8/site-packages/IPython/core/extensions.py
  #1667800020⋮/Users/gilad/dev/buildingblocksrepo⋮0⋮sed -E '/if mod\.__file__\.startswith\(self\.ipython_extension_dir\)/,+5d' /Users/gilad/dev/queryservice/job_orchestration/.venv/lib/python3.8/site-packages/IPython/core/extensions.py
  #1667800025⋮/Users/gilad/dev/buildingblocksrepo⋮0⋮sed -i -E '/if mod\.__file__\.startswith\(self\.ipython_extension_dir\)/,+5d' /Users/gilad/dev/queryservice/job_orchestration/.venv/lib/python3.8/site-packages/IPython/core/extensions.py
  #1667800026⋮/Users/gilad/dev/buildingblocksrepo⋮0⋮bat /Users/gilad/dev/queryservice/job_orchestration/.venv/lib/python3.8/site-packages/IPython/core/extensions.py
  #1667800040⋮/Users/gilad/dev/buildingblocksrepo⋮0⋮gsed -i -E '/if mod\.__file__\.startswith\(self\.ipython_extension_dir\)/,+5d' /Users/gilad/dev/queryservice/job_orchestration/.venv/lib/python3.8/site-packages/IPython/core/extensions.py
  #1667800042⋮/Users/gilad/dev/buildingblocksrepo⋮0⋮bat /Users/gilad/dev/queryservice/job_orchestration/.venv/lib/python3.8/site-packages/IPython/core/extensions.py
  #1667800076⋮/Users/gilad/dev/buildingblocksrepo⋮0⋮bat /Users/gilad/dev/termwiki/.venv/lib/python3.11/site-packages/IPython/core/extensions.py
  #1667800097⋮/Users/gilad/dev/buildingblocksrepo⋮2⋮rg -uu 'Loading extensions from .* is deprecated' --type=py --no-messages --files-with-match /
  #1667800099⋮/Users/gilad/dev/buildingblocksrepo⋮2⋮rg -uu 'Loading extensions from .* is deprecated' --type=py --no-messages --files-with-matches /
  #1667800146⋮/Users/gilad/dev/buildingblocksrepo⋮0⋮batw rgsed
  #1667802243⋮/Users/gilad/dev/buildingblocksrepo⋮0⋮micro /tmp/files
  #1667802255⋮/Users/gilad/dev/buildingblocksrepo⋮0⋮tw sed
  #1667802277⋮/Users/gilad/dev/buildingblocksrepo⋮0⋮bat /tmp/files
  #1667802878⋮/Users/gilad/dev/buildingblocksrepo⋮0⋮gsed -i -E '/if mod\.__file__\.startswith\(self\.ipython_extension_dir\)/,/dir\=compress_user/d' /Users/gilad/dev/queryservice_master/.venv/lib/python3.8/site-packages/IPython/core/extensions.py
  #1667802882⋮/Users/gilad/dev/buildingblocksrepo⋮0⋮bat /Users/gilad/dev/queryservice_master/.venv/lib/python3.8/site-packages/IPython/core/extensions.py
  #1667802895⋮/Users/gilad/dev/buildingblocksrepo⋮1⋮cat /tmp/ipython_extensions_files | map gsed -i -E "'/if mod\.__file__\.startswith\(self\.ipython_extension_dir\)/,/dir\=compress_user/d'" '{}'
  #1667802912⋮/Users/gilad/dev/buildingblocksrepo⋮2⋮rg -uu 'Loading extensions from .* is deprecated' --type=py --no-messages --files-with-matches /
  #1667803413⋮/Users/gilad/dev/buildingblocksrepo⋮0⋮bat /opt/homebrew/lib/python3.9/site-packages/IPython/core/extensions.py
  #1667803446⋮/Users/gilad/dev/buildingblocksrepo⋮1⋮cat /tmp/ipython_extensions_files | map gsed -i -E "'/if mod\.__file__\.startswith\(self\.ipython_extension_dir\)/,/dir\=compress_user/d'" '{}'
  #1667803465⋮/Users/gilad/dev/buildingblocksrepo⋮2⋮rg -uu 'Loading extensions from .* is deprecated' --type=py --no-messages --files-with-matches /
  #1667803496⋮/Users/gilad/dev/buildingblocksrepo⋮0⋮bat /Library/Python/3.8/site-packages/IPython/core/extensions.py
  #1667803521⋮/Users/gilad/dev/buildingblocksrepo⋮0⋮bat /opt/homebrew/lib/python3.9/site-packages/IPython/core/extensions.py
}

_zah.register_hooks
# hoff -q
