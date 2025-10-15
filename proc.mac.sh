#!/usr/bin/env zsh

# # proc.get_focusable <ID_OR_NAME>
# Anything that `open` can work with is focusable.
# (e.g. a bundle id or app path).
function proc.get_focusable(){
	local name="$1"
	shift 1 || { log.error "$0: Not enough args (expected 1, got ${#$}). Usage:\n$(docstring "$0")"; return 2; }
  if isnum "$name"; then
    # 'command' includes the run args; 'comm' is only the app path
    vex "ps -p $name -o comm | tail +2"
    return $?
  fi
  if [[ "$name" =~ ^com\..+ ]] || { [[ "$name" = /Applications/* && -d "$name" ]] ; }; then
    printf "%s" "$name"
    return 0
  fi
  log.warn "$0 doesn't know how to handle '$name', printing as-is and returning 2"
  printf "%s" "$name"
  return 2
}

# # proc.focus <EXECUTABLE_OR_PID>
function proc.focus(){
	local executable_or_pid="$1"
	shift 1 || { log.error "$0: Not enough args (expected 1, got ${#$}). Usage:\n$(docstring "$0")"; return 2; }
	local focusable="$(proc.get_focusable "$executable_or_pid")"
  local open_args=()
  if [[ "$focusable" =~ ^com\..+ ]]; then
    open_args=(-b)
  else
    open_args=(-a)
  fi
  open_args+=("$focusable")
  [[ "$1" ]] &&	open_args+=(--args "$@")
  open "${open_args[@]}"
  return $?
}