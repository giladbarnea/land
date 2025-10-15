#!/usr/bin/env bash


# Find icons:
# for file in $(fd -HI --type f warn -e png); do echo "\n$file\n" && kitty icat "$file" 2>/dev/null && sleep 0.25s; done


if [[ -z "$DISPLAY" || ! "$DISPLAY" =~ :[0-9] || "$OS" =~ Windows(_NT)? ]]; then
  # Zenity functions sometimes double as loggers as well, so without a display, just echo

  # echo "[zenity.sh][WARN] in SSH" 1>&2

  # # notif.generic <TEXT> <DIALOG_TYPE> [GLOBAL ZENITY OPTIONS...]
  function notif.generic() { echo "$1" 1>&2 ; } ;
else
  # # notif.generic <TEXT> <DIALOG_TYPE> [--bg] [GLOBAL ZENITY OPTIONS...]
  # `width` defaults to $COLUMNS.
  function notif.generic() {
    local text="$1"
    shift
    local background=false
    local positional=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --bg) background=true;;
        *) positional+=("$1");;
      esac
      shift
    done
    set -- "${positional[@]}"
    if "$background"; then
      (zenity --text="$text" "$@" &) &>/dev/null
      return 0  # dont know how to get status of bg job
    else
      zenity --text="$text" "$@"
      return $?
    fi
  }
fi

# # notif.notification [LEVEL={info,success,warn,error,fatal} (default info)] [--bg] <TEXT> [zenity args...]
function notif.notification(){
  local log_level=info
  local zgeneric_args=(--notification --timeout=0)
  local -A icons=(
    [info]=/usr/share/icons/Yaru/48x48/status/dialog-information.png
    [success]=/usr/share/icons/Yaru/48x48/actions/dialog-ok.png
    [warn]=/usr/share/icons/Yaru/48x48/status/dialog-warning.png
    [error]=/usr/share/icons/Yaru/48x48/status/dialog-error.png
    [fatal]=/usr/share/icons/Yaru/48x48/actions/cancel.png
  )
  if [[ "$1" = info || "$1" = success || "$1" = fatal || "$1" = error || "$1" = warn ]]; then
    log_level="$1"
    shift
  fi
  zgeneric_args+=(--window-icon="${icons[$log_level]}")
  notif.generic "$@" "${zgeneric_args[@]}"
  return 0
}

# # notif.success <TEXT> [GLOBAL ZENITY OPTIONS (except --notification and --window-icon)...]
# Possibly does `log.success TEXT`
function notif.success() {
  notif.notification success "$@"
}

# # notif.fatal <TEXT> [GLOBAL ZENITY OPTIONS (except --notification and --window-icon)...]
# Does log.fatal TEXT
function notif.fatal() {
  notif.notification fatal "$@"
}

# # notif.info <TEXT> [GLOBAL ZENITY OPTIONS (except --notification and --window-icon)...]
# Does log.info TEXT
function notif.info() {
  notif.notification "$@"
}

# # notif.error <TEXT> [GLOBAL ZENITY OPTIONS (except --notification and --window-icon)...]
# Does log.error TEXT
function notif.error() {
  notif.notification error "$@"
}

# # notif.warn <TEXT> [GLOBAL ZENITY OPTIONS (except --notification and --window-icon)...]
# Does log.warn TEXT
function notif.warn() {
  notif.notification warn "$@"
}

# # notif.confirm <TEXT> [GLOBAL ZENITY OPTIONS (except --notification and --window-icon)...]
# Does log.prompt TEXT
function notif.confirm() {
  # Yes / No
  notif.generic "$@" --question --title='?'
}
# # notif.input <PROMPT>
# ## Examples
# ```bash
# var=$(notif.input)
# ```
function notif.input() {
  # text input. no --text arg
  zenity --text-info --editable
}

complete -o dirnames -F __notif._completion notif.
