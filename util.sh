#!/usr/bin/env zsh
# Sourced fourth, after environment, aliases and log


# ===========[ Basic/Primitive ]===========

# # isdefined <COMMAND>
# ## Examples
# ```bash
# isdefined killgrep && ...
# if isdefined $hooked_fn; then ... fi
# ```
function isdefined(){
    type "$1" &>/dev/null
}

# isdefined complete || function complete(){ : ; } ;
# isdefined compdef || function compdef(){ : ; } ;
# isdefined compadd || function compadd(){ : ; } ;
# isdefined sudo || function sudo(){ "$@" ; } ;

function is_sudo() {
  [[ ! $EUID -gt 0 ]]
}

# # is_piped
# Whether stdin is available.
# This situation is piped:
# echo foo | is_piped && echo piped
function is_piped() {
  # Reading from stdin with timeout for no stdin: if read -t 0 -u 0 stdin
  [[ ! -t 0 ]]
}

# # is_piping
# Whether stdout is available.
# This situation is piping:
# { is_piping && echo piping ; } | cat
function is_piping(){
  [[ ! -t 1 ]]
}

function is_sourced(){
  # https://stackoverflow.com/a/28776166/11842164
  [[ $ZSH_EVAL_CONTEXT =~ :file$ ]]
}

function is_interactive(){
  [[ $- == *i* ]]
}

function is_heb_layout() {
  [[ $(xset -q | grep -o "LED.*") == *1* ]]
}

function is_pycharm() {
  [[ "$__CFBundleIdentifier" = com.jetbrains.pycharm ]]
}

function is_zunit(){
  [[ "$ZSH_ARGZERO" = */zunit ]]
}

function is_human(){
  is_interactive && \
  ! is_piping && \
  [[ "$CLAUDECODE" != 1 ]] && \
  ! is_zunit && \
  ! is_pycharm && \
  [[ ! "$VSCODE_INJECTION" = 1 ]] && \
  [[ ! "$CURSOR_TRACE_ID" ]]
}

# # randstr [LENGTH] (default 16)
function randstr() {
  local len=${1:-16}
  LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$len"
}


# -----------[ Env vars ]-----------

# # loadenvfile <FILE> [-v]
# Loads a file containing environment variables into the current shell.
# Ignores lines starting with '#'.
function loadenvfile(){
  local envfile="$1"
  local verbose="$2"
  shift || { log.error "No envfile provided. Usage:\n$(docstring "$0")"; return 2; }
  local line
  command grep --color=never -E -v '^(\s*#|$)' "$envfile" | while read -r line; do
    # varname="${line%=*}"
    # value="${line#*=}"
    # current_value="${(Q)$(set | command grep --color=never -oP "(?<=^$varname=).+")}"
    # statement="export $line"
    # [[ "$current_value" && "$current_value" != "$value" ]] && {
    # 	statement+="   #${C0} changed from $current_value"
    # }
    # vex export "$line" ---just-run\
    if [[ "$verbose" ]]; then
      vex export "$line" ---just-run || return $?
    else
      eval export "$line" || return $?
    fi
  done
}


# -----------[ Network ]-----------

function showip() {
  export VEX_LOG_BEFORE_RUNNING=true
  vex 'ifconfig en0 | grep inet | grep -v inet6'
  vex "netstat -nl | grep -P '1(7|9)2\.'"
  vex "ifconfig -a | grep -P '1(7|9)2\.'" || vex "ifconfig -a | grep inet"
  vex "ip addr | grep -P '1(7|9)2\.'"
  local hostname_args=()
  if [[ "$OS" = macos ]]; then
    hostname_args+=(-f)
  else
    hostname_args+=(-I)
  fi
  vex hostname ${hostname_args[@]}
  isdefined nmap && log.info "nmap installed but dont know how to use" -L
  isdefined arp && log.info "arp installed but dont know how to use" -L
  vex curl http://myexternalip.com/raw
  vex curl ipinfo.io
  vex curl -s -S -4 https://icanhazip.com  # pass -6 for ipv6
  log.info "\nrun ${Cc}cat /proc/net/fib_trie${Cc0} for main and local IPs"
  export VEX_LOG_BEFORE_RUNNING=

}

  # # fetchfile <URL> [DESTINATION]
  function fetchfile(){
    # --fail is important, otherwise it exits 0 even if destination doesn't exist etc.
    local url="$1"
    if [[ "$2" ]]; then
      local dest="$2"
      shift 2
      curl --silent --fail --location -o "$dest" "$url" "$@"
      return $?
    else
      shift || return 1
      curl --silent --fail --location -O "$url" "$@"
      return $?
    fi
  }

  # # fetchhtml <URL> [client options...]
  function fetchhtml(){
    curl --silent --fail --location "$@"
  }


# ===========[ Time/Date ]===========

