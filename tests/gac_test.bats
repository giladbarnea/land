#!/usr/bin/env bats

function setup() {
  export LAND="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export COMMIT_TEST_CALLS="$BATS_TEST_TMPDIR/calls"
}

function guarded_commit() {
  zsh -fc '
    source "$LAND/init.sh" >/dev/null 2>&1 || exit 1
    setopt extendedglob
    git_current_branch() { print -r -- main; }
    log.debug() { :; }
    log.error() { print -ru2 -- "$*"; }
    log.fatal() { print -ru2 -- "$*"; }
    input() { print -r -- PROMPT >> "$COMMIT_TEST_CALLS"; return 98; }
    vex() { print -r -- "$*" >> "$COMMIT_TEST_CALLS"; }
    git() { print -r -- "git $*" >> "$COMMIT_TEST_CALLS"; }
    failed_message() { gacp -y "$(false)"; }
    "$@"
  ' -- "$@"
}

@test 'a failed message substitution does not read stdin stage commit or push' {
  run guarded_commit failed_message <<< 'STDIN_MUST_NOT_BECOME_A_COMMIT_MESSAGE'

  [ "$status" -ne 0 ] || { echo "Accepted a failed message substitution: $output"; return 1; }
  [[ "$output" == *'empty'* ]] || { echo "Expected a clear empty-message error: $output"; return 1; }
  [ ! -e "$COMMIT_TEST_CALLS" ] || { echo 'Prompted or invoked Git after the message failed'; return 1; }
}

@test 'blank shorthand messages fail before staging in gac and gacp' {
  local command message
  for command in gac gacp; do
    for message in '' '   ' $'\n\t\n'; do
      run guarded_commit "$command" -y "$message" <<< 'STDIN_MUST_NOT_BECOME_A_COMMIT_MESSAGE'

      [ "$status" -ne 0 ] || { echo "Accepted a blank message in $command: $output"; return 1; }
      [ ! -e "$COMMIT_TEST_CALLS" ] || { echo "Invoked Git for a blank message in $command"; return 1; }
    done
  done
}

@test 'a valid shorthand message still reaches commit and push' {
  run guarded_commit gacp -y '  Keep this commit message  '

  [ "$status" -eq 0 ] || { echo "Rejected a valid message: $status $output"; return 1; }
  rg -q '^git add -- \.$' "$COMMIT_TEST_CALLS" || { echo 'Did not stage the requested changes'; return 1; }
  rg -q '^git commit --quiet -m Keep this commit message$' "$COMMIT_TEST_CALLS" || { echo 'Changed the commit message'; return 1; }
  rg -q '^git push --quiet$' "$COMMIT_TEST_CALLS" || { echo 'Did not reach the requested push'; return 1; }
}
