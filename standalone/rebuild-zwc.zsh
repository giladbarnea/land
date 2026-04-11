#!/usr/bin/env zsh

emulate -L zsh
setopt pipefail

LAND_DIR=${1:A}
[[ -d "$LAND_DIR" ]] || exit 1

LOCK_DIR="/tmp/land-zwc-${USER}.lock"
LOCK_PID_FILE="$LOCK_DIR/pid"

acquire_lock() {
  local lock_pid

  if mkdir "$LOCK_DIR" 2>/dev/null; then
    print -r -- "$$" >| "$LOCK_PID_FILE" || {
      rmdir "$LOCK_DIR" 2>/dev/null
      exit 1
    }
    return 0
  fi

  if [[ -r "$LOCK_PID_FILE" ]]; then
    lock_pid=$(<"$LOCK_PID_FILE")
    if [[ "$lock_pid" == <-> ]] && kill -0 "$lock_pid" 2>/dev/null; then
      exit 0
    fi
  fi

  rm -rf -- "$LOCK_DIR" 2>/dev/null
  mkdir "$LOCK_DIR" 2>/dev/null || exit 0
  print -r -- "$$" >| "$LOCK_PID_FILE" || {
    rmdir "$LOCK_DIR" 2>/dev/null
    exit 1
  }
}

acquire_lock

TMP_DIR=$(mktemp -d /tmp/land-zwc.XXXXXX) || {
  rmdir "$LOCK_DIR" 2>/dev/null
  exit 1
}

cleanup() {
  rm -rf -- "$TMP_DIR" "$LOCK_DIR"
}
trap cleanup EXIT INT TERM HUP

local src zwc tmp_src
local -a sources=(
  "$LAND_DIR"/**/*.(sh|zsh)(N)
  "$LAND_DIR"/completions/_*(N)
)

for zwc in "$LAND_DIR"/**/*.zwc(N); do
  [[ "${zwc%.zwc}" == *.zwc ]] || continue
  rm -f -- "$zwc"
done

for zwc in "$LAND_DIR"/**/*.zwc(N); do
  src=${zwc%.zwc}
  [[ -e "$src" ]] || rm -f -- "$zwc"
done

for src in $sources; do
  [[ -f "$src" ]] || continue
  [[ "$src" == *.zwc ]] && continue
  zwc="${src}.zwc"
  if [[ -e "$zwc" && "$zwc" -nt "$src" ]]; then
    continue
  fi

  tmp_src=$(mktemp "$TMP_DIR/src.XXXXXX") || continue
  if ! cp -- "$src" "$tmp_src" 2>/dev/null; then
    cp "$src" "$tmp_src" || {
      rm -f -- "$tmp_src"
      continue
    }
  fi

  if zcompile -R -- "$tmp_src" >/dev/null 2>&1 && [[ -f "${tmp_src}.zwc" ]]; then
    mv -f -- "${tmp_src}.zwc" "$zwc"
  fi

  rm -f -- "$tmp_src" "${tmp_src}.zwc"
done