# # zprofc COMMAND [-s,--setup SETUP_COMMAND] [-n,--number NUMBER=1] [--autofunc]
# Uses zsh's built-in zprof to profile a command. Results are in milliseconds.
# Example:
# ```bash
# zprofc 'isdefined fd' -s 'source util.sh'
# zprofc '[[ 1 = 2 ]]' --autofunc -n 100
# ```
# Results table should be read as follows:
# | num | calls | with descandants  |         |         | without descandants |           |         |         |
# | --- | ----- | ----------------  | ------- | ------- | ------------------- | --------- | ------- | ------- |
# |     |       | *time*            |  *call* | *%*     | *time*              | *call*    | *%*     | *name*  |
# | 1)  | 1     | 4.21 ms           | 4.21 ms | 100.00% | 4.21 ms             | 4.21 ms   | 100.00% | func    |
function zprofc(){
  local cmd setup_command="" autofunc=false
  local -i number=1
  while (( $# )); do
    case "$1" in
      -s=*|--setup-command=*) setup_command=${1#*=} ;;
      -s|--setup-command) setup_command=${2}; shift ;;
      -n=*|--number=*) number=${1#*=} ;;
      -n|--number) number=${2}; shift ;;
      --autofunc) autofunc=true ;;
      *) cmd="$1" ;;
    esac
    shift
  done
  [[ "$autofunc" = true ]] && {
    local literal_function="function __zprofc_autofunc() { $cmd ; } ;"
    # Add "; " only if setup_command is not empty.
    setup_command+="${setup_command:+"; "}${literal_function}"
    cmd="__zprofc_autofunc"
  }
  if [[ $number -gt 1 ]]; then
    cmd="$(repeat $number printf "%s; " "$cmd")"
  fi
	zsh --stdin <<-EOF
	$setup_command
	zmodload zsh/zprof
	$cmd
	zprof
	zmodload -u zsh/zprof
	EOF
}

# # timeit <LITERAL_BASH_CODE> [---show-output] [---name=NAME] [-i,---ignore-errors (default false)] [-r <REPEAT>, --repeat=<REPEAT> (default 100)]
# Measures times before and after `eval "$@"`
function timeit() {
  if [[ "$*" =~ \breturn\b || "$*" =~ \bexit\b ]]; then
    log.fatal "arguments include a 'return' or 'exit' statement; this will exit $0 itself. aborting"
    return 1
  fi
  # setopt localoptions nowarncreateglobal &>/dev/null || true

  # Values will actually be seconds with nanosecond precision
  local -F start_ns
  local -F end_ns
  local command_name
  local total_sec total_ms
  local show_output=false
  local ignore_errors=false
  local -i repeat=100
  local positional=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      ---show-output) show_output=true;;
      ---name=*) command_name="${1#---name=}";;
      ---name) shift; command_name="$1";;
      ---ignore-errors|-i) ignore_errors=true;;
      *) positional+=("$1");;
    esac
    shift;
  done
  set	-- "${positional[@]}"
  unset i; local i=0
  if [[ "$show_output" = true ]]; then
    start_ns="${EPOCHREALTIME}"
    eval "$@" || { log.error "command failed: $*; returning 1"; return 1; }
    end_ns="${EPOCHREALTIME}"
  else
    start_ns="${EPOCHREALTIME}"
    eval "$@" >/dev/null 2>&1 || { log.error "command failed: $*; returning 1"; return 1; }
    end_ns="${EPOCHREALTIME}"
  fi
  total_sec=$(bc -l <<< "scale=10; $end_ns - $start_ns")
  total_ms="$(bc -l <<< "scale=10; $total_sec * 1000")"

  if [[ "$command_name" ]]; then
    printf "%s\n" "${command_name} │ $total_sec seconds ($total_ms ms)"
  else
    printf "%s\n" "Total: $total_sec seconds ($total_ms ms)"
  fi
}

