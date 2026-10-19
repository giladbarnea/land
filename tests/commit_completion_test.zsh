#!/usr/bin/env zsh
# Press Tab in a real zsh PTY and check the resulting command buffer without executing it.
setopt errreturn
zmodload zsh/zpty
export LAND=${LAND:-${0:A:h:h}}
local temporary_directory=$(mktemp -d)
export COMPLETION_RESULT="$temporary_directory/result"
trap 'zpty -d completion 2>/dev/null; rm -rf -- "$temporary_directory"' EXIT
zpty completion zsh -f -i
zpty -w completion 'builtin cd "$LAND"; fpath=("$LAND/completions" $fpath); autoload -Uz compinit; compinit -u -D; source "$LAND/completions/_llm"; source "$LAND/completions/__git"; dump_buffer() { print -r -- "$BUFFER" > "$COMPLETION_RESULT"; BUFFER=""; zle reset-prompt; }; zle -N dump_buffer; bindkey "^X^B" dump_buffer; PROMPT="> "; print READY > "$COMPLETION_RESULT"'

wait_result() {
  local chunk
  local -i step
  for step in {1..100}; do
    zpty -r -t completion chunk || true
    [[ ! -f "$COMPLETION_RESULT" ]] || return 0
    sleep 0.05
  done
  print -u2 'Completion timed out'
  return 1
}

check_completion() {
  rm -f "$COMPLETION_RESULT"
  zpty -w -n completion "$1"$'\t\x18\x02'
  wait_result || return $?
  local actual="$(<"$COMPLETION_RESULT")"
  [[ "${actual% }" == "$2" ]] || { print -ru2 -- "FAIL: $1 -> ${(qq)actual}, expected ${(qq)2}"; return 1; }
  print -r -- "PASS: $1 -> $2"
}

wait_result
check_completion 'llm-commit-msg -y --ca' 'llm-commit-msg -y --cached'
check_completion 'llm-commit-msg -y --max-d' 'llm-commit-msg -y --max-diff-length='
check_completion 'llm-commit-msg --one-by-one=f' 'llm-commit-msg --one-by-one=false'
check_completion 'llm-commit-msg -y -- comp' 'llm-commit-msg -y -- completions/'
check_completion 'gac -y --am' 'gac -y --amend'
check_completion 'gacp "manual message" --am' 'gacp "manual message" --amend'
check_completion 'gac --yes -y --am' 'gac --yes -y --amend'
check_completion 'gac -y -- comp' 'gac -y -- completions/'
check_completion 'gsd --only-line-ranges --num' 'gsd --only-line-ranges --numstat'
check_completion 'gsd --stdin --on' 'gsd --stdin --only-line-ranges'
