#!/usr/bin/env bash
# sourced towards the end, after proc.sh and before misc.sh

# # launch.focus_any <PROCESSES>
function launch.focus_any(){
	log.debug "$0 ${Cc}$*"
	local proc focusable
	while read -r proc; do
		focusable="$(proc.get_focusable "$proc")"
		proc.focus "$focusable" && return 0
	done <<< "$processes"
	log.error "All given processes failed to focus"
	return 1
}

# # launch.verify <QUERY...> [--last-proc=QUERY]
# `pgrep -fa "$*" is called immediately, then again after a short delay.
# if --last-proc is specified, any found processes
# Expects all of `launch` args, plus [--last-proc=QUERY] to compare newly found processes to what
# If --last-proc isn't specified, it's assumed
function launch.verify() {
	if [[ ! "$1" ]]; then
	  log.error "$0: expecting at least 1 arg"
	  return 1
	fi
  local processes newest_process preexisting_proc query
  local positional=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --last-proc=*)
    	preexisting_proc="${1##*=}"
    	[[ "${preexisting_proc}" ]] && log.debug "preexisting_proc: ${preexisting_proc}"
    	shift ;;
    *) positional+=("$1"); shift ;;
    esac
  done
  set -- "${positional[@]}" # restore positional params
  local slow_startup=(
    vlc
  )

  # * Check 1st time immediately
  # TODO (sometimes bug): `npm start` doesn't create processes matching "npm start", only "npm"
  query="${*}"
  # processes="$(pgrep -fa "$query" || pgrep -fai "$query")"
  processes="$(proc.pgrep "$query" || proc.pgrep -i "$query")"
  [[ "$processes" ]] && { log.info "query: ${Cc}${query}${Cc0}\nPre-existing processes:" -L; proc.pprint "$processes" ; }

  # 'launch' may have been used to start a 2nd instance of something,
  # in which case user is expected to provide --last-proc=...;
  # if not provided, we assume any found process is a new process.
  if [[ "$processes" && "$processes" != *"winactivate"*"$1"* && ! "$preexisting_proc" ]]; then
    log.success "Success:" -L
    proc.pprint "$processes"
    return 0
  fi

	# * Check 2nd time after a short sleep
  local sleep_s
  if [[ ${slow_startup[(r)"$1"]} ]]; then
    sleep_s=1.5
  else
    sleep_s=0.5
  fi

  log.debug "Sleeping ${sleep_s} secs..."
  sleep "${sleep_s}"

  # processes="$(pgrep -fa "$query" || pgrep -fai "$query")"
  processes="$(proc.pgrep "$query" || proc.pgrep -i "$query")"

  if [[ "$processes" && "$processes" != *"winactivate"*"$1"* && ! "$preexisting_proc" ]]; then
    log.success "Success:" -L
		proc.pprint "$processes"
    return 0
  fi

  if [[ ! "$processes" ]]; then
    # * Surround with with '.*' and replace space with '.*', and try again
    # foo bar -> ".*foo.*bar.*"
    local pos_args="${*}"
    query='.*'${pos_args// /.*}'.*'
    log.warn "No processes found; replaced spaces with '.*' in \$query and ${Cc}pgrep${Cc0}ping again ${Cc}${query}${Cc0}..."
    # processes="$(pgrep -fa "$query" || pgrep -fai "$query")"
    processes="$(proc.pgrep "$query" || proc.pgrep -i "$query")"
    [[ ! "$processes" ]] && {
    	log.error "No matches with ${Cc}${query}${Cc0}, even case insensitively. Returning 1"
    	return 1
    }
  fi

  # * $process were found (good), but:
  # * either $preexisting_proc is not empty, so we need to make sure new != old;
  # * or $processes had 'winactivate'; or both
  # newest_process="$(pgrep -fan "$query" || pgrep -fain "$query")"
  newest_process="$(proc.pgrep -n "$query" || proc.pgrep -i -n "$query")"
  # We're happy if newest process != $preexisting_proc
  log.debug "newest_process: ${Cc}$newest_process"
  if [[ "$newest_process" && "$newest_process" != "$preexisting_proc" ]]; then
    if [[ "$newest_process" != *"winactivate"*"$1"* ]]; then
      log.success "Success: ${Cc}pgrep -fa $query${Cc0} returned:" -L
			proc.pprint "$newest_process"
      return 0
    fi
    log.warn "WEIRD: \$newest_process != \$preexisting_proc but includes 'winactivate'."
  fi
  return 1

}

