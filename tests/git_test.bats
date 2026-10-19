#!/usr/bin/env bats

function setup() {
  export LAND="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  export GIT_TEST_REPOSITORY="$BATS_TEST_TMPDIR/repository"
  mkdir "$GIT_TEST_REPOSITORY"
  git -C "$GIT_TEST_REPOSITORY" init -q
  git -C "$GIT_TEST_REPOSITORY" config user.email test@example.com
  git -C "$GIT_TEST_REPOSITORY" config user.name Test
  printf 'tracked before\n' > "$GIT_TEST_REPOSITORY/tracked.txt"
  git -C "$GIT_TEST_REPOSITORY" add tracked.txt
  git -C "$GIT_TEST_REPOSITORY" commit -qm initial
}

function git_structured_diff() {
  zsh -fc '
    alias gsd=true g=true gd=true glola=true gloga=true gp=true
    alias gstaa=true gstc=true gstd=true gstl=true gstp=true gsts=true gstu=true gstall=true
    alias gignore=true gunignore=true
    source "$LAND/git.sh"
    is_piped() { [[ -p /dev/stdin || -f /dev/stdin ]]; }
    cd "$GIT_TEST_REPOSITORY"
    git-structured-diff -y "$@"
  ' -- "$@"
}

function assert_git_output() {
  local expected_status=0 actual_status=0
  git -C "$GIT_TEST_REPOSITORY" --no-pager diff "$@" > "$BATS_TEST_TMPDIR/expected" 2> "$BATS_TEST_TMPDIR/expected-error" || expected_status=$?
  git_structured_diff "$@" > "$BATS_TEST_TMPDIR/actual" 2> "$BATS_TEST_TMPDIR/actual-error" || actual_status=$?
  [ "$actual_status" -eq "$expected_status" ] || { echo "Wrong exit status for $*: $actual_status, expected $expected_status"; return 1; }
  cmp "$BATS_TEST_TMPDIR/expected" "$BATS_TEST_TMPDIR/actual" || { echo "Changed Git output for $*"; return 1; }
  cmp "$BATS_TEST_TMPDIR/expected-error" "$BATS_TEST_TMPDIR/actual-error" || { echo "Changed Git stderr for $*"; return 1; }
}

@test 'git-structured-diff preserves non-patch output byte for byte including NULs' {
  local strange_name=$'name\twith\nquotes".txt'
  printf 'before\n' > "$GIT_TEST_REPOSITORY/$strange_name"
  git -C "$GIT_TEST_REPOSITORY" add -- "$strange_name"
  git -C "$GIT_TEST_REPOSITORY" commit -qm unusual-name
  printf 'after\n' > "$GIT_TEST_REPOSITORY/$strange_name"
  printf 'tracked after\n' > "$GIT_TEST_REPOSITORY/tracked.txt"
  local format
  for format in --stat --shortstat --numstat --name-only --name-status --raw --summary; do
    assert_git_output "$format" HEAD || return 1
    assert_git_output "$format" -z HEAD || return 1
  done
}

@test 'git-structured-diff preserves alternate diff formats instead of misparsing them' {
  printf 'tracked after\n' > "$GIT_TEST_REPOSITORY/tracked.txt"
  local format
  for format in --word-diff=plain --word-diff=porcelain --color=always '--line-prefix=> ' '--output-indicator-new=>'; do
    assert_git_output "$format" HEAD || return 1
  done
}

@test 'git-structured-diff keeps full paths and respects the path separator' {
  printf 'before\n' > "$GIT_TEST_REPOSITORY/space name.txt"
  printf 'before\n' > "$GIT_TEST_REPOSITORY/--only-line-ranges"
  git -C "$GIT_TEST_REPOSITORY" add -- 'space name.txt' --only-line-ranges
  git -C "$GIT_TEST_REPOSITORY" commit -qm paths
  printf 'after\n' > "$GIT_TEST_REPOSITORY/space name.txt"
  printf 'after\n' > "$GIT_TEST_REPOSITORY/--only-line-ranges"

  run git_structured_diff HEAD -- 'space name.txt'
  [[ "$output" == *'<space name.txt added=0 modified=1 deleted=0>'* ]] || { echo "Truncated file path: $output"; return 1; }
  [[ "$output" != *'only-line-ranges'* ]] || { echo "Included an unselected file: $output"; return 1; }

  run git_structured_diff HEAD -- --only-line-ranges
  [[ "$output" == *'1 │after'* ]] || { echo "Treated a filename as an option: $output"; return 1; }

  run git_structured_diff '--src-prefix=[SOURCE] ' '--dst-prefix=[DESTINATION] ' HEAD -- 'space name.txt'
  [[ "$output" == *'<[DESTINATION] space name.txt added=0 modified=1 deleted=0>'* ]] || { echo "Lost a custom prefix or path: $output"; return 1; }
}

