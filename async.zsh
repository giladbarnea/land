function repl() {
  while true; do
    statement="$(input)"
    case "$statement" in
    break | cont* | q | quit | exit) break ;;
    *) eval "$statement" ;;
    esac
  done
}

# # spinner <PID>
function spinner() {
  local pid=$1
  shift || {
    log.error "$0: Not enough positional args (expected at least 1). Usage:\n$(docstring -p "$0")"
    return 2
  }
  local refresh_rate_sec=0.1
  # shellcheck disable=SC1003  # Single-quote escape
  local spinstr='|/-\'
  local start_time="$(date +%s.%N)"
  while ps aux | awk '{print $2}' | command grep -q "$pid"; do
    local temp=${spinstr#?}
    local elapsed_time=$(bc <<<"$(date +%s.%N) - $start_time")
    local elapsed_seconds=$(printf "%.0f" "$elapsed_time")
    printf "\r${Ci}[%c] %02d:%02d  Waiting for %s to finish...${C0}" \
      "$spinstr" \
      $((elapsed_seconds / 60)) \
      $((elapsed_seconds % 60)) \
      "$pid"
    local spinstr=$temp${spinstr%"$temp"}
    sleep $refresh_rate_sec
  done
  printf "\r    \r"
  printf "\r[${Cgrn}✓${C0}] %s                                \n" "$pid"
}

# # background COMMAND...
# Runs the command in the background of a subshell.
# TODO: llm.agents does this differently and awesomely.
function background() {
  ($SHELL -ic "__(){ ${*} ; }; exec __" &)
}

# # realasync <PROGRAM...> -- --notify
# Launches a program in an independent process (nohup), quietly (1>/dev/null 2>&1).
# Examples:
# ```bash
# realasync "sleep 1 ; notif.info hi"
# realasync notif.generic hi -t title
# ```
function realasync() {
  # Should be able to handle all of the following:
  # $ realasync afplay /System/Library/Sounds/Ping.aiff
  # $ realasync 'afplay /System/Library/Sounds/Ping.aiff'
  # $ realasync 'sleep 1 && afplay /System/Library/Sounds/Ping.aiff'
  # $ realasync one_command
  local -a args
  local seen_double_dash=false
  local notify=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --) seen_double_dash=true ;;
    --notify)
      if [[ "$seen_double_dash" = true ]]; then
        notify=true
      else
        args+=("${1}")
      fi
      ;;
    *) args+=("${1}") ;;
    esac
    shift
  done
  local program="function __fn() { builtin cd \"${PWD}\" || true; ${args[*]} ; };"
  # Note: we source ~/.zshrc instead of -i because -i messes up piping to less.
  if [[ "$notify" = true ]]; then
    (nohup "$SHELL" -c "
    source ~/.zshrc;
    notif.generic \"Running ${args[1]} in background...\" -t \"🔄\"
    ${program}
    if exec __fn; then 
      notif.success \"${args[1]} completed successfully\"
    else
      notif.error \"${args[1]} failed\"
    fi" 1>/dev/null 2>&1 &)
  else
    (nohup "$SHELL" -c "source ~/.zshrc; ${program} exec __fn" 1>/dev/null 2>&1 &)
  fi
}

declare -A _ASYNC_JOBS

# # awaitable <COMMAND...> ---spinner
# awaitable awaitable $SHELL -c 'echo "hello world"'
# For some reason `jid="$(awaitable sleep 5)"` is blocking.
function awaitable() {
  local -a args
  local use_spinner=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
    ---spinner) use_spinner=true ;;
    *) args+=("$1") ;;
    esac
    shift
  done
  local -i job_id

  "${args[@]}" &
  disown # disown prevents automatic '[1] 17569' output when process is done.
  job_id=$!
  _ASYNC_JOBS[$job_id]=RUNNING
  printf "%d" $job_id # This is currently useless because jid="$(awaitable sleep 5)" is blocking for some reason. mkfifo?

  [[ "$use_spinner" = true ]] && spinner $job_id
  true
}