# # launch <THING> [ARGS...]
# ## Usages
# ```bash
# launch EXEC_PATH [ARGS PASSED TO PROGRAM...]
# launch ALIAS
# launch FUNCTION NAME
# ```
# ## Description
# An "intelligent" wrapper to `(nohup EXEC [ARGS...] &) &>/dev/null`.
# Easy way to run 'standlone' programs from terminal.
#
# ## Examples
# ```bash
#   launch vlc
#   launch vlc /path/to/vid.mp4
# ```
function launch() {
  log.title "launch ${Cc}${*}" -x

  if [[ ! "$1" ]]; then
    log.fatal "$0: Not enough args (expected at least 1, got ${#$}). Usage:\n$(docstring "$0")"
    return 1
  fi

  declare -A program_launch_choices=(
    [pc]='Launch [n][q]uit'
    [pycharm]='Launch [n]ew [q]uit'
  )

  if [[ "$1" = sudo ]]; then
    [[ "$2" ]] || { log.fatal "Got only 'sudo', no program to launch. Aborting. Usage:\n$(docstring "$0")"; return 1; }
    sudo -V || return $?
    shift
  fi

  local processes
  processes="$(proc.pgrep "${1}")"
  if [[ "$processes" ]]; then
    log.debug "\nPre-existing matching processes:" -L
    proc.pprint "$processes"
  fi

  # *** handle possibly existing process
  if [[ "$processes" && "$processes" != *"winactivate"*"$1"* ]]; then
    # ** process exists; handle it
    local what_to_do choices_str
    if [[ "${program_launch_choices[$1]}" ]]; then
      choices_str="${program_launch_choices[$1]}"
    else
      choices_str='Launch [n]ew [f]ocus existing [q]uit'
    fi
    what_to_do="$(input "Some existing processes matched." --choices "$choices_str")"
    case "$what_to_do" in
    q) log.warn Aborting; return 3 ;;
    f) log.prompt "Trying to focus..."
    	 launch.focus_any "$processes" && return 0
    	 confirm "Failed to focus any process. Launch anyway?" && return 1 ;;
    n) log.prompt "Launching new..." ;; # after switch/case
    *) log.fatal "Fail: invalid user answer: '$what_to_do'. aborting"; return 1 ;;
    esac
  fi

  # *** [n]ew or [f]ocus failed and user wants to launch new

  # ** Normalize $1 (maybe)
  if ! isdefined "$1"; then
    # * if $1.lower() is a command, use its lowercase version
    local lowercase
    lowercase="$(lower "$1")"
    if isdefined "$lowercase"; then
      log.warn "${Cc}$1${Cc0} is NOT cmd but ${Cc}$lowercase${Cc0} IS a cmd; using ${Cc}$lowercase${Cc0}"
      set -- "$lowercase" "${@:2}"

    elif [[ -f "$1" ]]; then
      # * if $1 is a file, use its absolute path
      # because the same way you need ./file.sh and not file.sh to execute it
      log.info "Using absolute path of $1"
      set -- "$(realpath "$1")" "${@:2}"

    fi
  fi

  local last_proc
  if [[ "$processes" ]]; then
    # (f) split by newline
    last_proc=${${(f)processes}[-1]}
  fi

  # this is where `launch "vlc /media/D/shared-dir/whitenoise.opus"` fails, but `launch vlc /media/D/shared-dir/whitenoise.opus` succeeds:
  # if [[ "$2" ]]; then
  #   # ** nohup "$1" "${@:2}"

  #   log.debug "Trying ${Cc}nohup $1 ${*:2}"

  #   # nohup "$1" "${@:2}" &>/dev/null &
  #   # disown
  #   (nohup "$1" "${@:2}" &) &>/dev/null

  #   if launch.verify "$1" "${@:2}" --last-proc="$last_proc"; then
  #     return 0
  #   fi

  #   local warn_msg="Failed: ${Cc}nohup $1 ${*:2}"
  #   if [[ -f "$1" && ! -x "$1" ]]; then
  #     warn_msg+="${Cc0}. NO EXECUTION RIGHTS: $(stat -c %A "$1")"
  #   fi
  #   log.warn "$warn_msg"
  # fi

  # ** nohup "$@"
  log.debug "Trying ${Cc}nohup $*"
  # nohup "$@" &>/dev/null &
  # disown
  (nohup "$@" &) &>/dev/null

  launch.verify "$@" --last-proc="$last_proc" && return 0

  log.warn "Failed: ${Cc}nohup $*"
  confirm "Try to get alias or function?" || return 1
  # *** maybe it's an alias or function
  # ** try get alias
  log.debug "Trying to get ${Cc}alias_value $1${Cc0}..."
  local alias_content

  local alias_content_ok=false
  if alias_content="$(alias_value "$1")"; then
    # * found alias
    log.success "alias_content:\t${Cc}$alias_content"
    if [[ "$alias_content" == *"launch "* ]]; then
      log.warn '$alias_content has "launch" substring'
      # * alias content includes "launch", e.g. alias whatsapp='launch /path/to/file'
      if [[ "$alias_content" == "launch "* ]]; then
        # keep only '/path/to/file'
        alias_content="${alias_content:7}"
        log.success "Trimmed 'launch' from \$alias_content"
        alias_content_ok=true
      else
        # 'launch' in the middle of alias content
        # alias_content_ok=false at this point
        log.warn "Couldn't trim 'launch' from \$alias_content. Not using it to avoid recursion"
      fi
    else
      alias_content_ok=true
    fi
    if $alias_content_ok; then
      log.info "Running ${Cc}eval $alias_content ${*:2}${Cc0} then returning 0..."
      # eval "$alias_content" "${@:2}" &>/dev/null &
      # disown
      (eval "$alias_content" "${@:2}" &) &>/dev/null
      return 0 # no use to check for process because alias probably is different
    fi
  fi
  log.warn "${Cc}alias_value ${1}${Cc0} returned empty or invalid"

  # ** try get function
  log.debug "Checking whether it's a function in ${LAND}..."
  # todo: use helper from inspect.sh
  local file_of_function
  if file_of_function="$(fileof "function $1" "${LAND}")"; then
    log.success "Found function ${Cc}$1${Cc0} in '$file_of_function'. sourcing..."
    if ! source "$file_of_function"; then
      log.fatal "Failed sourcing $file_of_function, returning 1"
      return 1
    fi
    log.debug "Running ${Cc}nohup $1 ${*:2}${Cc0} then returning 0"
    # nohup "$1" "${@:2}" &>/dev/null &
    # disown
    (nohup "$1" "${@:2}" &) &>/dev/null
    return 0 # no use to check for process because function probably is different
  fi
  log.fatal 'Fail: did not find function. returning 1'
  return 1

}


complete -o default -A command launch
