#!/usr/bin/env bats
function setup() {
	load ${LAND}/log.sh
	load ${LAND}/args.sh
}
@test 'args.parse test1' {
  # shellcheck disable=SC2054
  local definitions=(
    -r,--repo
    -l,local_file_path
    -t,--diff-tool,difftool
    --my-flag
    --opt-with-var,opt_with_var
    --opt-with-suprise,opt_with_different_varname
    --opt-no-var-equals
    --opt-no-var-space
  )
  local values=(
    -r ipython
    --diff-tool meld
    -l foo.sh
    --my-flag
    --opt-with-suprise "kinda cool"
    --opt-no-var-equals='great value'
    --opt-no-var-space "value for space"
  )
  args.parse "${definitions[@]}" "${values[@]}"
	[ "$repo" == ipython ]
	[ "$local_file_path" == foo.sh ]
	[ "$difftool" == meld ]
	[ "$my_flag" == true ]
	[ "$opt_with_var" == false ]
	[ "$opt_with_different_varname" == "kinda cool" ]
	[ "$opt_no_var_equals" == "great value" ]
	[ "$opt_no_var_space" == "value for space" ]
}
@test 'args.parse test2' {
  function foo(){
    args.parse -i,--include "$@"
    [ "$include" == bar.txt ]
  }
  foo -i bar.txt
}

@test 'args.parse test3' {
  args.parse -x,--exclude -x foo.txt a b c
  [ "$exclude" == foo.txt ]
  [ "${UNPARSED[*]}" == "a b c" ]
}