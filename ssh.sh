#!/usr/bin/env zsh


declare -A LISA
LISA[url]=
LISA[addr]=
LISA[secret]=~/.ssh/lisa

declare -A NELSON
NELSON[url]=
NELSON[addr]=
NELSON[secret]=~/.ssh/nelson

declare -A LEADER
LEADER[url]=
LEADER[addr]=
LEADER[secret]=~/.ssh/leader

declare -A NED
NED[url]=
NED[addr]=
NED[secret]=~/.ssh/ned

declare -A EDNA
EDNA[url]=
EDNA[addr]=
EDNA[secret]=~/.ssh/edna

declare -A SELMA
SELMA[url]=
SELMA[addr]=
SELMA[secret]=~/.ssh/selma

declare -A TROY
TROY[url]=
TROY[addr]=
TROY[secret]=~/.ssh/troy

declare -A ARIA
ARIA[url]=
ARIA[addr]=
ARIA[secret]=~/.ssh/aria

declare -A VERTICA
VERTICA[url]=
VERTICA[addr]=
VERTICA[secret]=~/.ssh/vertica

QA_ENVS=(
  LISA
  NELSON
  LEADER
  NED
  EDNA
  SELMA
  )


# *** rsync
{
  # ** rsync.sync

  # rsync.sync.local2remote <USER@IP> <SOURCE> <DESTINATION> [rsync options...]
  # Example:
  # rsync.sync.local2remote $LISA_ADDR ssh.sh /tmp/ssh.ssh
  function rsync.sync.local2remote(){
    local remote_addr="$1"
    local source="$2"
    local destination="$3"
    shift 3
    local delay
    local exitcode
    args.parse -d,--delay "$@" && set -- "${UNPARSED[@]}" && unset UNPARSED
    [[ $delay == false ]] && delay=10s
    while true
    do

      log.notice "Syncing $source to $destination..."
      rsync.wrapper "$source" "${remote_addr}:${destination}" "$@"
      exitcode=$?
      if [[ $exitcode != 0 ]]; then
        log.fatal "rsync exited with code $exitcode, aborting"
        return $exitcode
      fi

      log.success "Copied OK, sleeping $delay"
      sleep $delay

    done
  }

  # rsync.wrapper <SOURCE> <DESTINATION> [rsync option...]
  # Adds --info=progress2 -z --compress-level=9 -C -h
  function rsync.wrapper(){
    rsync --info=progress2 --compress-level=9 --cvs-exclude --human-readable "$@" 2>&1
  }
  # ** rsync.local2remote
  # rsync.local2remote <LOCAL PATH> <REMOTE PATH> <USER@IP> [rsync option...]
  function rsync.local2remote(){
    local local_path="$1"
    shift
    local remote_path="$1"
    shift
    local remote_addr="$1"
    shift
    rsync.wrapper "$local_path" "$remote_addr":"$remote_path" "$@"
  }

   function __rsync.local2remote_completion(){
     completion.generate '<LOCAL PATH>' '<REMOTE PATH>' '<USER@IP>' '[rsync option...]'
   }
   complete -o default -F __rsync.local2remote_completion rsync.local2remote

  # ** rsync.remote2local
  # rsync.remote2local <REMOTE PATH> <LOCAL PATH> <USER@IP> [rsync option...]
  function rsync.remote2local(){
    local remote_path="$1"
    shift
    local local_path="$1"
    shift
    local remote_addr="$1"
    shift
    rsync.wrapper "$remote_addr":"$remote_path" "$local_path" "$@"
  }
  function __rsync.remote2local_completion(){
    completion.generate '<REMOTE PATH>' '<LOCAL PATH>' '<USER@IP>' '[rsync option...]'
  }
  complete -o default -F __rsync.remote2local_completion rsync.remote2local


}

