#!/usr/bin/env bats

function setup() {
  export LAND="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

function strip_in_land() {
  zsh -fc '
    source "$LAND/init.sh" >/dev/null 2>&1 || exit 1
    strip "$@"
  ' -- "$@"
}

@test 'strip with an empty argument does not wait for input' {
  run strip_in_land '' <<< 'STDIN_MUST_NOT_BE_READ'

  [ "$status" -eq 2 ] || { echo "Expected an empty-input error: $status $output"; return 1; }
  [[ "$output" != *'STDIN_MUST_NOT_BE_READ'* ]] || { echo "Read stdin instead of the empty argument: $output"; return 1; }
}

@test 'strip trims only surrounding whitespace from arguments and piped input' {
  run strip_in_land $'\n\t new documentation \n\n'
  [ "$output" = 'new documentation' ] || { echo "Changed the text or kept surrounding whitespace: '$output'"; return 1; }

  run strip_in_land '  keep  inner  spacing  '
  [ "$output" = 'keep  inner  spacing' ] || { echo "Changed inner whitespace: '$output'"; return 1; }

  run strip_in_land <<< '  no longer from stdin  '
  [ "$output" = 'no longer from stdin' ] || { echo "Changed stdin trimming: '$output'"; return 1; }
}