function await() {
  local -i job_id="$1"
  local result

  while ps -x -p $job_id 1>/dev/null 2>&1; do :; done
}
# # onmodified <FILE_TO_WATCH> <-c, --command CMD | -s, --script PATH> [-i, --interval INTERVAL]
# `CMD` replaces literal '{}' with `FILE_TO_WATCH`.
# `onmodified ~/sxhkd.cfg -c "pkill --signal SIGTERM sxhkd; nohup sxhkd -c {} &>/dev/null &"`
function onmodified() {
  local file="$1"
  shift
  local command script
  local interval=4
  local positional=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
    -i | --interval)
      interval="$2"
      shift 2
      ;;
    -c | --command)
      command="$2"
      shift 2
      ;;
    -s | --script)
      script="$2"
      shift 2
      ;;
    *)
      positional+=("$1")
      shift
      ;;
    esac
  done
  if [[ -n "$script" && -n "$command" ]]; then
    log.fatal "Cannot have both script and command. Mutually exlusive."
    return 1
  fi

  if [[ -z "$script" && -z "$command" ]]; then
    log.fatal "Must have either script or command, both missing"
    return 1
  fi
  set -- "${positional[@]}"
  local last_modified_a="$(stat -c %Y "$file")"
  local last_modified_b
  local last_applied=-1
  local command="${command//"{}"/"$file"}"
  log.debug "command: ${Cc}${command}${Cc0}\n\tfile: ${file} | last_modified_a: ${last_modified_a} | interval: ${interval}"
  while true; do
    last_modified_b="$(stat -c %Y "$file")"
    if [[ "$last_modified_b" -gt "$last_modified_a" && "$last_modified_b" -gt "$last_applied" ]]; then
      # (nohup eval "$command" &) &>/dev/null
      #  vex "$command"
      eval "$command"
      last_applied="$(date "+%s")"
      echo "Applied command: $(date "+%X")"
    fi
    sleep "$interval"
  done
}

#complete -o bashdefault -o default -o nospace \
#         -C 'completion.generate <STATEMENT> -e "ls | map cat \$line"' \
#         map

# # after <pgrep -fl args OR process id> <COMMAND...>
# Examples:
# ```bash
# after scp notify-send done
# after 5432 'pip install numpy'
# ```
function after() {
  if [[ ! "$2" ]]; then
    log.fatal "$0: Not enough args (expected 2, got ${#$}. Usage: $0 <PGREP_FULL_ARG> <COMMAND...>)"
    return 1
  fi
  local first_positional_arg="$1"
  if [[ "$first_positional_arg" =~ ^[-\+]?[0-9]+$ ]]; then
    local proc_num="$first_positional_arg"
    shift
    log.debug "proc_num: ${proc_num} | command: ${*}"
    function _get_process() {
      ps "$proc_num" | awk 'FNR >= 2'
    }
  else
    local proc_grep="$first_positional_arg"
    shift
    log.debug "proc_grep: ${proc_grep} | command: ${*}"
    local pgrep_args=(-f)
    if [[ "$(uname)" == Darwin ]]; then
      # MacOS
      pgrep_args+=(-l)
    else
      # Linux
      pgrep_args+=(-a)
    fi
    function _get_process() {
      pgrep "${pgrep_args[@]}" "$proc_grep"
    }
  fi

  if ! _get_process; then
    confirm "Process ${Cc}${first_positional_arg}${Cc0} not running. Just run ${Cc}$*${Cc0}?" || return 0
    "$@"
    return $?
  fi

  while _get_process &>/dev/null; do
    vsleep 10
  done

  log.title "Process ${Cc}${first_positional_arg}${Cc0} finished. Running ${Cc}$*${Cc0}"
  vex ---log-before-running "$@"
  return $?
}

# # whiletrue <CMD> [-i, --interval INTERVAL_SECONDS] [-n, --no-exit-on-error]
function whiletrue() {
  local sleep_interval no_exit_on_error exitcode
  zparseopts -D -E - i:=sleep_interval -interval:=sleep_interval n=no_exit_on_error -no-exit-on-error=no_exit_on_error
  sleep_interval="${sleep_interval[2]:-1}"
  log.debug "sleep_interval: ${sleep_interval} | no_exit_on_error: ${no_exit_on_error}"
  while true; do
    vex "$@" ---just-run
    exitcode=$?
    if [[ "$exitcode" != 0 && ! "$no_exit_on_error" ]]; then
      log.fatal "Command ${Cc}$*${Cc0} exited with code ${Cc}${exitcode}${Cc0}."
      return $exitcode
    fi
    sleep "$sleep_interval"
  done
}

