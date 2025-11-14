#!/usr/bin/env bash
# sourced towards the end, after history.sh and before launch.sh

if [[ "$PLATFORM" == WIN ]]; then
  :
elif [[ "$OS" == Linux ]]; then
  source proc.linux.sh
else
  source proc.mac.sh
fi

# # killverify [-s SIGNAL_NAME_OR_NUMBER=TERM] [-m,--max-attempts MAX_ATTEMPTS=10] PID_OR_PATTERN ...
# # killverify [-SIGNAL_NAME_OR_NUMBER=TERM] [-m,--max-attempts MAX_ATTEMPTS=10] PID_OR_PATTERN ...
killverify() {
  local signal="TERM"
  local -i max_attempts=10
  local -a targets=()
  
  # Parse arguments using while-case for flexible ordering
  while [[ $# -gt 0 ]]; do
    case "$1" in
      (-s)
        # -s signal_name format
        shift
        if [[ $# -eq 0 ]]; then
          log.error "killverify: option requires an argument -- s"
          return 1
        fi
        signal="$1"
        ;;
      (-m=*|--max-attempts=*)
        max_attempts="${1#*=}"
        ;;
      (-m|--max-attempts)
        # -m or --max-attempts format
        shift
        if [[ $# -eq 0 ]]; then
          log.error "killverify: option requires an argument -- ${1}"
          return 1
        fi
        max_attempts="$1"
        ;;
      (-[0-9]*)
        # -signal_number format (e.g., -9, -15)
        signal="${1#-}"
        ;;
      (-*)
        # -signal_name format (e.g., -TERM, -KILL)
        signal="${1#-}"
        ;;
      (*)
        # It's a pid or pattern
        targets+=("$1")
        ;;
    esac
    shift
  done
  
  # Validate we have at least one target
  if [[ ${#targets[@]} -eq 0 ]]; then
    log.error "killverify: no targets specified"
    return 1
  fi
  
  # Process each target
  local -i overall_success=0
  for target in "${targets[@]}"; do
    local -i attempt=0
    local current_signal="$signal"
    
    # Check if target is a number (PID) or a pattern
    if [[ "$target" =~ ^[0-9]+$ ]]; then
      # It's a PID
      while kill -0 "$target" 2>/dev/null && (( attempt++ < max_attempts )); do
        log.debug "Attempt ${attempt}/${max_attempts}: ${current_signal}'ing PID $target"
        kill -"${current_signal}" "$target" 2>/dev/null
        sleep 0.2
        
        # Escalate to KILL after 3 failed attempts
        if (( attempt >= 3 )) && [[ $current_signal != "KILL" ]] && [[ $current_signal != "9" ]]; then
          current_signal=KILL
          log.notice "Escalating to SIGKILL for PID $target"
        fi
      done
      
      if kill -0 "$target" 2>/dev/null; then
        log.warn "Warning: PID $target still running"
        overall_success=1
      else
        log.success "PID $target terminated"
      fi
    else
      # It's a pattern
      while pgrep -q "$target" && (( attempt++ < max_attempts )); do
        log.debug "Attempt ${attempt}/${max_attempts}: ${current_signal}'ing processes matching '$target'"
        pkill -"${current_signal}" "$target"
        sleep 0.2
        
        # Escalate to KILL after 3 failed attempts
        if (( attempt >= 3 )) && [[ $current_signal != "KILL" ]] && [[ $current_signal != "9" ]]; then
          current_signal=KILL
          log.notice "Escalating to SIGKILL for pattern '$target'"
        fi
      done
      
      if pgrep -q "$target"; then
        log.warn "Warning: Some processes matching '$target' still running"
        overall_success=1
      else
        log.success "All processes matching '$target' terminated"
      fi
    fi
  done
  
  return $overall_success
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