if [[ "$OS" = macos ]]; then

  # # idletime [s, ms, us, ns] (default s)
  function idletime(){
    local unit="${1:-s}"
    local idletime_ns="$(ioreg -c IOHIDSystem | command grep -Po '(?<=HIDIdleTime" = )\d+')" || return 1
    local denominator
    case "$unit" in
      s)  denominator=1000000000 ;;
      ms) denominator=1000000 ;;
      us) denominator=1000 ;;
      ns) denominator=1 ;;
      *) log.error "Unknown unit: $unit"; return 1 ;;
    esac
    printf "%d" "$((idletime_ns / denominator))"
  }

  # # unixtime [s, ms, us, ns] (default s)
  # Prints e.g 1708426595
  function unixtime() {
    local unit="${1:-s}"
    case "$unit" in
      s)  gdate +%s ;;
      ms) gdate +%s%3N ;;
      us) gdate +%s%6N ;;
      ns) gdate +%s%9N ;;
      *) log.error "Unknown unit: $unit"; return 1 ;;
    esac
  }

  # # humantime [UNIX_TIMESTAMP / STDIN] (default now)
  # Prints UTC time e.g "Tue Feb 20 11:32:56 UTC 2024".
  function humantime() {
    local unix_timestamp
    if [[ "$1" ]]; then
      unix_timestamp="$1"
    elif is_piped; then
      unix_timestamp="$(<&0)"
    else
      humantime "$(gdate +%s)"
      return $?
    fi
    if isdefined gdate; then
      local truncated_unix_timestamp="${unix_timestamp:0:10}"
      gdate -u -d "@${truncated_unix_timestamp}"
    else
      date -u -r "${unix_timestamp}"
    fi
  }

  # # longdate [UNIX_TIMESTAMP] (default now)
  # Returns a string like "1691063481_Thu_Aug_3_14:51:21_IDT_2023"
  function longdate(){
    local ts
    [[ "$1" ]] && ts="$1" || ts="$(gdate +%s)"
    local human_ts="$(humantime "$ts")"
    local human_ts_no_spaces="${"${human_ts//  / }"// /_}"
    echo "${ts}_${human_ts_no_spaces}"
  }

else

  function idletime(){
    log.error "$0: not implemented for $OS"
    return 1
  }

  function unixtime() {
    date +%s.%N
  }

  function humantime() {
    # haven't tried
    date -d "@${1}"
  }
fi

# ===========[ Functional ]===========


# # map <CMD> [-v, --verbose] [-x, --exit-on-error]
# Convenience function of 'while read -r line; do eval "$line"; done'
# If `{}` is omitted, it will be appended to the end of the command.
# The following placeholders are supported:
# - None — "$line" is appended to the end of the command
# - `{}`
# - `${}`
# - `${line...}`
# - `${(...)line...}`
# Examples:
# ```bash
# ls | map cat		# {} can be omitted in this case
# ls *zip | map 'unzip ${} -d "$(basename $line .zip)"'
# ```
function map(){
  is_piped || { log.error "$0: current implementation only supports pipe usage"; return 1; }
  local verbose exit_on_error
  zparseopts -D -E -- v=verbose -verbose=verbose x=exit_on_error -exit-on-error=exit_on_error

  local expression="$1"
  shift 2>/dev/null || { log.error "$0: Not enough positional args (expected at least 1, got ${#$}). Usage:\n$(docstring -p "$0")"; return 2; }
  [[ "$1" ]] && { log.error "$0: Too many positional args. Specify the entire expression as a single argument. Usage:" ; docstring -p "$0"; return 2; }

  local substituted_expression
  if [[ "$expression" == *\$\{\}* ]]; then  # ${} -> ${line}
    substituted_expression="${expression//\$\{\}/\${line\}}"
  elif [[ "$expression" == *\{\}* ]]; then  # {} -> ${line}
    substituted_expression="${expression//\{\}/\${line\}}"
  elif [[
          # Keep as-is if:
          # 1. $line
          # 2. ${line...
          # 3. ${(...)line...
          "$expression" == *\$line*
          || "$expression" == *\$\{line*
          || "$expression" == *\$\{\(*\)line*
    ]]; then
    substituted_expression="$expression"
  else  # No {} in statement -> append "$line"
    substituted_expression="$expression \"\$line\""
  fi
  [[ "$verbose" ]] && log.debug "$(typeset expression substituted_expression)"
  local origpwd="$PWD"
  local line
  local current_iteration_failed=false
  local failed_count=0
  local original_LOG_TRACE_OFFSET="$LOG_TRACE_OFFSET"
  export LOG_TRACE_OFFSET=4

  while IFS= read -r line; do
    [[ "$verbose" ]] && log.debug "$(typeset -p line)"
    [[ -z "$line" || "$line" == '""' || "$line" == "''" ]] && {
      [[ "$verbose" ]] && log.debug "Skipping empty line"
      continue
    }
    current_iteration_failed=false
    [[ "$verbose" ]] && log.debug "Evaluating: ${(e)substituted_expression}"
    eval ${(e)substituted_expression} || current_iteration_failed=true

    [[ "$PWD" != "$origpwd" ]] && builtin cd "$origpwd"

    if "$current_iteration_failed"; then
      ((failed_count++))
      [[ "$exit_on_error" ]] && break
    fi
  done

  export LOG_TRACE_OFFSET="$original_LOG_TRACE_OFFSET"
  [[ "$verbose" ]] && log.debug "$(typeset failed_count)"
  return "$failed_count"
}

# # mapcmd CMD [CMD_ARGS...]
function mapcmd() {
  is_piped || { log.error "$0: current implementation only supports pipe usage"; return 1; }
  local cmd="$1"
  shift
  local -a command_args=("$@")
  # expression='${line:2}'; line='hello from stdin'; var_name='line'; print "${expression//line/${line}}"  # ${hello:2}
  local -a placeholder_to_substitute=(
    '{}'
    '\${}'
    '\$line'
  )
  local substitution='${line}'
  local placeholders_as_is='\${*line*}'
  # Add {} placeholder if not present in args
  # shellcheck disable=SC2157,SC1083
  # if [[ ! ${command_args[(r)$~{}]} ]]; then
  #   command_args+=("{}")
  # fi
  local pattern the_pattern
  local user_specified_placeholder=false
  for pattern in ${placeholder_to_substitute[@]} "$placeholders_as_is"; do
    if [[ ${command_args[(r)"$pattern"]} ]]; then
      the_pattern="${pattern}"
      user_specified_placeholder=true
      break
    fi
  done

  local -i placeholder_index
  if [[ "$user_specified_placeholder" = true ]]; then
    placeholder_index=${command_args[(I)"$the_pattern"]}
  else
    command_args+=("{}")
    placeholder_index=${#command_args[@]}
  fi

  # shellcheck disable=SC1083
  declare -i fail_count=0
  local stdin_line
  while IFS= read -r stdin_line; do
    command_args["$placeholder_index"]="$stdin_line"
    $cmd "${command_args[@]}" || ((fail_count++))
  done
  return $fail_count
}

# # filter <FUNCTION> <STDIN / LINE...> [-r, --raw] [-v --verbose]
# Prints back only lines that pass the function (returns 0).
# Internally uses `$line` as the line variable.
# --raw: don't use eval, just run the line(s).
# Examples:
# ```bash
# echo "hello\necho" | filter '[[ {} = hello* ]]' # hello
# echo "hello\necho" | filter isdefined					  # echo
# ```
function filter(){
  local raw verbose
  zparseopts -D -E -- r=raw -raw=raw v=verbose -verbose=verbose
  local filter_func="$1"
  shift || { log.error "$0 $(docstring -p "$0"): no filter function provided"; return 2; }
  local origpwd="$PWD"
  local line
  local -a lines=()

  if [[ "$1" ]]; then
    lines=("$@")
  elif is_piped; then
    lines=("$(<&0)")
  else
    log.error "$0: no input provided (pipe or argument) "
    return 2
  fi

  local substituted_statement
  if [[ "$filter_func" == *\$\{\}* ]]; then  # ${} -> ${line}
    substituted_statement="${filter_func//\$\{\}/\${line\}}"
  elif [[ "$filter_func" == *\{\}* ]]; then  # {} -> ${line}
    substituted_statement="${filter_func//\{\}/\${line\}}"
  elif [[ 
    # Keep as-is if:
    # 1. $line
    # 2. ${line...
    # 3. ${(...)line...
    "$filter_func" == *\$line* 
    || "$filter_func" == *\$\{line* 
    || "$filter_func" == *\$\{\(*\)line*
    ]]; then
    substituted_statement="$filter_func"
  else  # No {} in statement -> append "$line"
    substituted_statement="$filter_func \"\$line\""
  fi

  [[ "$verbose" ]] && log.debug "Replaced placeholder with 'line': ${substituted_statement}"
  local -i exit_code
  while read -r line; do
    [[ "$verbose" ]] && log.debug "$(typeset line)"
    [[ -z "$line" || "$line" == '""' || "$line" == "''" ]] && {
      [[ "$verbose" ]] && log.debug "${Cd}▊${C0} Skipping empty line"
      continue
    }
    if [[ "$raw" ]]; then
      ${(e)substituted_statement} && printf "%s\n" "$line"
    else
      [[ "$verbose" ]] && log.debug "${Cd}▊${C0} Evaluating: ${(e)substituted_statement}"
      eval ${(e)substituted_statement}
      exit_code=$?
      [[ "$verbose" ]] && log.debug "${Cd}▊${C0} Exit code: $exit_code"
      if [[ $exit_code == 0 ]]; then
        printf "%s\n" "$line"
      fi
    fi
    [[ "$PWD" != "$origpwd" ]] && builtin cd "$origpwd"
  done <<< "${lines[@]}"

  [[ "$PWD" != "$origpwd" ]] && builtin cd "$origpwd"
  return 0
}

# # filterwords <FUNCTION> <STDIN / WORD...>
# Prints back only words that pass the function (returns 0). Space-separated.
# Examples:
# ```bash
# echo hello printf 123 | filterwords '[[ {} =~ [[:digit:]] ]]'	# 123
# echo hello printf 123 | filterwords isdefined								  # printf
# ```
function filterwords(){
  local filter_func="$1"
  shift || { log.error "$0 $(docstring "$0"): no filter function provided"; return 1; }
  local origpwd="$PWD"
  local word
  local words=()

  if [[ "$1" ]]; then
    words=($@)
  else
    words=($(<&0))
  fi

  local any_passed=false
  local substituted_statement
  if [[ "$filter_func" == *\$\{\}* ]]; then  # ${} -> ${word}
    substituted_statement="${filter_func//\$\{\}/\${word\}}"
  elif [[ "$filter_func" == *\{\}* ]]; then  # {} -> ${word}
    substituted_statement="${filter_func//\{\}/\${word\}}"
  elif [[ "$filter_func" == *\$word* || "$filter_func" == *\$\{word* ]]; then  # $word or ${word... -> keep as-is
    substituted_statement="$filter_func"
  else  # No {} in statement, append "$word"
    substituted_statement="$filter_func \"\$word\""
  fi

  # shellcheck disable=SC2013
  for word in "${words[@]}"; do
    # log.debug "word: ${word}"
    if eval "$substituted_statement"; then
      if $any_passed; then
        printf " %s" "$word"
      else
        printf "%s" "$word"
        any_passed=true
      fi
    fi
  done
  [[ "$PWD" != "$origpwd" ]] && builtin cd "$origpwd"
  return 0

}

# # eee <STDIN...>
# Outputs to both stdout and stderr.
function eee() {
  tee -a /dev/stderr
}

# # eo <STDIN...>
# Redirects stderr to stdout.
function eo() {
  cat 2>&1
}

# # en <STDIN...>
# Redirects stderr to dev/null.
function en() {
  cat 2>/dev/null
}

# # oe <STDIN...>
# Redirects stdout to stderr.
function oe() {
  cat 1>&2
}

# # on <STDIN...>
# Redirects stdout to dev/null.
function on() {
  cat 1>/dev/null
}

# ===========[ Meta ]===========
# -----------[ Eval/Exec/Running ]-----------

# # vex CMD [CMD_OPTS...] [VEX_OPTS...]
# Verbose execution. Runs the given command, prints its output, prints whether the given command succeeded or not, and returns its exitcode.
# vex [---log-only-before-running=false] [---just-run=false] [---notify=false]
# vex [---log-before-running=false] [---log-only-errors=false] [---just-run=false] [---notify=false]
# ## Pre-execution logging
# `---log-before-running` Logs the command before running it. Can be combined with `---log-only-errors`.'
# `---log-only-before-running` Altogether turns off post-run success and failure logs. Implies `---log-before-running`, and incompatible with `---log-only-errors`.
# ## Execution control
# `---just-run` means not using `eval "$@"` but simply `"$@"`.
# ## Post-execution logging
# `---log-only-errors` Skips logging a success message if the command succeeded. Incompatible with `---log-only-before-running`.'
# ## Environment Variables
# The following environment variables are supported:
# - `VEX_LOG_ONLY_BEFORE_RUNNING` (default false)
# - `VEX_LOG_BEFORE_RUNNING` (default false)
# - `VEX_LOG_ONLY_ERRORS` (default false)
# - `VEX_JUST_RUN` (default false)
# - `VEX_NOTIFY` (default false)
function vex() {
  # bug?: also ---log-before-running ---log-only-errors doesn't log before running
  local positional=()
  local log_only_before_running="${VEX_LOG_ONLY_BEFORE_RUNNING:-false}"
  local log_before_running="${VEX_LOG_BEFORE_RUNNING:-false}"
  local log_only_errors="${VEX_LOG_ONLY_ERRORS:-false}"
  local just_run="${VEX_JUST_RUN:-false}"
  local notify="${VEX_NOTIFY:-false}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      ---log-only-before-running) log_only_before_running=true ;;
      ---log-before-running) log_before_running=true ;;
      ---log-only-errors) log_only_errors=true ;;
      ---just-run) just_run=true ;;
      ---notify) notify=true ;;
      ---*) log.warn "Ignoring unknown option: $1" ;;
      *)
        positional+=("$1") ;;
    esac
    shift
  done
  set -- "${positional[@]}"

  # * Check args for edge cases
  if [[ $notify = true && "$OS" = macos ]]; then
    log.warn "---notify is not implemented on MacOS. Setting to false."
    notify=false
  fi

  if [[ $log_only_before_running = true && $log_only_errors = true ]]; then
    log.warn "Cannot specify both ---log-only-before-running and ---log-only-errors. Logging indiscriminately before running."
    log_only_before_running=false
    log_before_running=true
    log_only_errors=false
  fi

  if [[ $log_only_before_running = true && $log_before_running = true ]]; then
    log.warn "---log-only-before-running implies ---log-before-running. Ignoring ---log-before-running."
    log_before_running=false
  fi

  local description="${Cc}$*${C0}"
  local pad_message_left=false
  local message

  # * Possibly log description of command before running
  if [[ "$log_only_before_running" = true || "$log_before_running" = true ]]; then
    message="${Cd}Running:${Cd0} $description"
    log "$message" --no-trace
    [[ $notify = true ]] && notif.info "Running: $*"
    pad_message_left=true
  fi

  # * Run command
  # Note: ${(e)expression} expands 'User ${USER} has home $HOME' to 'User gilad has home /home/gilad'
  local -i exitcode
  if [[ $just_run = true ]]; then
    "$@"
    exitcode=$?
  else
    # The most robust I've found: printf '%q\n' "$@"
    eval "$@"
    exitcode=$?
  fi

  if [[ $log_only_before_running = true ]]; then
    return $exitcode
  fi

  # * Possibly log outcome of command after running
  if [[ "$exitcode" == 0 ]]; then
    if [[ $log_only_errors = true ]]; then
      return 0
    fi
    message="OK${C0}: $description"
    if [[ $pad_message_left = true ]]; then
      log.success "     ${message}" --no-trace --no-level
    else
      log.success "${message}" --no-trace --no-level
    fi
    [[ $notify = true ]] && notif.success "OK: $*"
    return 0
  fi

  # * Log error (reaching here means command failed, and $log_only_before_running is false)
  message="FAIL ($exitcode)${C0}: $description"
  if [[ $pad_message_left = true ]]; then
    log.warn "   ${message}" --no-trace --no-level
  else
    log.warn "${message}" --no-trace --no-level
  fi
  [[ $notify = true ]] && notif.error "FAIL ($exitcode): $*"
  return "$exitcode"
}

# # runcmds [---no-vex] [---confirm-each / ---confirm-once] [---no-exit-on-error] [vex options...] CMD...
# `---no-vex` simply `eval`s each command, and not passing it to `vex`.
function runcmds() {
  local positional=()
  local confirm_each="${RUNCMDS_CONFIRM_EACH:-false}"
  local confirm_once="${RUNCMDS_CONFIRM_ONCE:-false}"
  # local exit_on_error="${RUNCMDS_NO_EXIT_ON_ERROR:-true}"
  local exit_on_error=true
  # local simple_eval="${RUNCMDS_SIMPLE_EVAL:-false}"
  local use_vex=true
  # local just_run="${RUNCMDS_JUST_RUN:-false}"
  # local log_before_running="${RUNCMDS_LOG_BEFORE_RUNNING:-false}"
  # local log_only_outcome="${RUNCMDS_LOG_ONLY_OUTCOME:-true}"
  # local log_only_errors="${RUNCMDS_LOG_ONLY_ERRORS:-false}"
  local vex_args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      ---confirm-each) # 3 dashes on purpose
        confirm_each=true ;;
      ---confirm-once)
        confirm_once=true ;;
      ---no-exit-on-error)
        exit_on_error=false ;;
      ---no-vex)
        use_vex=false ;;
      ---*)
        vex_args+=("$1") ;;
      *)
        positional+=("$1") ;;
    esac
    shift
  done
  set -- "${positional[@]}"

  # * Check for args edge cases
  if [[ $confirm_each = true && $confirm_once = true ]]; then
    log.warn "Cannot specify both ---confirm-each and ---confirm-once. Confirming each."
    confirm_each=true
    confirm_once=false
  fi
  if [[ $use_vex = false && "${vex_args}" ]] ; then
    log.warn "---no-vex is was specified along with vex-specific arguments: ${vex_args[*]}. Ignoring vex-specific arguments."
  fi

  # * If specified, confirm once with user.
  local user_answer exitcode cmd
  if $confirm_once; then
    log.prompt "Will run:"
    local line
    while read -r line; do printf "${Cc}%s${Cc0}\n" "$line"; done <<< "${@}"
    confirm "Continue?" || return 3
  fi

  declare -i fail_count=0
  local vex_args=()
  for cmd in "${@}"; do
    if $confirm_each; then
      user_answer="$(input "Run ${Cc}${cmd}${Cc0}?" --choices='[y]es [n]o [q]uit')"
      if [[ "$user_answer" == n ]]; then
        log.prompt Skipping
        continue
      elif [[ "$user_answer" == q ]]; then
        log.warn Aborting
        return 3
      fi
    fi
    if $use_vex; then
      vex "$cmd" "${vex_args[@]}"
      exitcode=$?
    else
      eval "$cmd"
      exitcode=$?
    fi
    if [[ $exitcode != 0 ]]; then
      ((fail_count++))
      if $exit_on_error; then
        log.error "Failed ${Cc}${cmd}${Cc0} (exited: $exitcode). Aborting."
        return $exitcode
      fi
      log.warn "Failed ${Cc}${cmd}${Cc0} (exited: $exitcode). Continuing."
    fi
  done
  return "$fail_count"
}

