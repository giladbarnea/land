#!/usr/bin/env bash
# shellcheck disable=2154

# # find.big_files <DEST> <-C ITEMCMD> [-S SORTFLAG=-h] [--vcs] [FIND OPTIONS...]
# Examples:
# ```bash
# # Ex. 1
# find.generic . -type f -size +1k -C "$(cat <<"EOF"
# du -h "$item" | cut -d $'\t' -f 1
# EOF
# )"
#
# # Ex. 2
# find.generic "$dest" -type f -size +1k "$@" -C "wc -l \"\$item\" | cut -d ' ' -f 1" -S -V
# find.generic . -type d ! -regex ".*\.nox.*" ! -regex ".*\.venv.*" -C 'find "$item" -type f'
# ```
function find.generic() {
  log.title "find.generic $*"
  local files=()
  local findargs=()
  local dest="$1"
  shift || return 1
  local vcs=false
  local itemcmd
  local sortflag='-h'
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --vcs)
      vcs=true
      shift || return 1 ;;
    -C)
      itemcmd="$2"
      shift 2 || return 1 ;;
    -S)
      sortflag="$2"
      shift 2 || return 1 ;;
    *)
      findargs+=("$1")
      shift || return 1 ;;
    esac
  done
  if ! $vcs; then
    findargs+=(
      ! -regex "'.*\.git.*'"
    )
  fi
  if [[ ! "$dest" || ! "$itemcmd" ]]; then
    log.fatal "$0 not enough args"
    docstring -p "$0"
    return 1
  fi
  log.debug "itemcmd: ${itemcmd}"
  if [[ ! "$itemcmd" =~ .*'\$item'.* ]]; then
    log.fatal "ITEMCMD must include \$item. Got: ${Cc}$itemcmd"
    return 1
  fi
  local item res
  while read -r item; do
    if ! res="$(eval "$itemcmd")"; then
      log.fatal "Failed $itemcmd"
      return 1
    fi
    files+=("$res | $item\n")
  done < <(find "$dest" "${findargs[@]}")
  echo "${files[*]}" | sort "$sortflag"
}

# # find.big_files [DEST] [--vcs] [FIND OPTIONS...]
function find.big_files() {
  log.title "find.big_files $*"
  local dest="."
  [[ -d "$1" ]] && dest="$1" && shift
  find.generic "$dest" -type f -size +1k "$@" -C "du -h \"\$item\" | cut -d \$'\t' -f 1"
}

# # find.dirs_with_many_files [DEST] [--vcs] [FIND OPTIONS...]
# ```bash
# find.dirs_with_many_files ! -regex '.*\.nox.*' ! -regex '.*\.venv.*'
# ```
function find.dirs_with_many_files() {
  # Alternative: tools.sh fd.count_files
  log.title "find.dirs_with_many_files $*"
  local dest="."
  [[ -d "$1" ]] && dest="$1" && shift
  find.generic "$dest" -type d "$@" -C "find \"\$item\" -type f | wc -l"
}

# # find.files_with_many_chars [DEST] [--vcs] [FIND OPTIONS...]
function find.files_with_many_chars() {
  log.title "find.files_with_many_chars $*"
  local dest="."
  [[ -d "$1" ]] && dest="$1" && shift
  find.generic "$dest" -type f -size +1k "$@" -C "wc -m \"\$item\" | cut -d ' ' -f 1" -S -V
}

# # find.files_with_many_lines [DEST] [--vcs] [FIND OPTIONS...]
function find.files_with_many_lines() {
  log.title "find.files_with_many_lines $*"
  local dest="."
  [[ -d "$1" ]] && dest="$1" && shift
  find.generic "$dest" -type f -size +1k "$@" -C "wc -l \"\$item\" | cut -d ' ' -f 1" -S -V
}