# # vsleep <sleep args...>
# Verbose sleep.
function vsleep() {
  vex sleep "$@"
}

# # onidle <COMMAND> [-s, --seconds SECONDS (default 10)]
# Examples:
# ```bash
# onidle 'black .'
# onidle 'say "get to work"' -s 10
# ```
function onidle() {
  local cmd="$1"
  shift 1 || {
    log.error "$0: Not enough positional args (expected 1, got ${#$}). Usage:\n$(docstring "$0")"
    return 2
  }
  local iteration=1
  local idletime_seconds
  zparseopts -D -E - s:=idletime_seconds -seconds:=idletime_seconds
  idletime_seconds="${idletime_seconds[2]:-10}"
  log.debug "Running ${Cc}${cmd}${Cc0} when idle every ${idletime_seconds} seconds."
  local current_idletime previous_idletime
  while true; do
    current_idletime="$(idletime)"
    [[ "$previous_idletime" && "$current_idletime" -lt "$previous_idletime" ]] && {
      log.debug "User activity detected. Resetting timer."
      iteration=1
    }
    previous_idletime="$current_idletime"
    if [[ $current_idletime -gt $((idletime_seconds * iteration)) ]]; then
      vex "$cmd"
      ((iteration++))
      sleep 1
    fi
  done
}

# # xargsparallel <COMMAND...>
# Automatically sets -P to the number of lines in stdin.
# Runs `xargs -P "$line_count" -I{} "$@" <<<"$stdin"`.
# Examples:
# ```bash
# head -5 pdfs.txt | xargsparallel zsh -ic 'pdf2md {}'
# ```
function xargsparallel() {
  # Read stdin into a variable
  local stdin
  stdin="$(<&0)"
  [[ -z "$stdin" ]] && {
    log.error "$0: No input"
    return 1
  }

  # Count the number of lines
  local -i line_count
  line_count=$(wc -l <<<"$stdin")
  log.debug "$(typeset line_count)"
  [[ "$line_count" = 0 ]] && {
    log.error "$0: No lines in input. Stdin: ${stdin}"
    return 1
  }
  if [[ "$line_count" == 1 ]]; then
    local -i word_count
    word_count=$(wc -w <<<"$stdin")
    if [[ "$word_count" = 0 ]]; then
      log.error "$0: No words in input. Stdin: ${stdin}"
      return 1
    fi
    if [[ "$word_count" = 1 ]]; then
      log.error "Input is a single line containing a single word. Just run ${Cc}$*${Cc0}."
      return 1
    fi
    confirm "Input is a single line containing multiple words. Run ${Cc}$*${Cc0} on each word? ${(j.\n.)${(s. .)stdin}}" || return 1
    xargs -n1 -I{} -P "$line_count" "$@" <<<${(j.\n.)${(s. .)stdin}}
  fi

  # Pass the input to xargs with -P set to the line count
  # printf '%s\0' "${pdfs[@]}" | xargs -0 -n1 -P3 -I{} zsh -ic 'log.title "$1"; pdf2md "$1"; log.title "finished $1"' _ {}
  xargs -n1 -I{} -P "$line_count" "$@" <<<"$stdin"
}

# # xargseach <COMMAND...>
# Convenience wrapper around `xargs -n1 -I{} COMMAND...`.
# Examples:
# ```bash
# xargseach yq 'query' {} <<< "a.yaml b.yaml c.yaml"
# ```
function xargseach() {
  # Preserves env and namespace:
  # printf '%s\0' "${pdfs[@]}" | xargs -0 -n1 -I{} zsh -ic 'log.title "$1"; pdf2md "$1"; log.title "finished $1"' _ {}
  xargs -n1 -I{} zsh -c 'exec "$@"' _ "$@" {}
}

