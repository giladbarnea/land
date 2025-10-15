# ------------[ defaults ]------------

# defaults-set <defaults write ...>
# Prints current values and confirms before running the write command.
# Examples:
#    defaults write com.apple.frameworks.diskimages skip-verify -bool true
#    defaults write -g PMPrintingExpandedStateForPrint -bool true
function defaults-set(){
  local -a write_command=(${(z)@})
  local -a read_command=(${(z)@})
  read_command[2]='read'
  log.debug "$(typeset read_command)"
  ${read_command[@]}
  confirm "Run ${write_command[*]}?" || return 1
  ${write_command[@]}

  set -x
  ${read_command[@]}
  set +x
}


# ------------[ wnr ]------------

alias wnr-reset='rm "/Users/gilad/Library/Application Support/wnr/timing-data.json"'