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
    builtin cd "${COMMIT_TEST_DIRECTORY:-$COMMIT_TEST_REPOSITORY}"
    if [[ -n "$COMMIT_TEST_CHOICE" ]]; then
      is_human() { return 0; }
      input() { print -r -- "$COMMIT_TEST_CHOICE"; }
      llm-commit-msg "$@"
    else
      input() { print -ru2 UNEXPECTED_PROMPT; return 98; }
      llm-commit-msg -y "$@"
    fi
    commit_status=$?
    print -ru2 -- "CALLER_DIRECTORY=$PWD"
    exit $commit_status
  ' -- "$@"
}

@test 'preview preserves the index timestamp so same-size edits are not missed' {
  git -C "$COMMIT_TEST_REPOSITORY" config core.trustctime false
  git -C "$COMMIT_TEST_REPOSITORY" config core.checkStat minimal
  touch -t 202601010000 "$COMMIT_TEST_REPOSITORY/tracked.txt"
  git -C "$COMMIT_TEST_REPOSITORY" add tracked.txt
  touch -t 202601010000 "$COMMIT_TEST_REPOSITORY/.git/index"
  printf 'TRACKED_CHANGE\n' > "$COMMIT_TEST_REPOSITORY/tracked.txt"
  touch -t 202601010000 "$COMMIT_TEST_REPOSITORY/tracked.txt"

  run commit_message

  [ "$status" -eq 0 ] && [[ "$output" == *TRACKED_CHANGE* ]] || { echo "The index copy hid a same-size edit: $output"; return 1; }
}

@test 'explicit paths preview staging while retaining unrelated staged content only' {
  printf 'STAGED_README\n' > "$COMMIT_TEST_REPOSITORY/README.md"
  git -C "$COMMIT_TEST_REPOSITORY" add README.md
  printf 'UNSTAGED_README\n' > "$COMMIT_TEST_REPOSITORY/README.md"
  printf 'SELECTED_APP\n' > "$COMMIT_TEST_REPOSITORY/tracked.txt"
  cp "$COMMIT_TEST_REPOSITORY/.git/index" "$BATS_TEST_TMPDIR/index-before"

  run commit_message -- tracked.txt

  [ "$status" -eq 0 ] || { echo "Preview failed: $output"; return 1; }
  [[ "$output" == *STAGED_README* && "$output" == *SELECTED_APP* && "$output" != *UNSTAGED_README* ]] || { echo "Preview does not match git add -- tracked.txt: $output"; return 1; }
  cmp "$COMMIT_TEST_REPOSITORY/.git/index" "$BATS_TEST_TMPDIR/index-before" || { echo 'Preview changed the real index'; return 1; }
  local preview="$output"
  git -C "$COMMIT_TEST_REPOSITORY" add -A -- tracked.txt

  run commit_message --cached

  [ "$status" -eq 0 ] && [ "$output" = "$preview" ] || { echo "Preview differs from the actual staged changes: $output"; return 1; }
}

@test 'menu selections combine classes without adding unrelated modifications' {
  printf 'STAGED_README\n' > "$COMMIT_TEST_REPOSITORY/README.md"
  git -C "$COMMIT_TEST_REPOSITORY" add README.md
  printf 'UNSTAGED_TRACKED\n' > "$COMMIT_TEST_REPOSITORY/tracked.txt"
  printf 'UNTRACKED_LITERAL\n' > "$COMMIT_TEST_REPOSITORY/[a].txt"
  cp "$COMMIT_TEST_REPOSITORY/.git/index" "$BATS_TEST_TMPDIR/index-before"

  COMMIT_TEST_CHOICE=su run commit_message

  [ "$status" -eq 0 ] || { echo "Combined menu choices failed: $output"; return 1; }
  [[ "$output" == *STAGED_README* && "$output" == *UNTRACKED_LITERAL* && "$output" != *UNSTAGED_TRACKED* ]] || { echo "Wrong menu selection: $output"; return 1; }
  cmp "$COMMIT_TEST_REPOSITORY/.git/index" "$BATS_TEST_TMPDIR/index-before" || { echo 'Menu preview changed the real index'; return 1; }
}

@test 'the staged menu handles renames and already-staged deletions' {
  git -C "$COMMIT_TEST_REPOSITORY" mv tracked.txt moved.txt

  COMMIT_TEST_CHOICE=s run commit_message

  [ "$status" -eq 0 ] && [[ "$output" == *'rename from tracked.txt'* && "$output" == *'rename to moved.txt'* ]] || { echo "Tried to restage a removed rename source: $output"; return 1; }

  git -C "$COMMIT_TEST_REPOSITORY" rm -qf moved.txt
  printf 'UNSELECTED_NEW_FILE\n' > "$COMMIT_TEST_REPOSITORY/unselected.txt"
  COMMIT_TEST_CHOICE=s run commit_message

  [ "$status" -eq 0 ] && [[ "$output" == *'deleted patch'* && "$output" != *UNSELECTED_NEW_FILE* ]] || { echo "Empty staging selection accidentally staged everything: $output"; return 1; }
}

