#!/env/bin/bash
if [[ "$OS" == Linux ]]; then {

# ** apt

alias suapt='sudo apt'
alias apti='suapt install' # <regex / glob / exact>
alias aptl='apt list'    # [glob]
alias aptli='apt list --installed'
alias aptlig="apt list --installed | grep -P"
alias aptlu='apt list --upgradable'
alias aptr='suapt remove'
alias aptp='suapt purge'
alias aptar='suapt autoremove'
alias apts='apt search'   # <regex>
alias aptud='suapt update'  # dl pkg info (avail versions)
alias aptug='suapt upgrade' # does not remove existing

function aptsg() {
  local pager
  local pagerargs=()
  if isdefined bat; then
    pager="bat"
    pagerargs=(--color=always --plain)
  else
    pager="${PAGER:-less}"
  fi

  apt search "$1" | command grep --color=always -A 1 -P "$1" | "$pager" "${pagerargs[@]}"
}

function apt.reqs(){
  local all_reqs=()
  local level_1_reqs=( $(apt depends "$1" 2>/dev/null | grep -Po '(?<=Depends: )[^ ]+'))
  if [ -z "$level_1_reqs" ]; then
    log.success "No dependencies for $1"
    return 0
  fi
  all_reqs=( ${level_1_reqs[@]} )
  log.info "Dependencies for $1: ${level_1_reqs[*]}"
  log.warn "Haven't implemented recursive calls yet, exiting"
  return 0

}

# ** snap
alias snaps="snap search"
alias snapi="sudo snap install" # [--verbose]
alias snapr="sudo snap remove"  # [--purge] to remove snapshot data
alias snapl="snap list"    # list installed snaps

function snapsg() {
  local pager pagerargs=()
  if isdefined bat; then
    pager="bat"
    pagerargs=(--color=always --plain)
  else
    # shellcheck disable=SC2153
    pager="$PAGER"
  fi

  snap search "$1" | command grep --color=always -A 1 -P "$1" | "$pager" "${pagerargs[@]}"
}

function snap.size(){
  snap info "$1" | command grep -Po '\d+(?=[A-Z]B)' | head -1
}
function snap.cleanup() {
  if [[ ! -e /var/lib/snapd/cache ]]; then
    log.fatal "/var/lib/snapd/cache does not exist, aborting"
    return 1
  fi

  log.prompt "/var/lib/snapd/cache files:"
  sudo /bin/ls /var/lib/snapd/cache
  sudo du -sh /var/lib/snapd/cache
  if ! confirm "Remove these files?"; then
    return 3
  fi

  local file
  sudo /bin/ls /var/lib/snapd/cache | while read -r file; do
    if ! vex sudo rm /var/lib/snapd/cache/"$file"; then
      log.fatal "Failed, aborting"
      return 1
    fi
  done

  log.prompt "disabled snaps:"
  sudo snap list --all | awk '/disabled/{print $1, $3}'
  if ! confirm "Remove these snaps?"; then
    return 3
  fi

  local snapname revision
  sudo snap list --all | awk '/disabled/{print $1, $3}' | while read -r snapname revision; do
    if ! vex sudo snap remove "$snapname" --revision="$revision"; then
      log.fatal "Failed, aborting"
      return 1
    fi
  done
  log.success "Done"
  return 0
}

}
else {
	source pkgmgr.mac.sh
}
fi