# *** ssh
{
  # # ssh.qa_env <QA ENV NAME> [ssh options...]
  function ssh.qa_env(){
    # troy -> TROY
    local qa_env_name="$(echo "$1"| tr '[:lower:]' '[:upper:]')"
    shift || return 1
    # typeset -A TROY=( [addr]='' [secret]=/home/gilad/.ssh/troy [url]='' )
    local qa_env_str="$(declare -p "$qa_env_name")"
    # $qa_env: TROY=( [addr]='' [secret]=/home/gilad/.ssh/troy [url]='' )
    eval "declare -A qa_env=${qa_env_str#*=}" || return 1
    if [[ ${@[(r)-i]} ]]; then
      vex ssh "${qa_env[addr]}" "$@"
      return $?
    fi
    if [[ ! -f "${qa_env[secret]}" ]]; then
        log.warn "No secret key found for $qa_env_name. You can create one with 'ssh.pair'."
        vex ssh "${qa_env[addr]}" "$@"
        return $?
    else
        vex ssh -i "${qa_env[secret]}" "${qa_env[addr]}" "$@"
        return $?
    fi
  }

}


# *** sshfs
{
  # sshfs.wrapper <QA ENV NAME> <LOCAL MOUNTPOINT> [REMOTE MOUNTPOINT] [sshfs args...]
  function sshfs.wrapper(){
    if ! command -v sshfs &>/dev/null; then log.fatal "'sshfs' not installed, run 'sudo apt install sshfs' and try again"; return 1; fi
    local qa_env_name="$(echo "$1"| tr '[:lower:]' '[:upper:]')"
    shift
    local qa_env_str
    if ! qa_env_str="$(declare -p $qa_env_name)"; then
      log.fatal "Bad qa_env_name: $qa_env_name"
      return 1
    fi
    eval "declare -A qa_env=${qa_env_str#*=}"
    local local_mountpoint="$1"
    shift
    if [[ ! -d "$local_mountpoint" ]]; then
      sudo mkdir -v "$local_mountpoint" || return 1
    fi
    local remote_mountpoint="${1:-/}"
    local sshfs_args=("${@}")
    if [[ -f "${qa_env[secret]}" ]]; then
      sshfs_args+=(-o IdentityFile="${qa_env[secret]}")
    fi


    sudo sshfs -o allow_other,no_check_root "${sshfs_args[@]}" "${qa_env[addr]}":"$remote_mountpoint" "$local_mountpoint"
    return $?
  }

  complete -o default \
           -C "completion.generate '<QA ENV NAME>' '<LOCAL MOUNTPOINT>' '[REMOTE MOUNTPOINT]' '[sshfs args...]' -e 'sshfs.wrapper leader /mnt/leader /root'" \
           sshfs.wrapper

}

# *** scp

# ** scp.local2remote
{
  # scp.local2remote <QA ENV NAME> <LOCAL PATH> <REMOTE PATH> [scp option...]
  function scp.local2remote() {
    local qa_env_name="$(echo "$1"| tr '[:lower:]' '[:upper:]')"
    shift
    local qa_env_str
    if ! qa_env_str="$(declare -p "$qa_env_name")"; then
      log.fatal "Bad qa_env_name: $qa_env_name"
      return 1
    fi
    eval "declare -A qa_env=${qa_env_str#*=}"
    local localpath="$1"
    shift
    local remotepath="$1"
    shift
    local scp_args=("$@")
    if [[ -f "${qa_env[secret]}" ]]; then
      scp_args+=(-i "${qa_env[secret]}")
    fi
    scp "${scp_args[@]}" "$localpath" "${qa_env[addr]}":"$remotepath"
    return $?
  }

  complete -o default -C "completion.generate '<QA ENV NAME>' '<LOCAL PATH>' '<REMOTE PATH>' '[scp options...]'" scp.local2remote

  # ** scp.remote2local

  # scp.remote2local <QA ENV NAME> <REMOTE PATH> <LOCAL PATH> [scp option...]
  function scp.remote2local() {
    local qa_env_name="$(echo "$1"| tr '[:lower:]' '[:upper:]')"
    shift
    local qa_env_str
    if ! qa_env_str="$(declare -p "$qa_env_name")"; then
      log.fatal "Bad qa_env_name: $qa_env_name"
      return 1
    fi
    eval "declare -A qa_env=${qa_env_str#*=}"
    local remotepath="$1"
    shift
    local localpath="$1"
    shift
    local scp_args=("$@")
    if [[ -f "${qa_env[secret]}" ]]; then
      scp_args+=(-i "${qa_env[secret]}")
    fi
    scp "${scp_args[@]}" "${qa_env[addr]}":"$remotepath" "$localpath"
    return $?
  }

  complete -o default -C "completion.generate '<QA ENV NAME>' '<REMOTE PATH>' '<LOCAL PATH>' '[scp options...]'" scp.remote2local


}

