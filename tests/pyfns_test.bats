#!/usr/bin/env bats

THIS_SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]:-$0}")")"
function setup() {
	load ${LAND}/util.sh
	load ${LAND}/pyfns.sh
	set -e
}

@test 'py.print' {
  local py_prog='next(l for l in lines if all(l.partition(' ")[2] in _line for _line in map(lambda _l:_l.partition(" ")[2],lines)))"
  run cat "$THIS_SCRIPT_DIR/pyfns_test_2_fullnames" | py.print "$py_prog"
  [ "$status" -eq 0 ]
}

