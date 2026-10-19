#!/usr/bin/env bats

function setup() {
  export LAND="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  export COMMIT_TEST_REPOSITORY="$BATS_TEST_TMPDIR/repository"
  export COMMIT_TEST_HOME="$BATS_TEST_TMPDIR/home"
  export COMMIT_TEST_REQUESTS="$BATS_TEST_TMPDIR/requests"
  mkdir -p "$COMMIT_TEST_REPOSITORY" "$COMMIT_TEST_HOME/.pi/agent/prompts" "$COMMIT_TEST_HOME/bin"
  printf 'Write a commit message.\n' > "$COMMIT_TEST_HOME/.pi/agent/prompts/commit-message.md"
  git -C "$COMMIT_TEST_REPOSITORY" init -q
  git -C "$COMMIT_TEST_REPOSITORY" config user.email test@example.com
  git -C "$COMMIT_TEST_REPOSITORY" config user.name Test
  printf 'tracked before\n' > "$COMMIT_TEST_REPOSITORY/tracked.txt"
  git -C "$COMMIT_TEST_REPOSITORY" add tracked.txt
  git -C "$COMMIT_TEST_REPOSITORY" commit -qm initial
}

function commit_message() {
  zsh -fc '
    source "$LAND/init.sh" >/dev/null 2>&1 || exit 1
    export HOME="$COMMIT_TEST_HOME"
    export PATH="$COMMIT_TEST_HOME/bin:$PATH"
    if [[ "$COMMIT_TEST_ERREXIT" == 1 ]]; then
      setopt errexit errreturn
    fi
    log.debug() { :; }
    log.info() { :; }
    log.notice() { :; }
    log.warn() { print -ru2 -- "$*"; }
    log.error() { print -ru2 -- "$*"; }
    notif.info() { :; }
    pi() {
      print -r -- REQUEST >> "$COMMIT_TEST_REQUESTS"
      command cat
    }
    builtin cd "$COMMIT_TEST_REPOSITORY"
    llm-commit-msg -y "$@"
  ' -- "$@"
}

@test 'automatic selection keeps untracked filenames with spaces and newlines' {
  local branch_name
  branch_name=$(git -C "$COMMIT_TEST_REPOSITORY" branch --show-current)
  git -C "$COMMIT_TEST_REPOSITORY" config "branch.$branch_name.remote" .
  git -C "$COMMIT_TEST_REPOSITORY" config "branch.$branch_name.merge" "refs/heads/$branch_name"
  printf 'SPACED_NEW_CONTENT\n' > "$COMMIT_TEST_REPOSITORY/new file.txt"
  printf 'NEWLINE_NEW_CONTENT\n' > "$COMMIT_TEST_REPOSITORY/"$'line\nbreak.txt'

  run commit_message

  [ "$status" -eq 0 ] || { echo "Expected success: $status $output"; return 1; }
  [[ "$output" == *'SPACED_NEW_CONTENT'* && "$output" == *'NEWLINE_NEW_CONTENT'* ]] || { echo "Automatic selection split a filename: $output"; return 1; }
}

@test 'one-by-one commit messages analyze tracked and untracked files before aggregation' {
  printf 'SELECTED_NEW_CONTENT\n' > "$COMMIT_TEST_REPOSITORY/new file.txt"
  printf 'SELECTED_TRACKED_CONTENT\n' > "$COMMIT_TEST_REPOSITORY/tracked.txt"
  printf 'UNSELECTED_CONTENT\n' > "$COMMIT_TEST_REPOSITORY/unselected.txt"

  run commit_message --one-by-one -- tracked.txt 'new file.txt'

  [ "$status" -eq 0 ] || { echo "Expected success: $status $output"; return 1; }
  [[ "$output" == *'SELECTED_NEW_CONTENT'* && "$output" == *'SELECTED_TRACKED_CONTENT'* ]] || { echo "A selected file was absent from the analysis: $output"; return 1; }
  [[ "$output" != *'UNSELECTED_CONTENT'* ]] || { echo "Analyzed an unselected file: $output"; return 1; }
  [ "$(wc -l < "$COMMIT_TEST_REQUESTS" | tr -d ' ')" -eq 3 ] || { echo 'Expected one analysis per selected file and one aggregation'; return 1; }
}

@test 'commit messages include selected untracked contents without including other files' {
  printf 'SELECTED_NEW_CONTENT\n' > "$COMMIT_TEST_REPOSITORY/new file.txt"
  printf 'UNSELECTED_NEW_CONTENT\n' > "$COMMIT_TEST_REPOSITORY/unselected.txt"
  printf 'UNSELECTED_TRACKED_CONTENT\n' > "$COMMIT_TEST_REPOSITORY/tracked.txt"

  run commit_message -- 'new file.txt'

  [ "$status" -eq 0 ] || { echo "Expected success: $status $output"; return 1; }
  [[ "$output" == *'SELECTED_NEW_CONTENT'* ]] || { echo "The model did not receive the selected new file: $output"; return 1; }
  [[ "$output" != *'UNSELECTED_NEW_CONTENT'* && "$output" != *'UNSELECTED_TRACKED_CONTENT'* ]] || { echo "Included files outside the selection: $output"; return 1; }
}

