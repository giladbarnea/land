#!/usr/bin/env bats

function setup() {
  export LAND="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export COMMIT_TEST_CALLS="$BATS_TEST_TMPDIR/calls"
  export COMMIT_TEST_REPOSITORY="$BATS_TEST_TMPDIR/repository"
  export COMMIT_TEST_HOME="$BATS_TEST_TMPDIR/home"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  mkdir -p "$COMMIT_TEST_REPOSITORY/src" "$COMMIT_TEST_HOME/.pi/agent/prompts"
  printf 'Write a commit message.\n' > "$COMMIT_TEST_HOME/.pi/agent/prompts/commit-message.md"
  git -C "$COMMIT_TEST_REPOSITORY" init -q
  git -C "$COMMIT_TEST_REPOSITORY" config user.name Test
  git -C "$COMMIT_TEST_REPOSITORY" config user.email test@example.com
  printf 'old readme\n' > "$COMMIT_TEST_REPOSITORY/README.md"
  printf 'old app\n' > "$COMMIT_TEST_REPOSITORY/src/app.py"
  git -C "$COMMIT_TEST_REPOSITORY" add .
  git -C "$COMMIT_TEST_REPOSITORY" commit -qm initial
}

function real_commit() {
  zsh -fc '
    source "$LAND/init.sh" >/dev/null 2>&1 || exit 1
    export HOME="$COMMIT_TEST_HOME"
    input() { print -ru2 UNEXPECTED_PROMPT; return 98; }
    pi() {
      command cat > "$COMMIT_TEST_CALLS"
      [[ "$COMMIT_TEST_MODEL_FAILURE" != 1 ]] || return 7
      print -r -- "Update repository"
    }
    builtin cd "$COMMIT_TEST_REPOSITORY/src"
    gac -y "$@"
  ' -- "$@"
}

@test 'gac with no message stages the whole repository from a subdirectory then describes the index' {
  printf 'ROOT_CHANGE\n' > "$COMMIT_TEST_REPOSITORY/README.md"
  printf 'APP_CHANGE\n' > "$COMMIT_TEST_REPOSITORY/src/app.py"
  printf 'NEW_FILE\n' > "$COMMIT_TEST_REPOSITORY/new file.txt"

  run real_commit

  [ "$status" -eq 0 ] || { echo "Generated commit failed: $output"; return 1; }
  [ "$(git -C "$COMMIT_TEST_REPOSITORY" log -1 --format=%s)" = 'Update repository' ] || { echo 'Did not use the generated message'; return 1; }
  [ -z "$(git -C "$COMMIT_TEST_REPOSITORY" status --porcelain)" ] || { echo 'Committed only the subdirectory'; return 1; }
  for content in ROOT_CHANGE APP_CHANGE NEW_FILE; do
    rg -q "$content" "$COMMIT_TEST_CALLS" || { echo "Model missed $content"; return 1; }
  done
}

@test 'explicit gac paths retain unrelated staged changes and exclude their unstaged versions' {
  printf 'STAGED_README\n' > "$COMMIT_TEST_REPOSITORY/README.md"
  git -C "$COMMIT_TEST_REPOSITORY" add README.md
  printf 'UNSTAGED_README\n' > "$COMMIT_TEST_REPOSITORY/README.md"
  printf 'APP_CHANGE\n' > "$COMMIT_TEST_REPOSITORY/src/app.py"

  run real_commit -- app.py

  [ "$status" -eq 0 ] || { echo "Explicit commit failed: $output"; return 1; }
  [ "$(git -C "$COMMIT_TEST_REPOSITORY" show HEAD:README.md)" = STAGED_README ] || { echo 'Committed the wrong README version'; return 1; }
  rg -q STAGED_README "$COMMIT_TEST_CALLS" && ! rg -q UNSTAGED_README "$COMMIT_TEST_CALLS" || { echo 'Model described the worktree instead of the index'; return 1; }
  [ "$(git -C "$COMMIT_TEST_REPOSITORY" show HEAD:src/app.py)" = APP_CHANGE ] || { echo 'Omitted the selected path'; return 1; }
}

@test 'a supplied message avoids the model and a model failure prevents commit' {
  printf 'APP_CHANGE\n' > "$COMMIT_TEST_REPOSITORY/src/app.py"
  run real_commit 'Manual message' -- app.py

  [ "$status" -eq 0 ] && [ ! -e "$COMMIT_TEST_CALLS" ] || { echo "Supplied message unexpectedly used the model: $output"; return 1; }
  local previous_head
  previous_head=$(git -C "$COMMIT_TEST_REPOSITORY" rev-parse HEAD)
  printf 'NEXT_CHANGE\n' > "$COMMIT_TEST_REPOSITORY/src/app.py"

  COMMIT_TEST_MODEL_FAILURE=1 run real_commit

  [ "$status" -ne 0 ] || { echo 'Committed despite model failure'; return 1; }
  [ "$(git -C "$COMMIT_TEST_REPOSITORY" rev-parse HEAD)" = "$previous_head" ] || { echo 'Changed HEAD after model failure'; return 1; }
  [ "$(git -C "$COMMIT_TEST_REPOSITORY" show :src/app.py)" = NEXT_CHANGE ] || { echo 'Failed generation should leave changes staged'; return 1; }
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
    git.stage() { print -r -- "git add -A -- $*" >> "$COMMIT_TEST_CALLS"; }
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
  rg -q '^git add -A -- $' "$COMMIT_TEST_CALLS" || { echo 'Did not stage the requested changes'; return 1; }
  rg -q '^git commit --quiet -m Keep this commit message$' "$COMMIT_TEST_CALLS" || { echo 'Changed the commit message'; return 1; }
  rg -q '^git push --quiet$' "$COMMIT_TEST_CALLS" || { echo 'Did not reach the requested push'; return 1; }
}
