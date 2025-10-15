#!/usr/bin/env bash

# Check out zparseopts

function args._extract_varname() {
  echo "$1" | cut -d - -f 3- | tr - _
}


# # args.parse <DEFINITION...> [VALUE...]
# ## DEFINITION
# A `definition` sets the args/opts to parse, with optional specification of variable names via comma (`,`).
# If no variable name is specified, it is understood from the long option name.
# ## Examples
# #### Simple Usage
# ```bash
# function foo(){
#   args.parse -i,--include "$@"
#   echo "$include"
# }
# foo -i bar.txt    # bar.txt
# ```
# #### All Features
# ```bash
# definitions=(
#    -r,--repo
#    -l,local_file_path
#    -t,--diff-tool,difftool
#    --my-flag
#    --opt-with-var,opt_with_var
#    --opt-with-suprise,opt_with_different_varname
#    --opt-no-var-equals
#    --opt-no-var-space
#  )
# values=(
#    -r ipython
#    --diff-tool meld
#    -l foo.sh
#    --my-flag
#    --opt-with-suprise "kinda cool"
#    --opt-no-var-equals='great value'
#    --opt-no-var-space "value for space"
#  )
#
# args.parse "${definitions[@]}" "${values[@]}"
# echo $repo                        # ipython
# echo $local_file_path             # foo.sh
# echo $difftool                    # meld
# echo $my_flag                     # true
# echo $opt_with_var                # false
# echo $opt_with_different_varname  # kinda cool
# echo $opt_no_var_equals           # great value
# echo $opt_no_var_space            # value for space
# ```
function args.parse() {
   log.debug "args.parse($*)"

  declare -A keys
  UNPARSED=()
  local opt1
  local opt2
  local varname
  local val
  while [[ $# -gt 0 ]]; do
    case "$1" in
    #*,[-a-z]*|--[a-z])
    *,[-a-z]*)
      ### Definitions, not including standalone --longopt (on purpose)
      opt1="$(echo "$1" | cut -d ',' -f 1)"
      opt2="$(echo "$1" | cut -d ',' -f 2)"
      varname="$(echo "$1" | cut -d ',' -f 3)"
      if [[ "$opt1" == "$opt2" ]]; then
        # 1 tuple; -t or --diff-tool
        if [[ -n "${keys[$opt1]}" ]]; then
          varname="${keys[$1]}"
          val="$2"
          eval "$varname=\"$val\""
          shift 2

        else
          keys[$opt1]=false
          shift

        fi
      elif [[ -z "$varname" ]]; then
        # 2 tuple: -t,--diff-tool or -t,difftool or --diff-tool,difftool
        if [[ "$opt2" != -* ]]; then
          # -t,difftool
          varname="$opt2"
        else
          # -t,--diff-tool
          varname="$(args._extract_varname "$opt2")"
          keys[$opt2]="$varname"
          log.debug "varname: ${varname} | keys[$opt2]: ${keys[$opt2]}"
        fi
        # if ! args._is_defined "$varname"; then
        #   keys[$opt1]="$varname"
        #   eval "$varname"=false
        # else
        #   log.warn "$varname already defined: $(args._val_by_varname "$varname")"
        # fi
        keys[$opt1]="$varname"
        eval "$varname"=false
        shift

      else
        # 3 tuple
        # -t,--diff-tool,difftool
        keys[$opt1]="$varname"
        keys[$opt2]="$varname"
        shift

      fi ;;
    *) ### Values, e.g $@, or standalone --longopt definition (on purpose)
      if [[ -n "${keys[$1]}" ]]
      # * Known definition, and $1 is the key, e.g -t foo or --diff-tool bar or --diff-tool=baz
      then

        if [[ "${keys[$1]}" == false ]]
        # Var name was NOT specified
        then
          varname="$(args._extract_varname "$1")"
          # if [[ -z "$2" ]]
          # then
          #   keys[$1]=true
          #   eval "$varname"=true
          #   shift
          #   continue
          # fi
          if [[ "$2" != -* ]]
          # --diff-tool bar
          then
            val="$2"
            shift 2

          else
            # --diff-tool
            val=true
            shift

          fi
          eval "$varname=\"$val\""
        else
          # Var name was specified
          varname="${keys[$1]}"
          val="$2"
          eval "$varname=\"$val\""
          shift 2

        fi
      else
        # * UNknown definition, first time seeing it
        if [[ "$1" != -* ]]
        # Raw value
        then
          UNPARSED+=("$1")
          shift

          continue
        fi

        if [[ "$1" != --* ]]
        # just '-l' isn't good if we can't attribute it to a variable.
        then
          log.fatal "Got a definition of a short option (${Cc}${1}${Cc0}) with no varname; only longopt can be standalone. keys[$1]: ${keys[$1]}"
          return 2
        fi

        if [[ "$1" == *=* ]]
        # --diff-tool=foo
        then
          local key="$(echo "$1" | cut -d = -f 1)"
          val="$(echo "$1" | cut -d = -f 2)"
          varname="$(args._extract_varname "$key")"
          eval "$varname=\"$val\""
        else
          # --diff-tool (either definition or value)
          varname="$(args._extract_varname "$1")"
          # if ! args._is_defined "$varname"
          # # Only set to 'false' if undefined.
          # # This catches 'local varname=foo' from outside too.
          # then
          #   keys[$1]=false
          #   eval "$varname"=false
          # fi
          keys[$1]=false
          eval "$varname"=false
        fi
        shift

      fi ;;
    esac
  done
  export UNPARSED
}

__args.parse__completion(){
  completion.generate '<DEFINITION...>' '[VALUE...]' -e 'args.parse -d,--delay,my_delay_var "$@" && set -- "${UNPARSED[@]}" && unset UNPARSED'
}
complete -o default -F __args.parse__completion args.parse