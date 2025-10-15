#!/usr/bin/env bash
# sourced towards the end, after history.sh and before launch.sh

if [[ "$PLATFORM" == WIN ]]; then
  :
elif [[ "$OS" == Linux ]]; then
  source proc.linux.sh
else
  source proc.mac.sh
fi

source "/Users/gilad/dev/bashscripts/environment.sh"  # 30ms
source "/Users/gilad/dev/bashscripts/log.sh"          # 14ms
source "/Users/gilad/dev/bashscripts/util.sh"         # 14ms
source "/Users/gilad/dev/bashscripts/str.sh"

# # proc.kill <PID_OR_QUERY> [OPTIONS]
# ### Options
# `--verify` will check at most 10 times, 100ms apart, if the processes are still running.
# `--aggressive` will try to kill the processes again each verification interval.
# `-l, --loops LOOPS` sets the number of times to check if the processes are still running, default 10.
# `-v` for some log.debug output.
# ### proc.kill <PID...> [--verify, --verify=QUERY [--aggressive]] [-SIG] [-i] [-l, --loops LOOPS]
# PID(s) can be numbers, or a full process lines, in which case non-numbers are filtered-out.
# In `--verify=QUERY` form, verification is done with `pgrep -fa [-i] QUERY`, not `ps -p PID`.
# ### proc.kill <QUERY> [--verify [--aggressive]] [-SIG] [-i] [-l, --loops LOOPS]
# Kill all pids that `pgrep -fa [-i] QUERY` returns.
function proc.kill() {
  function kill_quietly() {
    local _signal
    local _pids=()
    local _exitcode
    while [[ $# -gt 0 ]]; do
      case "$1" in
      -[[:digit:]]* | -[[:upper:]]*) _signal="$1" ;;
      *) _pids+=("$1") ;;
      esac
      shift
    done
    kill "$_signal" "${_pids[@]}" 2>/tmp/"${0}.stderr"
    _exitcode=$?
    if [[ "$_exitcode" != 0 ]]; then
      log.warn "$0 exited: ${_exitcode} with error: $(</tmp/"${0}.stderr")"
    fi
    return $_exitcode
  }
  log.title "\$*: $*"
  local pids=()
  local pgrep_args=(-fa)
  local verify=false
  local aggressive=false
  local signal query
  local loops=10
  local verbose=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --verify=*)
      query="${1#*=}" # Don't modify pids here, because query will only be used to verify
      verify=true
      ;;
    --verify) verify=true ;;
    --aggressive) aggressive=true ;;
    -l | --loops*)
      if [[ "$1" = *=* ]]; then
        loops=${1#*=}
      else
        loops="$2"
        shift
      fi
      ;;
    -i) pgrep_args+=(-i) ;;
    -v) verbose=true ;;
    -[[:digit:]]* | -[[:upper:]]*)
      if [[ "$signal" ]]; then
        log.warn "signal already set to $signal; ignoring given '$1'"
      else
        signal="$1"
      fi
      ;;
    [[:digit:]]*) pids+=("$1") ;;
    *) # Alphabetical, or 1 line of process info
      if [[ "$1" = *" "* ]]; then
        # Full process line, e.g '542 /Applications/App.app --foo --bar' -> '542'
        pids+=("${1%% *}")
      else
        if [[ "$query" ]]; then
          log.fatal "$0 $(inspect.signature "$0"): only one query allowed, already got '$query'"
          return 1
        fi
        if [[ "${#pids[@]}" -gt 0 ]]; then
          log.fatal "$0 $(inspect.signature "$0"): positional arguments can be either query or pids, not both"
          return 1
        fi
        query="$1"
        # shellcheck disable=SC2207
        pids=($(pgrep "${pgrep_args[@]}" "$query"))
      fi ;;
    esac
    shift
  done
  $verbose && log.debug "query: ${query} | loops: ${loops} | pgrep_args=(${pgrep_args[*]})"
  [[ ! "${pids}" ]] && {
    log.error "No pids given or matched"
    return 1
  }
  [[ ! "$signal" ]] && signal="-SIGKILL"
  $verbose && log.debug "signal: ${signal} | pids=(${pids[*]})"
  ps -p "${pids// /,}" &>/dev/null 2>&1 || log.warn "No processes existed even before killing, for pids=(${pids[*]})"
  local exitcode
  kill_quietly "$signal" "${pids[@]}"
  exitcode=$?
  ! "$verify" && return "$exitcode"
  local pid
  local unkilled_pids=()
  local pgrep_matches=()
  local i=0
  for ((i = 0; i < loops; i++)); do
    sleep 0.1
    unkilled_pids=()
    for pid in "${pids[@]}"; do
      if ps -p "$pid" &>/dev/null 2>&1; then
        unkilled_pids+=("$pid")
      fi
    done
    if [[ "$query" ]]; then
      # shellcheck disable=SC2207
      pgrep_matches=($(pgrep "${pgrep_args[@]}" "$query"))
      if [[ ! "${pgrep_matches}" ]]; then
        local success_message="No processes matching '$query' found"
        if [[ "${unkilled_pids}" ]]; then
          success_message+=", although some pids are still alive: ${unkilled_pids[*]}"
        else
          success_message+=", and no pids remain alive either"
        fi
        log.success "$success_message"
        return 0
      fi
      $verbose && log.debug "unkilled_pids=(${unkilled_pids[*]}) | pgrep_matches=(${pgrep_matches[*]})"
    else
      [[ ! "${unkilled_pids}" ]] && {
        log.success "Killed all pids"
        return 0
      }
      $verbose && log.debug "unkilled_pids=(${unkilled_pids[*]})"
    fi
    "$aggressive" && kill_quietly "$signal" "${pids[@]}"
  done
  log.fatal "Failed to kill some processes. unkilled_pids=(${unkilled_pids[*]}); pgrep_matches=(${pgrep_matches[*]})"
  local -i unkilled_pids_count="${#unkilled_pids[@]}"
  local -i pgrep_matches_count="${#pgrep_matches[@]}"
  return $((unkilled_pids_count + pgrep_matches_count))

}