@test 'git-structured-diff labels blank-line changes instead of hiding them' {
  printf 'tracked before\n\n' > "$GIT_TEST_REPOSITORY/tracked.txt"

  run git_structured_diff HEAD

  [[ "$output" == *'<tracked.txt added=1 modified=0 deleted=0>'* ]] || { echo "Did not count the blank-line addition: $output"; return 1; }
  [[ "$output" == *'<added patch 1/1 start of block: line 2>'* ]] || { echo "Did not locate the blank-line addition: $output"; return 1; }
}

@test 'git-structured-diff does not strip real path components with no-prefix output' {
  mkdir "$GIT_TEST_REPOSITORY/a"
  printf 'before\n' > "$GIT_TEST_REPOSITORY/a/file.txt"
  git -C "$GIT_TEST_REPOSITORY" add a/file.txt
  git -C "$GIT_TEST_REPOSITORY" commit -qm directory
  printf 'after\n' > "$GIT_TEST_REPOSITORY/a/file.txt"

  run git_structured_diff --no-prefix HEAD -- a/file.txt
  [[ "$output" == *'<a/file.txt added=0 modified=1 deleted=0>'* ]] || { echo "Stripped a real directory: $output"; return 1; }

  rm "$GIT_TEST_REPOSITORY/a/file.txt"
  run git_structured_diff --no-prefix HEAD -- a/file.txt
  [[ "$output" == *'<a/file.txt added=0 modified=0 deleted=1>'* ]] || { echo "Stripped a deleted file directory: $output"; return 1; }

  printf 'new\n' > "$GIT_TEST_REPOSITORY/a/new.txt"
  git -C "$GIT_TEST_REPOSITORY" add a/new.txt
  run git_structured_diff --no-prefix --cached HEAD
  [[ "$output" == *'<a/new.txt added=1 modified=0 deleted=0>'* ]] || { echo "Stripped a new file directory: $output"; return 1; }
}

function gsd_launcher() {
  (cd "$GIT_TEST_REPOSITORY" && "$HOME/.local/bin/gsd" "$@")
}

@test 'gsd preserves Git failure and difference exit statuses' {
  run gsd_launcher --stat not-a-real-revision
  [ "$status" -eq 128 ] || { echo "Expected Git status 128, got $status: $output"; return 1; }

  printf 'tracked after\n' > "$GIT_TEST_REPOSITORY/tracked.txt"
  run gsd_launcher --quiet HEAD
  [ "$status" -eq 1 ] || { echo "Expected difference status 1, got $status: $output"; return 1; }
  [ -z "$output" ] || { echo "--quiet must not print output: $output"; return 1; }

  run gsd_launcher --exit-code HEAD
  [ "$status" -eq 1 ] || { echo "Expected difference status 1, got $status: $output"; return 1; }
  [[ "$output" == *'modified patch'* ]] || { echo "Expected a formatted patch: $output"; return 1; }
}

@test 'gsd does not silently ignore whitespace changes' {
  printf 'tracked  before\n' > "$GIT_TEST_REPOSITORY/tracked.txt"

  run gsd_launcher HEAD

  [ "$status" -eq 0 ] || { echo "Expected success: $output"; return 1; }
  [[ "$output" == *'tracked  before'* ]] || { echo "Expected the whitespace change, not an empty diff: $output"; return 1; }
}

@test 'git-structured-diff preserves stat output from a commit comparison' {
  printf 'tracked after\n' > "$GIT_TEST_REPOSITORY/tracked.txt"
  git -C "$GIT_TEST_REPOSITORY" commit -qam second
  git -C "$GIT_TEST_REPOSITORY" --no-pager diff --stat HEAD^ HEAD > "$BATS_TEST_TMPDIR/expected"

  git_structured_diff --stat HEAD^ HEAD > "$BATS_TEST_TMPDIR/actual"

  cmp "$BATS_TEST_TMPDIR/expected" "$BATS_TEST_TMPDIR/actual" || {
    echo 'Expected the exact Git stat output, not an empty result.'
    return 1
  }
}