#
#for QA_ENV in "${QA_ENVS[@]}"; do
#    qa_env_lowercase="$(echo "$QA_ENV" | tr '[:upper:]' '[:lower:]')"
#    source /dev/stdin <<EOF
#
######## [ rsync local -> remote ] ########
## <LOCAL PATH> <REMOTE PATH> [rsync option...]
#function rsync.local2${qa_env_lowercase}() {
#     rsync.local2remote "${@:0:3}" "${QA_ENV[addr]}" "${@:3}"
#};
#function __rsync.local2${qa_env_lowercase}_completion(){
#  completion.generate '<LOCAL PATH>' "<${QA_ENV} PATH>" '[rsync option...]'
#}
#complete -o default -F __rsync.local2${qa_env_lowercase}_completion rsync.local2${qa_env_lowercase}
#
#
######## [ rsync remote -> local ] ########
## <REMOTE PATH> <LOCAL PATH> [rsync option...]
#function rsync.${qa_env_lowercase}2local() {
#     rsync.remote2local "${@:0:3}" "${QA_ENV[addr]}" "${@:3}"
#};
#function __rsync.${qa_env_lowercase}2local_completion(){
#  completion.generate "<${QA_ENV} PATH>" '<LOCAL PATH>' '[rsync option...]'
#}
#complete -o default -F __rsync.${qa_env_lowercase}2local_completion rsync.${qa_env_lowercase}2local
#
#
######## [ ssh ] ########
#function ssh.${qa_env_lowercase}() {
#     ssh.qa_env ${qa_env_lowercase} "$@"
#     return $?
#};
#function __ssh.${qa_env_lowercase}_completion(){
#  completion.generate '[ssh option...]'
#}
#complete -o default -F __ssh.${qa_env_lowercase}_completion ssh.${qa_env_lowercase}
#
######## [ ssh.pair ] ########
#function ssh.pair.${qa_env_lowercase}() {
#     ssh.pair ${qa_env_lowercase} "${QA_ENV[addr]}" "$@"
#     return $?
#};
#function __ssh.pair.${qa_env_lowercase}_completion(){
#  completion.generate '[ssh-keygen option...]'
#}
#complete -o default -F __ssh.pair.${qa_env_lowercase}_completion ssh.pair.${qa_env_lowercase}
#
######## [ sshfs ] ########
#function sshfs.${qa_env_lowercase}() {
#     sshfs.wrapper ${qa_env_lowercase} "$@"
#     return $?
#};
#
#function __sshfs.${qa_env_lowercase}_completion(){
#  completion.generate '<LOCAL MOUNTPOINT>' '[REMOTE MOUNTPOINT]' '[ssh-keygen option...]' -e 'sshfs.${qa_env_lowercase} /mnt/${qa_env_lowercase}'
#}
#complete -o default -F __sshfs.${qa_env_lowercase}_completion sshfs.${qa_env_lowercase}
#
#
######## [ scp local -> remote ] ########
#function scp.local2${qa_env_lowercase}() {
#     scp.local2remote ${qa_env_lowercase} "$@"
#     return $?
#};
#
#function __scp.local2${qa_env_lowercase}_completion(){
#  completion.generate '<LOCAL PATH>' '<REMOTE PATH>' '[scp options...]'
#}
#complete -o default -F __scp.local2${qa_env_lowercase}_completion scp.local2${qa_env_lowercase}
#
######## [ scp remote -> local ] ########
#function scp.${qa_env_lowercase}2local() {
#     scp.remote2local ${qa_env_lowercase} "$@"
#     return $?
#};
#
#function __scp.${qa_env_lowercase}2local_completion(){
#  completion.generate '<REMOTE PATH>' '<LOCAL PATH>' '[scp options...]'
#}
#complete -o default -F __scp.${qa_env_lowercase}2local_completion scp.${qa_env_lowercase}2local
#
#EOF
#
#
#  done