# # wget.bg <OUTPATH> <URL>
function wget.bg() {
  local _url="$1"
  local _outpath="$2"
  if ! shift 2; then
    echo "[FATAL] wget.bg | Not enough args (expected 2, got ${#$})" 1>&2
    return 1
  fi
  # log.debug "_url: ${_url} | _outpath: ${_outpath}"
  local wget_args=(
    --quiet
    --background
    # --tries=1
    # --timeout='0.5'
    --no-check-certificate
    # --max-redirect=1
    # --timestamping --no-if-modified-since
    "$@"
  )

  local pid exitcode
  # Continuing in background, pid 270508.
  wget "${wget_args[@]}" -o /dev/null -O "$_outpath" "$_url" 2>&1
  # pid="$(wget "${wget_args[@]}" -o /dev/null -O "$_outpath" "$_url" 2>&1 | grep -Po '\d+')"
  # if $(ps -fp $pid); then
  # # lst2 /proc/$pid
  #   cat /proc/$pid/fdinfo/1
  # fi
  # wait $pid
  # return $?
  return 0

  #  log.debug "pid: ${pid}"
  #  return $?
}

# # wait_until_exists <PATH> [-t, --timeout TIMEOUT_SEC=0.5] [-i, --interval INTERVAL_SEC=0.005] [-v, --verbose]
function wait_until_exists() {
  # Todo: this is cool (use in e.g pip.sh)
  # terminal 1:
  # for script in $(/bin/ls $SCRIPTS/*.sh | xargs -n1 basename); do
  #   background fetchfile https://raw.githubusercontent.com/giladbarnea/bashscripts/master/$script
  # done
  # terminal 2:
  # for script in $(/bin/ls $SCRIPTS/*.sh | xargs -n1 basename); do
  #   wait_until_exists $script -t 30 && source $script
  # done
  local start_ts="$(unixtime)"
  local path="$1"
  local timeout=0.5
  local sleep_interval=0.005
  shift || return 1
  local verbose=false
  local positional=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
    -v | --verbose) verbose=true ;;
    -t | --timeout)
      timeout="$2"
      shift
      ;;
    -i | --interval)
      sleep_interval="$2"
      shift
      ;;
    *) positional+=("$1") ;;
    esac
    shift
  done
  set -- "${positional[@]}"
  if $verbose; then
    function _echo() { echo "[DEBUG][wait_until_exists($path)] | $*" 1>&2; }
  else
    function _echo() { :; }
  fi
  local now elapsed
  while true; do
    if [[ -e "$path" ]]; then
      if [[ -s "$path" ]]; then
        return 0
      else
        _echo "[DEBUG][wait_until_exists($path)] | Empty" 1>&2
      fi

    else
      _echo "[DEBUG][wait_until_exists($path)] | Does not exist" 1>&2
    fi
    sleep "$sleep_interval"
    now="$(unixtime)"
    elapsed="$(echo "$now - $start_ts" | bc)"
    if [[ "$(echo "${elapsed} >= ${timeout}" | bc)" == 1 ]]; then
      echo "[WARN][wait_until_exists($path)] Timed out waiting for $path to exist" 1>&2
      return 1
    fi
  done
}