# # proc.pgrep [OPTION...] <PATTERN_OR_PID>
# A `pgrep "full" "long"` wrap for compatibility with MacOS and Linux.
# `OPTION` is passed to `pgrep`, unless we've given a number and this is a MacOS,
# in which case it's passed to `ps`.
# ## Examples:
# ```bash
# proc.pgrep "foo"
# proc.pgrep ".*foo" -i
# proc.pgrep 24856
# ```
function proc.pgrep() {
  # todo: split to .macos and .linux
  local query
  local extra_args=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
    -*) extra_args+=("$1") ;;
    *) [[ "$query" ]] && extra_args+=("$1") || query="$1" ;;
    esac
    shift
  done

  log.debug "query: $query | extra_args: ${extra_args[*]}"

  # don't quote $case var, don't escape quotes from $query
  if isnum "$query"; then
    log.debug "Detected number"
    if [[ "$OS" = macos ]]; then
      ps -p "$query" -o 'pid command' "${extra_args[@]}" | tail +2
      return $?
    fi
    # In Linux, s for session; otherwise 'f' doesnt match pid
    pgrep -as "${extra_args[@]}" "$query"
    return $?
  fi
  # string
  local pgrep_args=(-fa "${extra_args[@]}")
  [[ "$OS" = macos ]] && pgrep_args+=(-l)
  local exit_code
  vex pgrep "${pgrep_args[@]}" "$query" || {
    exit_code=$?

    [[ "${extra_args[*]}" = *i* ]] && return $exit_code

    # try again with -i
    pgrep_args+=(-i)
    vex pgrep "${pgrep_args[@]}" "$query"
    return $?
  }
  return $?
}

# # proc.pprint <FULL_PROCESS / STDIN>
function proc.pprint() {
  local full_process
  if [[ "$1" ]]; then
    full_process="$1"
  else
    is_piped || {
      log.error "$0: no input"
      return 1
    }
    full_process="$(<&0)"
  fi
  py.print \
    -s 'executables = map(lambda full_process: full_process.split(" ", 2), lines)' \
    'newline.join(f"\x1b[1m{pid}\x1b[0m {exec} \x1b[2m{args}\x1b[0m" for pid,exec,args in executables)' \
    --readlines 2>/dev/null <<<"$full_process" || # Sometimes a line is just e.g '1234 kitty', so ValueError when splitting to pid,exec,args.
    py.print \
      -s 'executables = map(lambda full_process: full_process.split(" ", 1), lines)' \
      'newline.join(f"\x1b[1m{pid}\x1b[0m {exec}" for pid,exec in executables)' \
      --readlines 2>/dev/null <<<"$full_process"
  printf "\n"
}