@test 'git-structured-diff does not add untracked files to the comparison' {
  printf 'tracked after\n' > "$GIT_TEST_REPOSITORY/tracked.txt"
  printf 'selected payload line 1\nselected payload line 2\n' > "$GIT_TEST_REPOSITORY/selected.txt"
  printf 'unselected payload\n' > "$GIT_TEST_REPOSITORY/unselected.txt"

  run git_structured_diff HEAD -- tracked.txt selected.txt

  [ "$status" -eq 0 ] || { echo "Expected success. Output: $output"; return 1; }
  [[ "$output" == *'<tracked.txt added=0 modified=1 deleted=0>'* ]] || { echo "Expected the tracked diff. Output: $output"; return 1; }
  [[ "$output" != *'selected.txt'* ]] || { echo "Git excludes untracked files, even when selected. Output: $output"; return 1; }
  [[ "$output" != *'unselected.txt'* ]] || { echo "Did not expect the unselected file tag. Output: $output"; return 1; }
  [[ "$output" != *'unselected payload'* ]] || { echo "Did not expect the unselected content. Output: $output"; return 1; }
}

@test 'git-structured-diff with no arguments excludes staged additions' {
  printf 'staged content\n' > "$GIT_TEST_REPOSITORY/staged.txt"
  git -C "$GIT_TEST_REPOSITORY" add staged.txt

  run git_structured_diff < /dev/null

  [ "$status" -eq 0 ] || { echo "Expected success. Output: $output"; return 1; }
  [ -z "$output" ] || { echo "Expected an empty worktree diff, not staged additions. Output: $output"; return 1; }
}

@test 'git-structured-diff preserves the summary and formats the patch in mixed output' {
  printf 'tracked after\n' > "$GIT_TEST_REPOSITORY/tracked.txt"
  git -C "$GIT_TEST_REPOSITORY" --no-pager diff --stat HEAD > "$BATS_TEST_TMPDIR/stat"

  run git_structured_diff --stat --patch HEAD

  [[ "$output" == "$(< "$BATS_TEST_TMPDIR/stat")"* ]] || { echo "Lost the leading stat: $output"; return 1; }
  [[ "$output" == *'<modified patch 1/1'* ]] || { echo "Did not format the patch: $output"; return 1; }
  assert_git_output --raw -z --patch HEAD
}

@test 'git-structured-diff formats no-index comparisons outside a repository and preserves status' {
  export GIT_TEST_REPOSITORY="$BATS_TEST_TMPDIR"
  printf 'before\n' > "$BATS_TEST_TMPDIR/left"
  printf 'after\n' > "$BATS_TEST_TMPDIR/right"

  run git_structured_diff --no-index left right
  [ "$status" -eq 1 ] || { echo "Expected no-index difference status 1: $status $output"; return 1; }
  [[ "$output" == *'<modified patch 1/1'* ]] || { echo "Expected a formatted no-index patch: $output"; return 1; }

  assert_git_output --no-index --stat left right
  assert_git_output --no-index left left
  assert_git_output --no-index missing right
}

@test 'git-structured-diff does not confuse patch content with file headers' {
  printf '%s\n' '-- old header' 'diff --git old text' '@@ old text' > "$GIT_TEST_REPOSITORY/tracked.txt"
  git -C "$GIT_TEST_REPOSITORY" commit -qam before
  printf '%s\n' '++ new header' 'diff --git new text' '@@ new text' > "$GIT_TEST_REPOSITORY/tracked.txt"

  run git_structured_diff HEAD

  [[ "$output" == *' -  │-- old header'* ]] || { echo "Dropped content resembling a file header: $output"; return 1; }
  [[ "$output" == *'1 │++ new header'* ]] || { echo "Dropped content resembling a file header: $output"; return 1; }
  [[ "$output" == *'2 │diff --git new text'* ]] || { echo "Misparsed diff-like content: $output"; return 1; }
  [[ "$output" == *'3 │@@ new text'* ]] || { echo "Misparsed hunk-like content: $output"; return 1; }
}