@test 'directory selections include matching new files once and exclude ignored and unrelated files' {
  mkdir "$COMMIT_TEST_REPOSITORY/selected"
  printf 'before\n' > "$COMMIT_TEST_REPOSITORY/selected/tracked.txt"
  git -C "$COMMIT_TEST_REPOSITORY" add selected/tracked.txt
  git -C "$COMMIT_TEST_REPOSITORY" commit -qm directory
  printf 'DIRECTORY_TRACKED_CONTENT\n' > "$COMMIT_TEST_REPOSITORY/selected/tracked.txt"
  printf 'DIRECTORY_NEW_CONTENT\n' > "$COMMIT_TEST_REPOSITORY/selected/new.txt"
  printf 'IGNORED_CONTENT\n' > "$COMMIT_TEST_REPOSITORY/selected/ignored.txt"
  printf 'OUTSIDE_CONTENT\n' > "$COMMIT_TEST_REPOSITORY/outside.txt"
  printf 'selected/ignored.txt\n' > "$COMMIT_TEST_REPOSITORY/.git/info/exclude"

  run commit_message -- selected selected/new.txt

  [ "$status" -eq 0 ] || { echo "Expected success: $status $output"; return 1; }
  [[ "$output" == *'DIRECTORY_TRACKED_CONTENT'* && "$output" == *'DIRECTORY_NEW_CONTENT'* ]] || { echo "Omitted a directory change: $output"; return 1; }
  [[ "$output" != *'IGNORED_CONTENT'* && "$output" != *'OUTSIDE_CONTENT'* ]] || { echo "Included an excluded file: $output"; return 1; }
  [ "$(printf '%s' "$output" | rg -o DIRECTORY_NEW_CONTENT | wc -l | tr -d ' ')" -eq 1 ] || { echo "Duplicated the new file: $output"; return 1; }
}

@test 'staged additions and tracked deletions still compare against HEAD in both modes' {
  printf 'STAGED_NEW_CONTENT\n' > "$COMMIT_TEST_REPOSITORY/staged.txt"
  git -C "$COMMIT_TEST_REPOSITORY" add staged.txt
  rm "$COMMIT_TEST_REPOSITORY/tracked.txt"
  local mode
  for mode in false true; do
    run commit_message "--one-by-one=$mode" -- staged.txt tracked.txt

    [ "$status" -eq 0 ] || { echo "Expected success in mode $mode: $status $output"; return 1; }
    [[ "$output" == *'STAGED_NEW_CONTENT'* && "$output" == *'tracked before'* && "$output" == *'deleted patch'* ]] || { echo "Lost a staged addition or tracked deletion: $output"; return 1; }
  done
}

@test 'Git failures stop both modes before any model request' {
  git -C "$COMMIT_TEST_REPOSITORY" update-ref -d HEAD
  local mode
  for mode in false true; do
    run commit_message "--one-by-one=$mode" -- tracked.txt

    [ "$status" -ne 0 ] || { echo "Masked a failed HEAD comparison in mode $mode: $output"; return 1; }
    [ ! -e "$COMMIT_TEST_REQUESTS" ] || { echo 'Sent an incomplete diff to the model'; return 1; }
  done
}

@test 'an empty failed no-index comparison is not mistaken for a successful difference' {
  printf 'new content\n' > "$COMMIT_TEST_REPOSITORY/new.txt"
  local git_binary
  git_binary=$(command -v git)
  printf '#!/bin/sh\ncase "$*" in *--no-index*) printf "injected read failure\\n" >&2; exit 1;; esac\nexec "%s" "$@"\n' "$git_binary" > "$COMMIT_TEST_HOME/bin/git"
  chmod +x "$COMMIT_TEST_HOME/bin/git"

  run commit_message -- new.txt

  [ "$status" -eq 1 ] || { echo "Expected the read failure: $status $output"; return 1; }
  [ ! -e "$COMMIT_TEST_REQUESTS" ] || { echo 'Sent a failed comparison to the model'; return 1; }
}

@test 'new-file difference status remains successful under errexit and errreturn' {
  printf 'STRICT_SHELL_NEW_CONTENT\n' > "$COMMIT_TEST_REPOSITORY/new.txt"

  COMMIT_TEST_ERREXIT=1 run commit_message -- new.txt

  [ "$status" -eq 0 ] || { echo "Treated Git difference status 1 as an error: $status $output"; return 1; }
  [[ "$output" == *'STRICT_SHELL_NEW_CONTENT'* ]] || { echo "Lost the new file under strict shell options: $output"; return 1; }
}

@test 'empty and symlink untracked files reach the model without changing the index' {
  touch "$COMMIT_TEST_REPOSITORY/empty.txt"
  ln -s target.txt "$COMMIT_TEST_REPOSITORY/link.txt"
  git -C "$COMMIT_TEST_REPOSITORY" ls-files --stage > "$BATS_TEST_TMPDIR/index-before"

  run commit_message -- empty.txt link.txt

  [ "$status" -eq 0 ] || { echo "Expected success: $status $output"; return 1; }
  [[ "$output" == *'empty.txt'* && "$output" == *'link.txt'* && "$output" == *'target.txt'* ]] || { echo "Lost an empty file or symlink: $output"; return 1; }
  git -C "$COMMIT_TEST_REPOSITORY" ls-files --stage > "$BATS_TEST_TMPDIR/index-after"
  cmp "$BATS_TEST_TMPDIR/index-before" "$BATS_TEST_TMPDIR/index-after" || { echo 'Changed the real Git index'; return 1; }
}
