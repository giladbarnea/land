#!/usr/bin/env zsh
setopt errreturn
zmodload zsh/zpty
export LAND=${LAND:-${0:A:h:h}}
local temporary_directory=$(mktemp -d)
export SKILLS_TERMINAL_TEST_ROOT="$temporary_directory"
trap 'zpty -d skills_sync 2>/dev/null; rm -rf -- "$temporary_directory"' EXIT

print -r -- '
source "$LAND/skills.sh"
typeset -g +x IS_HUMAN="$SKILLS_TERMINAL_TEST_HUMAN"
setopt pipefail
case "$SKILLS_TERMINAL_TEST_OUTPUT" in
  pipe) skills sync "$SKILLS_TERMINAL_TEST_ROOT/source" "$SKILLS_TERMINAL_TEST_ROOT/target" | tee "$SKILLS_TERMINAL_TEST_ROOT/output" ;;
  file) skills sync "$SKILLS_TERMINAL_TEST_ROOT/source" "$SKILLS_TERMINAL_TEST_ROOT/target" > "$SKILLS_TERMINAL_TEST_ROOT/output" ;;
  input) print context | skills sync "$SKILLS_TERMINAL_TEST_ROOT/source" "$SKILLS_TERMINAL_TEST_ROOT/target" > "$SKILLS_TERMINAL_TEST_ROOT/output" ;;
esac
print -r -- "$?" > "$SKILLS_TERMINAL_TEST_ROOT/result"
' > "$temporary_directory/run.zsh"

check_session() {
  local label="$1" human="$2" output_mode="$3" answer="$4" keep_link="$5"
  local link_path="$temporary_directory/target/skills/retired skill"
  rm -rf -- "$temporary_directory/source" "$temporary_directory/target"
  rm -f -- "$temporary_directory/result" "$temporary_directory/output"
  mkdir -p "$temporary_directory/source/skills/current" "$temporary_directory/target/skills"
  ln -s "$temporary_directory/missing source" "$link_path"
  zpty skills_sync env SKILLS_TERMINAL_TEST_HUMAN="$human" SKILLS_TERMINAL_TEST_OUTPUT="$output_mode" zsh -f -i
  zpty -w skills_sync 'source "$SKILLS_TERMINAL_TEST_ROOT/run.zsh"'

  local chunk terminal_output='' answered=false
  local -i step
  for step in {1..100}; do
    if zpty -r -t skills_sync chunk; then
      terminal_output+="$chunk"
    fi
    if [[ "$human" = true && "$answered" = false && "$terminal_output" == *'[y/N] '* ]]; then
      zpty -w -n skills_sync "$answer"$'\n'
      answered=true
    fi
    [[ ! -f "$temporary_directory/result" ]] || break
    sleep 0.05
  done
  while zpty -r -t skills_sync chunk; do terminal_output+="$chunk"; done
  zpty -d skills_sync
  [[ -f "$temporary_directory/result" ]] || { print -ru2 -- "FAIL: $label timed out: $terminal_output"; return 1; }
  [[ "$(<"$temporary_directory/result")" = 0 ]] || { print -ru2 -- "FAIL: $label failed: $terminal_output"; return 1; }

  if [[ "$keep_link" = true ]]; then
    [[ -L "$link_path" ]] || { print -ru2 -- "FAIL: $label removed $link_path without approval"; return 1; }
  else
    [[ ! -L "$link_path" ]] || { print -ru2 -- "FAIL: $label kept $link_path after approval: $terminal_output"; return 1; }
  fi
  [[ -L "$temporary_directory/target/skills/current" ]] || { print -ru2 -- "FAIL: $label did not sync the current skill"; return 1; }
  [[ "$(<"$temporary_directory/output")" != *'[y/N]'* ]] || { print -ru2 -- "FAIL: $label wrote its prompt into command output"; return 1; }

  if [[ "$human" = true ]]; then
    [[ "$answered" = true ]] || { print -ru2 -- "FAIL: $label did not ask for confirmation: $terminal_output"; return 1; }
  else
    [[ "$terminal_output" != *'[y/N]'* ]] || { print -ru2 -- "FAIL: $label prompted without a human session"; return 1; }
    [[ "$terminal_output" == *"Kept obsolete link $link_path because removal requires interactive confirmation."* ]] || {
      print -ru2 -- "FAIL: $label did not explain why it kept the actual link path: $terminal_output"
      return 1
    }
  fi
  print -r -- "PASS: $label"
}

check_session 'human with piped output' true pipe y false
check_session 'human with redirected output' true file y false
check_session 'human with piped input and redirected output' true input y false
check_session 'human declines removal' true pipe n true
check_session 'human gives an empty answer' true pipe '' true
check_session 'terminal input ends without an answer' true pipe $'\x04' true
check_session 'unattended session with a terminal' false pipe '' true