@test 'paths after the separator are never parsed as options' {
  printf 'FLAG_FILE\n' > "$COMMIT_TEST_REPOSITORY/--one-by-one"

  run commit_message -- --one-by-one

  [ "$status" -eq 0 ] && [[ "$output" == *FLAG_FILE* ]] || { echo "Parsed a filename as an option: $output"; return 1; }
  [ "$(wc -l < "$COMMIT_TEST_REQUESTS" | tr -d ' ')" -eq 1 ] || { echo 'Filename enabled one-by-one mode'; return 1; }
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

  run commit_message -- selected

  [ "$status" -eq 0 ] || { echo "Expected success: $status $output"; return 1; }
  [[ "$output" == *'DIRECTORY_TRACKED_CONTENT'* && "$output" == *'DIRECTORY_NEW_CONTENT'* ]] || { echo "Omitted a directory change: $output"; return 1; }
  [[ "$output" != *'IGNORED_CONTENT'* && "$output" != *'OUTSIDE_CONTENT'* ]] || { echo "Included an excluded file: $output"; return 1; }

  run commit_message -- selected selected/new.txt

  [ "$(printf '%s' "$output" | rg -o DIRECTORY_NEW_CONTENT | wc -l | tr -d ' ')" -eq 1 ] || { echo "Duplicated the new file: $output"; return 1; }
}

@test 'automatic selection from a subdirectory includes staged changes anywhere and spaced names' {
  mkdir "$COMMIT_TEST_REPOSITORY/src"
  printf 'before\n' > "$COMMIT_TEST_REPOSITORY/src/code.txt"
  git -C "$COMMIT_TEST_REPOSITORY" add src/code.txt
  git -C "$COMMIT_TEST_REPOSITORY" commit -qm src
  printf 'STAGED_SUBDIRECTORY_CONTENT\n' > "$COMMIT_TEST_REPOSITORY/src/code.txt"
  printf 'STAGED_ROOT_SPACED_CONTENT\n' > "$COMMIT_TEST_REPOSITORY/my notes.txt"
  git -C "$COMMIT_TEST_REPOSITORY" add src/code.txt 'my notes.txt'

  COMMIT_TEST_DIRECTORY="$COMMIT_TEST_REPOSITORY/src" run commit_message

  [ "$status" -eq 0 ] || { echo "Expected success: $status $output"; return 1; }
  [[ "$output" == *'STAGED_SUBDIRECTORY_CONTENT'* ]] || { echo "Lost a staged change when run from a subdirectory: $output"; return 1; }
  [[ "$output" == *'STAGED_ROOT_SPACED_CONTENT'* ]] || { echo "Lost a staged file with a space in its name: $output"; return 1; }
  [[ "$output" == *"CALLER_DIRECTORY=$COMMIT_TEST_REPOSITORY/src"* ]] || { echo "Changed the caller's directory: $output"; return 1; }
}

@test 'automatic selection includes both names of a staged rename' {
  git -C "$COMMIT_TEST_REPOSITORY" mv tracked.txt moved.txt

  run commit_message

  [ "$status" -eq 0 ] || { echo "Expected success: $status $output"; return 1; }
  [[ "$output" == *'rename from tracked.txt'* && "$output" == *'rename to moved.txt'* ]] || { echo "Lost Git's rename metadata: $output"; return 1; }
  [[ "$output" != *'tracked before'* ]] || { echo "Repeated the entire renamed file instead of describing the rename: $output"; return 1; }
}

@test 'the first commit in a new repository compares staged files with an empty tree' {
  export COMMIT_TEST_DIRECTORY="$BATS_TEST_TMPDIR/new-repository"
  git init -q "$COMMIT_TEST_DIRECTORY"
  printf 'FIRST_COMMIT_CONTENT\n' > "$COMMIT_TEST_DIRECTORY/first.txt"
  git -C "$COMMIT_TEST_DIRECTORY" add first.txt
  local mode
  for mode in false true; do
    run commit_message "--one-by-one=$mode"

    [ "$status" -eq 0 ] || { echo "The first commit failed in mode $mode: $status $output"; return 1; }
    [[ "$output" == *'FIRST_COMMIT_CONTENT'* && "$output" == *'added patch'* ]] || { echo "Did not describe the first file in mode $mode: $output"; return 1; }
  done
}