# # import [-t, --timeout TIMEOUT_SEC=2] [--if-undefined CMD] [-v, --verbose] [--no-local-import] <FILE...> [--] [source args...]
# Tries to source FILE(s) locally, and if it fails, fetches asynchronously from giladbarnea/bashscripts/master and tries again.
# `import -v pip.sh deployme.sh`
function import() {
  function _fatal() { printf "\033[91m%s\033[0m\n" "[import] ! FATAL: $*" 1>&2; }
  function _warn() { printf "\033[33m%s\033[0m\n" "[import] Warning: $*" 1>&2; }
  function _good() { printf "\033[32m%s\033[0m\n" "[import] Good: $*" 1>&2; }
  if [[ -z "$1" ]]; then
    _fatal "$0 function requires at least 1 pos arg (file path or gist id or url)"
    return 1
  fi

  local verbose=false
  local local_import=true
  local parse_source_args=false
  local hopefully_defined
  local timeout=2
  local files_to_import=()
  local files_to_fetch=()
  local files_to_fetch_tmp=()
  local source_args=()
  # declare -A fetched_files=()
  # declare -A imported_files=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --if-undefined*)
      if [[ "$1" == *=* ]]; then
        hopefully_defined=${1/*=/}
        shift
      else
        hopefully_defined="$2"
        shift 2
      fi
      if type "$hopefully_defined" &>/dev/null; then
        $verbose && _good "'$hopefully_defined' is defined, returning 0" 1>&2
        return 0
      fi
      ;;
    -v | --verbose)
      verbose=true
      shift
      ;;
    -t | --timeout)
      timeout="$2"
      shift 2
      ;;
    --no-local-import)
      local_import=false
      shift
      ;;
    --)
      parse_source_args=true
      shift
      ;;
    *)
      if $parse_source_args; then
        source_args+=("$1")
      else
        files_to_import+=("$1")
      fi
      shift
      ;;
    esac
  done

  if $verbose; then
    function _debug() { printf "\033[2m%s\033[0m\n" "[import][DEBUG] $*" 1>&2; }
  else
    function _debug() { :; }
  fi
  if [[ -z "${files_to_import}" ]]; then
    _fatal "Expecting at least 1 file name to import"
    return 1
  fi

  $local_import && {
    _debug "Trying to import ${#files_to_import[@]} files locally..."
    local file_to_import
    for file_to_import in ${files_to_import[@]}; do
      if { source "$file_to_import" ||
        source "$THIS_SCRIPT_DIR"/"$file_to_import" ||
        source "$SCRIPTS"/"$file_to_import" "${source_args[@]}"; } 2>/dev/null; then
        _debug "Sourced $file_to_import locally"
        continue
      fi
      files_to_fetch+=("$file_to_import")
    done

    if [[ -z "$files_to_fetch" ]]; then
      _debug "All imports succeeded locally, returning 0"
      return 0
    fi
  }

  files_to_fetch=("${files_to_import[@]}")

  local fetched_files_location=/tmp/import
  if ! mkdir -p "$fetched_files_location"; then
    _fatal "Failed 'mkdir -p $fetched_files_location'"
    return 1
  fi

  _debug "Fetching ${#files_to_fetch[@]} files in parallel..."

  local files_str="${files_to_fetch[*]}"
  local comma_sep_files="${files_str// /,}"
  if isdefined curl; then
    local curl_args=(
      --create-dirs
      "https://raw.githubusercontent.com/giladbarnea/bashscripts/master/{$comma_sep_files}"
      -o "$fetched_files_location/#1"
    )
    $verbose || curl_args+=(--silent)
    if ! curl "${curl_args[@]}" --parallel --parallel-immediate; then
      if ! curl --help | command grep -q '\-\-parallel'; then
        _warn "Looks like curl does not support --parallel, retrying without --parallel..."
        if ! curl "${curl_args[@]}"; then
          _fatal "Failed curl ${curl_args[*]}, returning 1"
          rm -rf "$fetched_files_location"
          return 1
        fi
      fi
    fi
  elif isdefined wget; then
    for file_to_fetch in ${files_to_fetch[@]}; do
      wget.bg \
        "https://raw.githubusercontent.com/giladbarnea/bashscripts/master/$file_to_fetch" \
        "$fetched_files_location/$file_to_fetch"
    done
    sleep 0.01 # wget downloads partial files
  else
    _fatal "Neither curl nor wget are installed, returning 1"
    return 1
  fi

  _debug "Done fetching ${#files_to_fetch[@]} files in parallel, now sourcing..."

  local start_ts="$(unixtime)"
  local now elapsed source_exitcode file_to_fetch
  local sourced_ok=false
  if [[ -z "$LEGACY_IMPORT" || "$LEGACY_IMPORT" == false ]]; then
    while true; do
      sourced_ok=false
      _debug "Iterating ${#files_to_fetch[@]} files to source..."
      files_to_fetch_tmp=()
      file_to_fetch=
      for file_to_fetch in ${files_to_fetch[@]}; do
        sourced_ok=false
        now="$(unixtime)"
        elapsed="$(bc <<<"$now - $start_ts")"
        if [[ "$(bc <<<"${elapsed} >= ${timeout}")" == 1 ]]; then
          _fatal "Timed out! Still left to fetch: ${files_to_fetch[*]}"
          rm -rf "$fetched_files_location"
          return 1
        fi

        if [[ -s "$fetched_files_location/$file_to_fetch" ]]; then
          source "$fetched_files_location/$file_to_fetch" "${source_args[@]}"
          source_exitcode=$?
          if [ $source_exitcode == 0 ]; then
            sourced_ok=true
          else
            _debug "Failed sourcing: $file_to_fetch. source exit code: $source_exitcode"
          fi
        else
          _debug "Empty: $file_to_fetch"
        fi

        if $sourced_ok; then
          _debug "Sourced successfully: $file_to_fetch"
        else
          sleep 0.005
          files_to_fetch_tmp+=("$file_to_fetch")
        fi
      done
      if [[ "${#files_to_fetch_tmp}" = 0 ]]; then
        _debug "All imports succeeded, returning 0"
        rm -rf "$fetched_files_location"
        return 0
      fi
      files_to_fetch=("${files_to_fetch_tmp[@]}")
    done
  else
    ### Legacy import (waits for last download)
    local source_failed=()
    local wait_until_exists_args=(--timeout 1)
    for file_to_fetch in ${files_to_fetch[@]}; do
      if $verbose; then
        wait_until_exists_args+=(--verbose)
      fi
      if wait_until_exists "$fetched_files_location/$file_to_fetch" "${wait_until_exists_args[@]}"; then
        source "$fetched_files_location/$file_to_fetch" "${source_args[@]}"
        source_exitcode=$?
        _debug "source $file_to_fetch exit code: $source_exitcode"
        if [[ "$source_exitcode" != 0 ]]; then source_failed+=("$file_to_fetch"); fi
      fi
    done
    if "${source_failed}"; then
      _warn "Some imports failed, returning 1"
      return 1
    fi
    _debug "All imports succeeded, returning 0"
    return 0
  fi

  ### THIS CODE IS NEVER EXECUTED

  local outfilename="$(randstr)"
  local outfilepath="$fetched_files_location/$outfilename"

  local targets=(
    #    "$target"
    # "https://raw.githubusercontent.com/$target"
    "https://raw.githubusercontent.com/giladbarnea/bashscripts/master/$target"
    # "https://gist.github.com/${target}/raw"
    # "https://gist.github.com/giladbarnea/${target}/raw"
  )

  for _target in "${targets[@]}"; do
    wget.bg "$outfilepath" "$_target"
  done
  if wait_until_exists "$outfilepath" 2; then
    source "$outfilepath"
    return $?
  else
    return 1
  fi

  #####

  if wget.bg "$outfilepath" "https://raw.githubusercontent.com/giladbarnea/bashscripts/master/$target"; then
    source "$outfilepath"
    return $?
  fi

  # Valid URL, e.g https://raw.githubusercontent.com/giladbarnea/bashscripts/master/log.sh
  if wget.bg "$outfilepath" "$target"; then
    source "$outfilepath"
    return $?
  fi

  # GIST_ID or owner/GIST_ID
  if [[ "$target" = */* ]]; then
    local exitcode
    wget.bg "$outfilepath" "https://gist.github.com/${target}/raw"
    exitcode=$?
  else
    wget.bg "$outfilepath" "https://gist.github.com/giladbarnea/${target}/raw"
    exitcode=$?
  fi
  if [[ "$exitcode" == 0 ]]; then
    source "$outfilepath"
    return $?
  fi

  if ! isdefined gh; then
    echo "    !    $target does not exist locally, nor is it a valid url or a github gist, and gh cli is not installed. Exiting" 1>&2
    return 1
  fi

  local gist_url
  if gist_url="$(ghg-url "$target")"; then
    source <(wget -qO- "$gist_url" --no-check-certificate)
    return $?
  fi
  return 1

}
