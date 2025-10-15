#!/usr/bin/env bash

usage='bfind.sh [SEARCH_VALUE [ROOT_DIR]] [OPTS...]
`ROOT_DIR_OR_SEARCH_VALUE` is what to search for if it is not a dir path, otherwise it sets where to search.
Optional `ARG_2` sets either what to search or where to search, whatever is was not set, otherwise passed to `find`.
Available `OPTS` are `--min-depth` which sets start depth and `--max-depth`. Otherwise passed to `find`.'


function print_usage() {
  echo "$usage"
  exit 0
}

if [[ ! "$1" ]]; then
  echo "[ERROR] $0 Requires at least one arg (what to search for)" 1>&2
  print_usage
elif [[ "$1" == -h || "$1" == *help ]]; then
  print_usage
else

  declare location="$PWD"
  declare -i start_depth=1
  declare -i max_depth=10
  declare search="*"

  # * location or query
#  if [[ -d "$1" ]]; then
#    location="$1"
#  else
#    search="$1"
#  fi
#  shift

  declare positional=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --max-depth*)
      if [[ "$1" == --max-depth ]]; then
        max_depth="$2"
        shift 2
      else
        max_depth="${1/*=/}"
        shift
      fi ;;
    --min-depth*)
      if [[ "$1" == --min-depth ]]; then
        start_depth="$2"
        shift 2
      else
        start_depth="${1/*=/}"
        shift
      fi ;;
    *)
      if [[ ! "$search" ]]; then
        search="$1"
      elif [[ ! "$location" ]]; then
        if [[ ! -d "$1" ]]; then
          echo "[ERROR] $1 is not a dir" 1>&2
          exit 1
        fi
        location="$1"
      else
        positional+=("$1")
      fi
      shift ;;
    esac
  done
  set -- "${positional[@]}"

  declare -i i
  echo "[DEBUG] \x1b[2m$(typeset search location max_depth start_depth) @: ${*}\x1b[0m" 1>&2
  if [[ "$start_depth" -gt "$max_depth" ]]; then
    echo "[WARNING] start_depth ($start_depth) > max_depth ($max_depth); setting max_depth=$start_depth" 1>&2
    max_depth=$start_depth
  fi
  for ((i = start_depth; i <= max_depth; i++)); do

    (
      echo "[DEBUG] \x1b[2mSearching depth $i/$max_depth...\x1b[0m" 1>&2
      find "$location" -maxdepth $i -mindepth $i -name "$search" "$@"
      echo "[DEBUG] \x1b[2m✅ Done searching depth $i/$max_depth\x1b[0m" 1>&2
    ) &

  done

fi