@test 'untracked nested repositories are described without reading their files' {
  git init -q "$COMMIT_TEST_REPOSITORY/vendor-clone"
  printf 'NESTED_CONTENT_MUST_NOT_BE_READ\n' > "$COMMIT_TEST_REPOSITORY/vendor-clone/inner.txt"
  git -C "$COMMIT_TEST_REPOSITORY/vendor-clone" add inner.txt
  git -C "$COMMIT_TEST_REPOSITORY/vendor-clone" -c user.name=Test -c user.email=test@example.com commit -qm initial
  printf 'TRACKED_CHANGE\n' > "$COMMIT_TEST_REPOSITORY/tracked.txt"
  local mode
  for mode in false true; do
    run commit_message "--one-by-one=$mode"

    [ "$status" -eq 0 ] || { echo "A nested repository failed in mode $mode: $status $output"; return 1; }
    [[ "$output" == *'vendor-clone'* && "$output" == *'Subproject commit'* && "$output" == *'TRACKED_CHANGE'* ]] || { echo "Lost the nested repository or the tracked change: $output"; return 1; }
    [[ "$output" != *'NESTED_CONTENT_MUST_NOT_BE_READ'* ]] || { echo "Read files inside the nested repository: $output"; return 1; }
  done
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
  local blob
  blob=$(git -C "$COMMIT_TEST_REPOSITORY" rev-parse HEAD:tracked.txt)
  rm -f "$COMMIT_TEST_REPOSITORY/.git/objects/${blob:0:2}/${blob:2}"
  printf 'changed so Git must read the missing object\n' > "$COMMIT_TEST_REPOSITORY/tracked.txt"
  local mode
  for mode in false true; do
    run commit_message "--one-by-one=$mode" -- tracked.txt

    [ "$status" -ne 0 ] || { echo "Masked a failed HEAD comparison in mode $mode: $output"; return 1; }
    [ ! -e "$COMMIT_TEST_REQUESTS" ] || { echo 'Sent an incomplete diff to the model'; return 1; }
  done
}

@test 'Git staging errors stop before any model request and preserve the real index' {
  cp "$COMMIT_TEST_REPOSITORY/.git/index" "$BATS_TEST_TMPDIR/index-before"
  git init -q "$COMMIT_TEST_REPOSITORY/empty-clone"

  run commit_message

  [ "$status" -ne 0 ] || { echo "Accepted a repository that Git cannot stage: $output"; return 1; }
  [ ! -e "$COMMIT_TEST_REQUESTS" ] || { echo 'Sent an unstaged preview to the model'; return 1; }
  cmp "$COMMIT_TEST_REPOSITORY/.git/index" "$BATS_TEST_TMPDIR/index-before" || { echo 'Changed the real index on failure'; return 1; }
}

@test 'new-file difference status remains successful under errexit and errreturn' {
  printf 'STRICT_SHELL_NEW_CONTENT\n' > "$COMMIT_TEST_REPOSITORY/new.txt"

  COMMIT_TEST_ERREXIT=1 run commit_message -- new.txt

  [ "$status" -eq 0 ] || { echo "Treated Git difference status 1 as an error: $status $output"; return 1; }
  [[ "$output" == *'STRICT_SHELL_NEW_CONTENT'* ]] || { echo "Lost the new file under strict shell options: $output"; return 1; }
}

@test 'untracked links to existing directories describe the link without reading its contents' {
  mkdir "$COMMIT_TEST_REPOSITORY/target-directory"
  printf 'DIRECTORY_CONTENT_MUST_NOT_BE_READ\n' > "$COMMIT_TEST_REPOSITORY/target-directory/secret.txt"
  ln -s target-directory "$COMMIT_TEST_REPOSITORY/relative-link"
  ln -s "$COMMIT_TEST_REPOSITORY/target-directory" "$COMMIT_TEST_REPOSITORY/absolute-link"
  git -C "$COMMIT_TEST_REPOSITORY" ls-files --stage > "$BATS_TEST_TMPDIR/index-before"
  local mode
  for mode in false true; do
    run commit_message "--one-by-one=$mode" -- relative-link absolute-link

    [ "$status" -eq 0 ] || { echo "Directory symlinks failed in mode $mode: $status $output"; return 1; }
    [[ "$output" == *'relative-link'* && "$output" == *'absolute-link'* && "$output" == *'target-directory'* ]] || { echo "Missing link names or targets: $output"; return 1; }
    [[ "$output" == *'120000'* && "$output" != *'DIRECTORY_CONTENT_MUST_NOT_BE_READ'* ]] || { echo "Compared the directory instead of the link: $output"; return 1; }
  done
  git -C "$COMMIT_TEST_REPOSITORY" ls-files --stage > "$BATS_TEST_TMPDIR/index-after"
  cmp "$BATS_TEST_TMPDIR/index-before" "$BATS_TEST_TMPDIR/index-after" || { echo 'Changed the real Git index'; return 1; }
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