@test 'git-structured-diff preserves binary patches and rename-only and mode-only output' {
  git -C "$GIT_TEST_REPOSITORY" mv tracked.txt renamed.txt
  assert_git_output --cached --find-renames HEAD
  git -C "$GIT_TEST_REPOSITORY" commit -qm rename
  chmod +x "$GIT_TEST_REPOSITORY/renamed.txt"
  assert_git_output HEAD
  printf 'binary\000before\n' > "$GIT_TEST_REPOSITORY/data.bin"
  git -C "$GIT_TEST_REPOSITORY" add data.bin
  git -C "$GIT_TEST_REPOSITORY" commit -qm binary
  printf 'binary\000after\n' > "$GIT_TEST_REPOSITORY/data.bin"
  printf 'tracked after\n' > "$GIT_TEST_REPOSITORY/renamed.txt"
  assert_git_output --binary HEAD
  assert_git_output HEAD
}

@test 'git-structured-diff preserves metadata and missing-newline information in text patches' {
  chmod +x "$GIT_TEST_REPOSITORY/tracked.txt"
  printf 'after without newline' > "$GIT_TEST_REPOSITORY/tracked.txt"

  run git_structured_diff HEAD

  [[ "$output" == *'old mode 100644'* && "$output" == *'new mode 100755'* ]] || { echo "Dropped mode changes: $output"; return 1; }
  [[ "$output" == *'after without newline'* && "$output" == *'No newline at end of file'* ]] || { echo "Dropped missing-newline information: $output"; return 1; }
}

@test 'git-structured-diff formats piped patches but preserves other stdin bytes' {
  printf 'tracked after\n' > "$GIT_TEST_REPOSITORY/tracked.txt"
  git -C "$GIT_TEST_REPOSITORY" --no-pager diff HEAD > "$BATS_TEST_TMPDIR/input"
  export GIT_TEST_REPOSITORY="$BATS_TEST_TMPDIR"

  run git_structured_diff < "$BATS_TEST_TMPDIR/input"
  [[ "$output" == *'<modified patch 1/1'* ]] || { echo "Did not format stdin: $output"; return 1; }

  printf 'no final newline\000after NUL' > "$BATS_TEST_TMPDIR/input"
  git_structured_diff < "$BATS_TEST_TMPDIR/input" > "$BATS_TEST_TMPDIR/actual"
  cmp "$BATS_TEST_TMPDIR/input" "$BATS_TEST_TMPDIR/actual" || { echo 'Changed non-patch stdin bytes'; return 1; }

  printf 'diff --git a/a b/a\n--- a/a\n+++ b/a\n@@ -1 +1 @@\n-before\n' > "$BATS_TEST_TMPDIR/input"
  git_structured_diff < "$BATS_TEST_TMPDIR/input" > "$BATS_TEST_TMPDIR/actual"
  cmp "$BATS_TEST_TMPDIR/input" "$BATS_TEST_TMPDIR/actual" || { echo 'Silently formatted an incomplete hunk'; return 1; }
}

@test 'git-structured-diff keeps additions deletions and multiple hunk line ranges' {
  printf 'one\ntwo\nthree\nfour\nfive\nsix\nseven\neight\nnine\nten\n' > "$GIT_TEST_REPOSITORY/tracked.txt"
  git -C "$GIT_TEST_REPOSITORY" commit -qam multiline
  printf 'ONE\ntwo\nthree\nfour\nfive\nsix\nseven\neight\nnine\nTEN\n' > "$GIT_TEST_REPOSITORY/tracked.txt"
  run git_structured_diff --only-line-ranges --unified=0 HEAD
  [[ "$output" == *'line 1: modified'* && "$output" == *'line 10: modified'* ]] || { echo "Wrong hunk ranges: $output"; return 1; }

  printf 'new content\n' > "$GIT_TEST_REPOSITORY/new.txt"
  git -C "$GIT_TEST_REPOSITORY" add new.txt
  run git_structured_diff --cached HEAD
  [[ "$output" == *'<new.txt added=1 modified=0 deleted=0>'* ]] || { echo "Lost an explicitly staged addition: $output"; return 1; }

  rm "$GIT_TEST_REPOSITORY/tracked.txt"
  run git_structured_diff HEAD -- tracked.txt
  [[ "$output" == *'<tracked.txt added=0 modified=0 deleted=1>'* ]] || { echo "Lost the deleted file name: $output"; return 1; }
}

