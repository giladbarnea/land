#!/usr/bin/env bats

function setup() {
  export GIT_TEST_REPOSITORY="$(mktemp -d)"
  git -C "$GIT_TEST_REPOSITORY" init -q
  git -C "$GIT_TEST_REPOSITORY" config user.email test@example.com
  git -C "$GIT_TEST_REPOSITORY" config user.name Test
  printf 'tracked before\n' > "$GIT_TEST_REPOSITORY/tracked.txt"
  git -C "$GIT_TEST_REPOSITORY" add tracked.txt
  git -C "$GIT_TEST_REPOSITORY" commit -qm initial
}

function teardown() {
  rm -rf "$GIT_TEST_REPOSITORY"
}

function git_structured_diff() {
  zsh -fc '
    alias gsd=true g=true gd=true glola=true gloga=true gp=true
    alias gstaa=true gstc=true gstd=true gstl=true gstp=true gsts=true gstu=true gstall=true
    alias gignore=true gunignore=true
    source "$LAND/git.sh"
    cd "$GIT_TEST_REPOSITORY"
    git-structured-diff -y "$@"
  ' -- "$@"
}

@test 'git-structured-diff includes only selected untracked files' {
  printf 'tracked after\n' > "$GIT_TEST_REPOSITORY/tracked.txt"
  printf 'selected payload line 1\nselected payload line 2\n' > "$GIT_TEST_REPOSITORY/selected.txt"
  printf 'unselected payload\n' > "$GIT_TEST_REPOSITORY/unselected.txt"

  run git_structured_diff HEAD -- tracked.txt selected.txt

  [ "$status" -eq 0 ] || { echo "Expected success. Output: $output"; return 1; }
  [[ "$output" == *'<tracked.txt added=0 modified=1 deleted=0>'* ]] || { echo "Expected the tracked diff. Output: $output"; return 1; }
  [[ "$output" == *'<selected.txt added=1 modified=0 deleted=0>'* ]] || { echo "Expected the selected untracked file tag. Output: $output"; return 1; }
  [[ "$output" == *'selected payload line 1'* ]] || { echo "Expected the first selected line. Output: $output"; return 1; }
  [[ "$output" == *'selected payload line 2'* ]] || { echo "Expected the second selected line. Output: $output"; return 1; }
  [[ "$output" != *'unselected.txt'* ]] || { echo "Did not expect the unselected file tag. Output: $output"; return 1; }
  [[ "$output" != *'unselected payload'* ]] || { echo "Did not expect the unselected content. Output: $output"; return 1; }
}