# # proc.killgrep <EX_REGEX> [-i | --ignore-case] [--wildcards]
# ## Description
# Tries to kill all processes matching EX_REGEX. Suggests adding wildcards or ignoring case if nothing matched.
# Verifies all matches actually died.
# ## Examples
# ```bash
# proc.killgrep 'jupyter'
# proc.killgrep '.*jupyter.*' -i
# ```
function proc.killgrep() {
  if [[ -z "$1" ]]; then
    log.fatal "$0 Expecting at least 1 arg"
    return 1
  fi
  local case_sensitive_flag
  local fullnames
  local do_wildcards=false
  local has_wildcards=false
  local query
  local user_answer
  log.title "proc.killgrep(${*})"

  while [[ $# -gt 0 ]]; do
    case "$1" in
    -i | --ignore-case)
      case_sensitive_flag="-i"
      ;;
    --wildcards)
      do_wildcards=true
      ;;
    -*)
      log.warn "Unknown option: $1. Ignoring."
      ;;
    *)
      query="$1"
      str.has_wildcard_at_ends "$query" && has_wildcards=true
      ;;
    esac
    shift
  done

  fullnames="$(vex proc.pgrep "$case_sensitive_flag" "'$query'")"
  [[ ! "$fullnames" ]] && { # ** nothing found; prompt to modify query or exit
    if [[ "$case_sensitive_flag" ]] && "$has_wildcards"; then
      # * both --ignore-case and .* already
      log.fatal "Nothing found; already has wildcards and tried case insensitively. aborting"
      return 1
    fi
    if [[ "$case_sensitive_flag" ]]; then
      # * only --ignore-case, not .*
      if confirm "proc.pgrep $case_sensitive_flag '$query' yielded nothing; surround with '.*'?"; then
        proc.killgrep ".*$query.*" --ignore-case
        return $?
      else
        log.warn Aborting
        return 3
      fi
    fi
    if "$has_wildcards"; then
      # * only .*, not --ignore-case
      if confirm "proc.pgrep $case_sensitive_flag '$query' yielded nothing; try with --ignore-case?"; then
        proc.killgrep "$query" --ignore-case
        return $?
      else
        log.warn Aborting
        return 3
      fi
    fi
    # * not .* and not --ignore-case
    user_answer="$(input 'No processes matched query; what to do?' --choices '[i]gnore case, [w]ildcard surround, [b]oth, [q]uit')"
    case "$user_answer" in
    q)
      log.warn Aborting
      return 3
      ;;
    i)
      # log.info "calling 'proc.killgrep' with \"$query\" --ignore-case..."
      proc.killgrep "$query" --ignore-case
      return $?
      ;;
    w)
      # log.info "calling 'proc.killgrep' with \".*$query.*\"..."
      proc.killgrep ".*$query.*"
      return $?
      ;;
    b)
      # log.info "calling 'proc.killgrep' with \".*$query.*\" --ignore-case..."
      proc.killgrep ".*$query.*" --ignore-case
      return $?
      ;;
    esac
  }

  # ** $fullnames is not empty
  log.prompt "Found these processes:"
  proc.pprint "$fullnames"

  [[ "$(str.count "$fullnames" $'\n')" = 1 ]] && { # * only one process found
    confirm "Kill process ${fullnames}?" || {
      log.warn Aborting
      return 3
    }
    proc.kill "$fullnames" --verify --aggressive || {
      log.fatal Failed killing process
      return 3
    }
    return 0
  }

  # ** try to kill common process pid
  local common_process_pid
  common_process_pid=$(
    echo "$fullnames" | py.print \
      -s 'executables = map(lambda full_process: full_process.split(" ", 1), lines)' \
      'next(pid for pid, exec_with_args in executables if all(exec_with_args in exec_with_args for pid, exec_with_args in executables))' \
      --readlines 2>/dev/null
    # E.g given 2 processes: '1234 chrome -v' and '5678 chrome -v --flag', common pid -> '1234'
  ) && {
    # ** found common process pid
    log.success "The following pid's exec and args are included in all other full process names: ${Cc}$common_process_pid" -L -x
    local oldest_pid
    oldest_pid="$(pgrep -of $case_sensitive_flag "$query")"
    local pid_to_kill
    if [[ "$common_process_pid" == "$oldest_pid" ]]; then
      if confirm "Common pid is also the oldest ($oldest_pid), probably the root. Kill that one and check if all others died?"; then
        pid_to_kill="$oldest_pid"
      fi
    else
      user_answer="$(input "Common process pid ($common_process_pid) != oldest pid ($oldest_pid); Which to kill?" --choices="[c]ommon process pid, [o]ldest pid ($oldest_pid), [b]oth, [a]ll processes")"
      case "$user_answer" in
      c) pid_to_kill="$common_process_pid" ;;
      o) pid_to_kill="$oldest_pid" ;;
      b) pid_to_kill="$common_process_pid $oldest_pid" ;;
      a) : ;;
      esac
    fi
    if [[ "$pid_to_kill" ]]; then
      # todo: pass case sensitiveness. also below in 'local proc_kill_args'
      proc.kill "$pid_to_kill" --verify="$query" && return 0
      fullnames="$(proc.pgrep $case_sensitive_flag "$query")"
      log.warn "Still got running processes:" -L -x
      proc.pprint "$fullnames"
    fi
    log.info "Doing regular kill loop"
  }

  # *** full loop (all processes)
  local proc_kill_args=(--verify="$query" --aggressive)
  [[ "$case_sensitive_flag" ]] && proc_kill_args+=(-i)
  if [[ "$(str.count "$fullnames" $'\n')" = 1 ]]; then
    confirm "Kill process ${fullnames}?" || {
      log.warn Aborting
      return 3
    }
    proc_kill_args+=("$fullnames")
  else
    user_answer="$(input "What to do with them?" --choices 'kill [a]ll, [s]elect individually, [q]uit')"
    case "$user_answer" in
    q)
      log.warn Aborting
      return 3
      ;;
    s) proc_kill_args+=($(input "Enter pids to kill, separated by spaces:")) ;;
    a)
      log.prompt "Killing all of them..."
      proc_kill_args+=("$fullnames")
      ;;
    esac
  fi
  proc.kill "${proc_kill_args[@]}"
  return $?

}

# # proc.kill_bg_jobs [xargs options...]
function proc.kill_bg_jobs() {
  jobs -l | command grep -Po '\d{3,6}' | xargs kill "$@"
}

#compdef _pgrep proc.{kill,pgrep,pprint,killgrep,kill_bg_jobs}