# # silence <CMD...> [---eval]
# Runs `"$@" &> /dev/null`.
# If `---eval` is specified, then `eval "$@" &> /dev/null` is run instead.
function silence(){
  local use_eval=false
  declare -a cmds=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      ---eval) use_eval=true ;;
      *) cmds+=("$1") ;;
    esac
    shift
  done
  [[ -n $cmds ]] || { log.error "$0: Not enough positional args (expected at least 1). Usage:\n$(docstring "$0")"; return 2; }
  local exitcode
  if $use_eval; then
    "${cmds[@]}" 1>/dev/null 2>&1
    exitcode=$?
  else
    "${cmds[@]}" 1>/dev/null 2>&1
    exitcode=$?
  fi

  return $exitcode
}

# # cached FUNCTION_NAME [FUNCTION_ARGS...]
# Hashes the function name and its arguments, and stores the result and the exit code in a cache directory (default: /tmp/land/cached). Prints the output of the function.
# Can be disabled by setting `DISABLE_CACHE` to `true` or `1`.
function cached() {
  [[ "$DISABLE_CACHE" = true || "$DISABLE_CACHE" = 1 ]] && {
    "$@"
    return $?
  }
  local func_name=$1
  shift || { log.error "no function name provided. Usage:\n$(docstring "$0")"; return 2; }
  local -a func_args=("$@")
  local cache_dir="/tmp/land/cached"
  mkdir -p "$cache_dir"
  local combined_hash="$(cachekey "$func_name" "${func_args[@]}")"
  local cached_output_file="${cache_dir}/${combined_hash}.output"
  local cached_exitcode_file="${cache_dir}/${combined_hash}.exitcode"
  if [[ -f "$cached_output_file" ]]; then
    cat "$cached_output_file"
    return "$(<"$cached_exitcode_file")"
  fi
  local func_output
  local -i func_exitcode
  func_output="$("$func_name" "${func_args[@]}")"
  func_exitcode=$?
  printf "%s" "$func_output" > "$cached_output_file"
  printf "%s" "$func_exitcode" > "$cached_exitcode_file"
  printf "%s" "$func_output"
  return "$func_exitcode"
}