@test 'git-structured-diff preserves errors check diagnostics and explicit output destinations' {
  assert_git_output --not-a-real-option HEAD
  assert_git_output not-a-real-revision
  printf 'trailing space \n' > "$GIT_TEST_REPOSITORY/tracked.txt"
  assert_git_output --check HEAD
  git -C "$GIT_TEST_REPOSITORY" --no-pager diff HEAD > "$BATS_TEST_TMPDIR/expected-file"

  run git_structured_diff --output="$BATS_TEST_TMPDIR/output-file" HEAD
  [ "$status" -eq 0 ] && [ -z "$output" ] || { echo "Changed --output behavior: $status $output"; return 1; }
  cmp "$BATS_TEST_TMPDIR/expected-file" "$BATS_TEST_TMPDIR/output-file" || { echo 'Changed the explicit output file'; return 1; }
}

@test 'git-structured-diff propagates formatter failures and removes temporary captures' {
  printf 'tracked after\n' > "$GIT_TEST_REPOSITORY/tracked.txt"
  mkdir "$BATS_TEST_TMPDIR/tools" "$BATS_TEST_TMPDIR/captures"
  printf '#!/bin/sh\nexit 7\n' > "$BATS_TEST_TMPDIR/tools/awk"
  chmod +x "$BATS_TEST_TMPDIR/tools/awk"

  PATH="$BATS_TEST_TMPDIR/tools:$PATH" TMPDIR="$BATS_TEST_TMPDIR/captures" run git_structured_diff HEAD

  [ "$status" -eq 7 ] || { echo "Masked the formatter failure: $status $output"; return 1; }
  [ -z "$output" ] || { echo "Returned a plausible diff after formatter failure: $output"; return 1; }
  [ -z "$(ls -A "$BATS_TEST_TMPDIR/captures")" ] || { echo 'Leaked temporary diff captures'; return 1; }
}

@test 'gsd invokes only the requested Git comparison and ignores unrelated stdin' {
  printf 'tracked after\n' > "$GIT_TEST_REPOSITORY/tracked.txt"
  printf 'untracked content\n' > "$GIT_TEST_REPOSITORY/untracked.txt"
  printf 'this input must not replace the requested comparison' > "$BATS_TEST_TMPDIR/input"

  GIT_TRACE="$BATS_TEST_TMPDIR/trace" run gsd_launcher --stat HEAD -- tracked.txt < "$BATS_TEST_TMPDIR/input"

  [ "$status" -eq 0 ] || { echo "Expected success: $output"; return 1; }
  [[ "$output" == *'tracked.txt |'* && "$output" != *'untracked'* && "$output" != *'this input'* ]] || { echo "Changed the comparison: $output"; return 1; }
  [ "$(rg -c 'built-in: git ' "$BATS_TEST_TMPDIR/trace")" -eq 1 ] || { echo 'Executed extra Git operations'; return 1; }
}

@test 'gsd supports no-index process substitutions' {
  run bash -c '"$HOME/.local/bin/gsd" --no-index <(printf "before\n") <(printf "after\n")'

  [ "$status" -eq 1 ] || { echo "Expected difference status 1: $status $output"; return 1; }
  [[ "$output" == *'before'* && "$output" == *'after'* ]] || { echo "Lost process substitution content: $output"; return 1; }
}

@test 'git-structured-diff preserves combined merge diffs' {
  git -C "$GIT_TEST_REPOSITORY" branch other
  printf 'first branch\n' > "$GIT_TEST_REPOSITORY/tracked.txt"
  git -C "$GIT_TEST_REPOSITORY" commit -qam first-branch
  local first_branch
  first_branch=$(git -C "$GIT_TEST_REPOSITORY" branch --show-current)
  git -C "$GIT_TEST_REPOSITORY" checkout -q other
  printf 'other branch\n' > "$GIT_TEST_REPOSITORY/tracked.txt"
  git -C "$GIT_TEST_REPOSITORY" commit -qam other-branch
  git -C "$GIT_TEST_REPOSITORY" merge "$first_branch" >/dev/null 2>&1 || [ "$?" -eq 1 ]

  assert_git_output --cc
}
