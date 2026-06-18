#!/usr/bin/env bash
# sourced towards the end, after history.sh and before launch.sh

: "${THIS_SCRIPT_DIR:=$(dirname -- "$0")}"

if [[ "$PLATFORM" == WIN ]]; then
  :
elif [[ "$OS" == Linux ]]; then
  source "$THIS_SCRIPT_DIR/proc.linux.sh"
else
  source "$THIS_SCRIPT_DIR/proc.mac.sh"
fi

# # killverify [-s SIGNAL_NAME_OR_NUMBER=TERM] [-m,--max-attempts MAX_ATTEMPTS=10] PID_OR_PATTERN ...
# # killverify [-SIGNAL_NAME_OR_NUMBER=TERM] [-m,--max-attempts MAX_ATTEMPTS=10] PID_OR_PATTERN ...
killverify() {
  local signal="TERM"
  local -i max_attempts=10
  local -a targets=()

  _killverify_parse_args "$@" || return 1

  # Validate we have at least one target
  if [[ ${#targets[@]} -eq 0 ]]; then
    log.error "${0}: no targets specified"
    return 1
  fi

  # Process each target
  local -i overall_success=0
  local target
  for target in "${targets[@]}"; do
    if [[ "$target" =~ ^[0-9]+$ ]]; then
      _killverify_pid "$target" "$signal" "$max_attempts" || overall_success=1
    else
      _killverify_pattern "$target" "$signal" "$max_attempts" || overall_success=1
    fi
  done

  return $overall_success
}

# # _killverify_parse_args ARG ...
# Parses killverify's argv, populating the caller's `signal`, `max_attempts` and `targets` (dynamic scope).
_killverify_parse_args() {
  # Parse arguments using while-case for flexible ordering
  while [[ $# -gt 0 ]]; do
    case "$1" in
    -s)
      # -s signal_name format
      shift
      if [[ $# -eq 0 ]]; then
        log.error "killverify: option requires an argument -- s"
        return 1
      fi
      signal="$1"
      ;;
    -m=* | --max-attempts=*)
      max_attempts="${1#*=}"
      ;;
    -m | --max-attempts)
      # -m or --max-attempts format
      shift
      if [[ $# -eq 0 ]]; then
        log.error "killverify: option requires an argument -- ${1}"
        return 1
      fi
      max_attempts="$1"
      ;;
    -[0-9]*)
      # -signal_number format (e.g., -9, -15)
      signal="${1#-}"
      ;;
    -*)
      # -signal_name format (e.g., -TERM, -KILL)
      signal="${1#-}"
      ;;
    *)
      # It's a pid or pattern
      targets+=("$1")
      ;;
    esac
    shift
  done
}

# # _killverify_pid PID SIGNAL MAX_ATTEMPTS
# Signals a single PID, escalating to SIGKILL after 3 attempts. Returns non-zero if still running.
_killverify_pid() {
  local target="$1"
  local current_signal="$2"
  local -i max_attempts="$3"
  local -i attempt=0

  while _killverify_pid_alive "$target" && ((attempt++ < max_attempts)); do
    log.debug "Attempt ${attempt}/${max_attempts}: ${current_signal}'ing PID $target"
    kill -"${current_signal}" "$target" 2>/dev/null
    sleep 0.5

    # Escalate to KILL after 3 failed attempts
    if ((attempt >= 3)) && [[ $current_signal != "KILL" ]] && [[ $current_signal != "9" ]]; then
      current_signal=KILL
      log.notice "Escalating to SIGKILL for '$target'"
    fi
  done

  if _killverify_pid_alive "$target"; then
    log.warn "Warning: PID $target still running"
    return 1
  fi
  log.success "PID $target terminated"
}

# # _killverify_pid_alive PID
_killverify_pid_alive() { kill -0 "$1" 2>/dev/null; }

# # _killverify_pattern PATTERN SIGNAL MAX_ATTEMPTS
# Signals processes matching a pattern, escalating to SIGKILL after 3 attempts. Returns non-zero if any remain.
_killverify_pattern() {
  local target="$1"
  local current_signal="$2"
  local -i max_attempts="$3"
  local -i attempt=0
  local attempt_successful=false

  while _killverify_pattern_matches "$target" && ((attempt++ < max_attempts)); do
    log.debug "Attempt ${attempt}/${max_attempts}: ${current_signal}'ing processes matching '$target'"
    pkill -"${current_signal}" -ao "$target" && break
    sleep 0.5

    # Escalate to KILL after 3 failed attempts
    if ((attempt >= 3)) && [[ $current_signal != "KILL" ]] && [[ $current_signal != "9" ]]; then
      log.notice "Escalating to SIGKILL for '$target' after 3 failed ${current_signal} attempts."
      current_signal=KILL
    fi
  done

  if _killverify_pattern_matches "$target"; then
    log.warn "Warning: Some processes matching '$target' still running"
    return 1
  fi
  log.success "All processes matching '$target' terminated"
}

# # _killverify_pattern_matches PATTERN
_killverify_pattern_matches() { [[ -n "$(pgrep -fao "$1")" ]]; }

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

#compdef _pgrep proc.{kill,pgrep,pprint,killgrep,kill_bg_jobs}