typeset -g CACHE_DIR="/tmp/land/cached"

function cachekey(){
  local func_name=$1
  shift || { log.error "no function name provided. Usage:\n$(docstring "$0")"; return 2; }
  local -a func_args=("$@")
  local func_name_hash="$(md5sum <<< "$func_name" | awk '{print $1}')"
  local func_args_hash="$(md5sum <<< "${func_args[*]}" | awk '{print $1}')"
  local combined_hash="${func_name_hash}_${func_args_hash}"
  printf "%s" "$combined_hash"
}

# # clearcached [SUBPATH] [-v]
function clearcached(){
  local subpath
  local verbose
  while (( $# )); do
    case "$1" in
      (-v) verbose=true;;
      (*) subpath="$1";;
    esac
    shift
  done
  subpath="/${subpath#/}"
  [[ "$verbose" ]] && log.debug "Clearing cache: ${CACHE_DIR}${subpath}*"
  rm -rf "${CACHE_DIR}${subpath}"* 2>/dev/null || true
}

# # cachefn FUNCTION_NAME
# Replace a function with a cached version of itself.
function cachefn(){
  # Use functions -c oldfn newfn to remove the original function (zshbuiltins)
  :
}

# ===========[ Deprecated ]===========

# # # completion.generate <ARG...> [-d DESCRIPTION] [-e EXAMPLE (multiple)]
# # ## Examples:
# # ```bash
# # # Ex. 1
# # function compfn(){ completion.generate <METHOD> <URL> <API> <ENDPOINT> [DATA] '[-c]' '[-n]' ; }
# # complete -o default -F compfn fn
# #
# # # Ex. 2
# # complete -o default -C "completion.generate '[LINENUM_START]' '[LINENUM_STOP]' '[QUERY]'" hfzf
# # ```
# function completion.generate() {
#   local sig=()
#   local examples=()
#   # local example
#   local multiline=false
#   local description
#   while [ $# -gt 0 ]; do
#     case "$1" in
#     -e)
#       if [[ -n "${examples}" ]]; then
#         multiline=true
#       fi
#       examples+=("$2")
#       shift 2 ;;
#     -d)
#       description="$2"
#       shift 2 ;;
#     *)
#       if ! $multiline && [[ "$1" =~ .*$'\n'+.* ]]; then
#         # str.has_newline "$1" && multiline=true
#         multiline=true
#       fi
#       sig+=("$1")
#       shift ;;
#     esac
#   done
#   local index=$((COMP_CWORD - 1))
#   local current_word=${COMP_WORDS[$index]}
#   if [[ "$current_word" != -- ]]; then
#     return 1
#   fi
#   local old_comp_line="${COMP_LINE}"
#   local message="\n${h1}${COMP_LINE%% *}${C0} "
#   local msgarray=()
#   # if $multiline; then (message+="\n" && msgarray+=("\n")); fi
#   # if $multiline; then message+="\n"; fi
#   if [[ -n "$sig" ]]; then
#     local remaining_sig=("${sig[@]:$index}")
#     msgarray+=("${remaining_sig[@]}")
#     message+="${remaining_sig[*]}"
#     # if $multiline; then
#     #   message+="${remaining_sig[*]}"
#     # else
#     #   message+="${Cb}${Ci}${remaining_sig[*]}${C0}"
#     # fi
#   fi
#   if [[ -n "$description" ]]; then
#     if $multiline; then message+="\n"; fi
#     message+="    ${Ccyn}${description}${C0}"
#   fi
#   if [[ -n "${examples}" ]]; then
#     if $multiline; then message+="\n"; fi
#     local example
#     message+="\n  ${h2}Examples:${C0}"
#     for example in "${examples[@]}"; do
#       message+="\n    ❯ "
#       if isdefined bat.hilite; then
#         message+="$(echo "$example" | bat.hilite)"
#       else
#         message+="${Cblu}${example}${C0}"
#       fi
#     done
#     # if [[ "${#examples[@]}" -ge 2 ]]; then
#     #   # log.debug "examples: ${examples[*]} | len: ${#examples[@]}"
#     #   message+="\n  ${h2}Examples:${C0}"
#     #   for example in "${examples[@]}"; do
#     #     message+="\n    ❯ "
#     #     if isdefined bat.hilite; then
#     #       message+="$(echo "$example" | bat.hilite)"
#     #     else
#     #       message+="${Cblu}${example}${C0}"
#     #     fi
#     #   done
#     # else
#     #   example="${examples}"
#     #   message+="    ${Cd}Example:${C0} "
#     #   if isdefined bat.hilite; then
#     #     message+="$(echo "$example" | bat.hilite)"
#     #   else
#     #     message+="${Cblu}${example}${C0}"
#     #   fi
#     # fi
#   fi
#   #echo '\e[2J\e[H'
#   printf "%b\n\n" "$message" 1>&2
#   # printf '%b\n' $'\e[2J'
#   #log.debug "old_comp_line: ${old_comp_line}"
#   #  printf "%b" "$message" 1>&2
#   # COMPREPLY=(${msgarray[@]})
# }

#declare _completion_generate_examples=(
#  '-e "compfn(){ completion.generate ... ; }; complete -F compfn fn"'
#  '-e "complete -C \"completion.generate ...\" fn"'
#)
#complete -o default \
#         -C "completion.generate '<ARG...>' '[-e EXAMPLE (multiple)]' '[-d DESCRIPTION]' ${_completion_generate_examples[*]}" \
#         completion.generate

# ===========[ Misc ]===========

if [[ "$PLATFORM" == WIN ]]; then

  # really slow for some reason
  function print_hr(){ : ; } ;

elif [[ "$SHELL" = *zsh ]]; then

  # # print_hr [LEN] [-n, --no-newline]
  # LEN defaults to term width if unspecified
  function print_hr() {
    # Performance:
    #  hyperfine results:
    #    for loop: bash is 2 microsecs, zsh is 600 :[
    #    reducing iterations and printing longer strings slows things down
    #  timeit results:
    #    timeit 'for ((j=0; j<10000; j++)); do cols=$((COLUMNS/8)); for ((i = 0; i < cols; i++)); do printf "────────" 1>&2; done; done' ==> 130 microsecs
    #    timeit 'for ((j=0; j<10000; j++)); do cols=$((COLUMNS)); for ((i = 0; i < cols; i++)); do printf "─" 1>&2; done; done' ==> 940 microsecs
    #    timeit 'unset i; local i=0; for i in {1..10000}; do printf "─%.0s" {1..$COLUMNS} 1>&2; done'	==> 36 microsecs
    #    timeit 'unset i; local i=0; for i in {1..10000}; do printf "──%.0s" {1..165} 1>&2; done'	==> 31 microsecs
    #    reducing iterations and printing longer strings increases speed proportionally in for loops, less so in {1..}

    printf "\033[38;2;75;75;75m" 1>&2
    local cols reset_string="\033[0m\n"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -n|--no-newline) reset_string="\033[0m";;
        *) cols="$1";;
      esac
      shift
    done
    [[ -z "$cols" ]] && cols="$COLUMNS"
    [[ -z "$cols" ]] && cols="$(tput cols)"
    # [[ -n "${print_hr_cache[$cols]}" ]] && { printf "%s" "${print_hr_cache[$cols]}" 1>&2 ; return 0 ; }
    # # Least slow way I've found in zsh
    # # shellcheck disable=SC2051
    # local hr="$(printf '─%.0s' {1..$cols})"
    # print_hr_cache[$cols]="$hr"
    # printf "%s" "$hr" 1>&2
    # This is even more zsh-native: print ${(l.$COLUMNS..—.)}
    printf "─%.0s" {1..$cols} 1>&2

    # shellcheck disable=SC2059
    printf "$reset_string" 1>&2
  }

else
  # # print_hr [LEN] [-n, --no-newline]
  # LEN defaults to term width if unspecified
  function print_hr() {
    printf "\033[38;2;75;75;75m" 1>&2
    local cols reset_string="\033[0m\n"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -n|--no-newline) reset_string="\033[0m";;
        *) cols="$1";;
      esac
      shift
    done
    [[ -z "$cols" ]] && cols="$COLUMNS"
    [[ -z "$cols" ]] && cols="$(tput cols)"
    # Way faster in hyperfine (--shell=bash vs --shell=zsh) for some reason
    local i
    for ((i = 0; i < cols-1; i++)); do
      printf '─' 1>&2
    done
    # shellcheck disable=SC2059
    printf "$reset_string" 1>&2
  }

fi
