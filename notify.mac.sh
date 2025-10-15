#!/usr/bin/env zsh

# ========[ This file is a wrapper for `osascript` or `terminal-notifier` (if available) for displaying simple notifications ]========

# # notif.generic <MESSAGE> [-t, --title TITLE] [-s, --sound (Default false)] [notify tool opt...]
function notif.generic(){
  local message="$1"
  shift 1 || { log.error "$0: Not enough args (expected at least 1, got ${#$}). Usage:\n$(docstring "$0")"; return 2; }
  local title sound
  zparseopts -F -D -E -- t:=title -title:=title s=sound -sound=sound
  local sound_len="${#sound}"
  if [[ "${commands[terminal-notifier]}" ]]; then
    local -a tnargs
    [[ $title ]] && tnargs+=(-title "${title:1}")
    (( ${#sound} )) && tnargs+=(-sound frog)
    terminal-notifier "${tnargs[@]}" -message "${message}" "$@"
  else
    local script="display notification \"${message}\""
    [[ $title ]] && script+=" with title \"${title:1}\""
    (( ${#sound} )) && script+=" sound name \"Frog\""
    osascript -e "${script}" "$@"
  fi
}

function notif.info(){
  notif.generic "$*" -t 'ℹ️  Info'
}
function notif.success(){
  notif.generic "$*" -t '✅  Success'
}
function notif.warn(){
  notif.generic "$*" -t '⚠️  Warn'
}
function notif.error(){
  notif.generic "$*" -t '❌  Error'
}
