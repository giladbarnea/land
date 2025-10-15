#!/usr/bin/env zsh

type docker &>/dev/null || return 1

# shellcheck disable=SC2032
#if { ! alias docker && ! alias docker compose ; } &>/dev/null \
#   && [[ "$1" == --patch-sudo-docker || -n "$PATCH_SUDO_DOCKER" || "$(stat -c %U "$(which docker)")" != "${WHOIAM:-$(whoami)}" ]]
#then
#  function docker(){ sudo "docker" "$@" ; }
#  function docker compose(){ sudo "docker compose" "$@" ; }
#fi


SERVICES=(
   '<NO SERVICE!>'
 )

# ---------[ Images ]-----------
{

function docker.images.names() {
  docker images --all | cut -d $'\n' -f 2- | cut -d ' ' -f 1
}
function docker.images.ids() {
  docker images --all | cut -d $'\n' -f 2- | command grep --color=never -Po '[a-z0-9]+(?=\s+\d* \w* ago)'
}

# # docker.images.remove <SERVICE...>
# # docker.images.remove --all
# Does `docker rmi` to `docker compose images`.
# ## Example
# docker.images.remove
function docker.images.remove() {
  log.title "docker.images.remove($*)"
  if [[ ! "$1" ]]; then
    log.fatal "Not enough args (expected either '--all' or <SERVICE...>)"
    return 1
  fi

  local remove_these=()
  local positional=()
  local docker_image_prune_args=(-f)
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --all)
      remove_these=("$(docker.images.ids)")
      docker_image_prune_args+=(-a)
      break ;;
    *) remove_these+=("$1") ;;
    esac
		shift
  done
  set -- "${positional[@]}"
  log.debug "remove_these: ( ${remove_these[*]} )"

  vex docker compose down -v --remove-orphans
  log.title "docker rmi -f ..."
  local image_id
  while read -r image_id; do vex docker rmi -f "$image_id"; done <<< "${remove_these[@]}"
  log.title "docker image prune ${docker_image_prune_args[*]}"
  vex docker image prune "${docker_image_prune_args[@]}"

  log.notice "Should print nothing:" -L
  vex docker images -f '"dangling=true"'
  return $?
}

function docker.images.tok8(){
  # docker build --build-arg name=${app} -f ./backend/services/${app}/Dockerfile.unified -t local-${v}/${app}:latest --network host ./backend/services
  # docker save local-${v}/${app}:latest | gzip -c --best --rsyncable > ${app}_local_${v}.tgz
  # scp to /opt of every *slave node*
  #     get IP from Nodes > internalIP in lens, or: k get nodes -o yaml | grep -Po '(?<=IPv4Address: )[\d.]+' | cut -d $'\n' -f 2-
  # rsync --info=progress2 --human-readable --compress-level=9 ./${app}_local_${v}.tgz "${addr}:/opt"
  # ssh $otto "bash -c 'seq 2 6 | xargs -n1 -P4 -I% scp /opt/${app}_local_${v}.tgz root@1...%:/opt; seq 2 6 | xargs -n1 -P4 -I% ssh -t root@...% docker load -i /opt/${app}_local_${v}.tgz'"
  # ssh -t root@${slave}2 'for i in 3 4 5 6; do scp /opt/customconfig_local_0.tgz root@${slave}${i}:/opt; docker load -i /opt/customconfig_local_0.tgz; done'
  # seq 2 6 | xargs -n1 -P4 -I% scp /opt/customconfig_local_0.tgz root@...%:/opt
  # reminder: ssh-keygen -f ~/.ssh/slave2; ssh-copy-id -i ~/.ssh/slave2.pub root@...${i}
  local dockerfile_path="$(docker.services.get_Dockerfile "$service")" ||	return 1
  local app="$(input "Service name?")"
  local v="$(input "Version?")"
  vex "declare -p | command grep -P 'root@\d{2,3}(\.\d{2,3}){3}'"
  local destination="$(input "Destination? e.g root@...")"
  runcmds \
		'docker build --build-arg name=${app} -f "$dockerfile_path" -t local-${v}/${app}:latest --network host ./backend/services' \
		'docker save local-${v}/${app}:latest | gzip -c --best --rsyncable > ${app}_local_${v}.tgz' \
		'rsync --info=progress2 --human-readable --compress-level=9 ./${app}_local_0.tgz ${destination}:/opt'
	local slave_nodes=($(vex "ssh $destination kubectl -n secure-management get nodes -o yaml 2>/dev/null | grep -Po '(?<=IPv4Address: )[\d.]+' | cut -d $'\n' -f 2-"))
	ssh $destination "bash -c 'for slave in \${slave_nodes[@]}; do scp /opt/${app}_local_${v}.tgz \$slave:/opt && ssh -t \$slave docker load -i /opt/${app}_local_${v}.tgz; done'"
	z.good "done ${app} ${v} ${destination}"
}

# # docker.images.build_by_service <SERVICE> [docker build args...]
# Consider using `--no-cache --pull`
function docker.images.build_by_service() {
  log.megatitle "docker.images.build_by_services($*)"
  local service="$1"
  shift || { log.fatal "Not enough args (expected <SERVICE>)" ; return 1 ; }
  local dockerfile_path
  dockerfile_path="$(docker.services.get_Dockerfile "$service")" ||	return 1
  log.success "Using $dockerfile_path"
  local positional=()
  local tag="artifactory.rdlab.local/microservices-docker-sandbox-local/${service}:latest"
  while [[ $# -gt 0 ]]; do
  	if [[ "$1" == -t || "$1" == --tag ]]; then
  		tag="$2"
  		shift 2
  	elif [[ "$1" == --tag=* ]]; then
			tag="${1#--tag=}"
			shift
		else
			positional+=("$1")
			shift
		fi
	done
  docker build \
         --build-arg name="${service}" \
         -t "${tag}" \
         -f "${dockerfile_path}" \
         "${positional[@]}" \
         ./backend/services
  return $?
}

# docker.images.build_by_services <SERVICE> [SERVICE...] [-- [docker build args...]]
# docker.images.build_by_services --all [-- [docker build args...]]
# Uses 8 processes by default.
# Examples:
# docker.images.build_by_services --all                                  # builds images of all services, 8 at a time
# docker.images.build_by_services --all -P 6                             # builds images of all services, 6 at a time
# docker.images.build_by_services accounts customconfig -- --no-cache    # builds images of accounts and customconfig, aborts if something fails
function docker.images.build_by_services() {
  # for service in "$SERVICES[@]"; do
  # 	kitty --hold . /home/gilad/dev/land/init.sh && builtin cd /home/gilad/dev/allotsecure && docker.images.build_by_service "$service"
  # done
  set -o pipefail
  log.title "docker.images.build_by_services($*)"
  if [[ -z "$1" ]]; then
    log.fatal "$0 expecting at least one arg, either --all or SERVICE, [SERVICE...]"
    return 1
  fi
  local services=()
  local parse_docker_build_args=false
  local docker_build_args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --all)
        services=("${SERVICES[@]}")
        shift ;;
      --)
        parse_docker_build_args=true
        shift ;;
      *)
        if $parse_docker_build_args; then
          docker_build_args+=("$1")
        else
          services+=("$1")
        fi
        shift ;;
    esac
  done
  if ! confirm "Services: ${Cc}${services[*]}${Cc0}\ndocker build args: ${Cc}${docker_build_args[*]}${Cc0}\nContinue?"; then
    log.warn Aborting
    return 3
  fi
  local service
  for service in "${services[@]}"; do
  	log.megatitle "${service}"
    background docker.images.build_by_service "$service" "${docker_build_args[@]}"
  done

  if ! vex pgrep -fa "'docker build --build-arg name'"; then
		log.error "No docker build processes running"
		return 2
	fi
  local docker_build_processes
	# (printf "%b" 'from rich import get_console; from time import sleep\nwith get_console().status("Building..."): sleep(600)' | py39 &)
  while docker_build_processes="$(pgrep -fa "docker build --build-arg name")"; do
  	echo "$docker_build_processes"
  	log.info "\nWaiting for $(wc -l <<< "$docker_build_processes") processes to finish..." -L -x
  	sleep 5
  done
  # pkill --newest 'python'
  log.success "All done"
 #   export docker.services.get_Dockerfile
 # ##  echo "${services[*]}" | xargs -P8 zsh -c 'source ~/dev/land/docker.sh; sudo docker build --build-arg name="$1" -t artifactory.rdlab.local/microservices-docker-sandbox-local/"$1":latest -f "$(docker.services.get_Dockerfile "$1")" ./backend/services' {}
 #   echo "${services[*]}" | xargs -P8 bash -c 'sudo docker build --build-arg name="$1" -t artifactory.rdlab.local/microservices-docker-sandbox-local/"$1":latest -f "$(docker.services.get_Dockerfile "$1")" ./backend/services' {}
 #   return $?


#  for service in "${services[@]}"; do
#    local dockerfile
#    if ! dockerfile="$(docker.services.get_Dockerfile "$service")"; then
#      log.megawarn "No Dockerfile nor Dockerfile.unified found: $PWD/backend/services/$service."
#      continue
#    fi
#    log.megatitle "building service #$i ($dockerfile): $service"
#    local failures=$((0))
#    vex docker build --build-arg name="$service" -t artifactory.rdlab.local/microservices-docker-sandbox-local/"$service":latest -f "$dockerfile" ./backend/services
#    if [[ "$?" != 0 ]]; then failures=$((failures+1)); fi
#  done
#  return $failures
}

alias d.i.n=docker.images.names
alias d.i.i=docker.images.ids
alias d.i.r=docker.images.remove
alias d.i.b=docker.images.build_by_service
alias d.i.bs=docker.images.build_by_services

}

# ---------[ Containers ]-----------
{

function docker.containers.ids() {
  vex docker ps --all --quiet
}
function docker.containers.names() {
  vex "docker ps -a | awk 'FNR >1 {print \$NF}'"
}

# # docker.containers.stop
function docker.containers.stop() {
  log.title "docker.containers.stop($*)"
  local positional=()
  set -- "${positional[@]}"
  local stop_these=($(docker.containers.ids))
  log.debug "stop_these: ( ${stop_these[*]} )"
  if [[ -z "$stop_these" ]]; then
    # nothing to stop
    return 0
  fi
  vex docker stop "${stop_these[*]}"
  return $?
}

# # docker.containers.remove
function docker.containers.remove() {
  # TODO: accept e.g 'pytest' then grep. docker ps -a | grep pytest | awk '{print $1}' | xargs -n1 docker rm -f
  log.title "docker.containers.remove()"
  local positional=()
  set -- "${positional[@]}"
  local remove_these=($(docker.containers.ids))
  log.debug "remove_these: ( ${remove_these[*]} )"
  local exitcode
  if [[ -z "$remove_these" ]]; then
    # nothing to remove
    exitcode=0
  else
    vex docker container rm -v -f "${remove_these[*]}"
    exitcode=$?
  fi
  vex docker container prune -f
  return $exitcode
}

# # docker.containers.logs.grep <GREP OPTION...> [-- docker logs OPTIONS...]
function docker.containers.logs.grep(){
	[[ -z "$1" ]] && { log.fatal "Must specify at least 1 grep arg" ; return 1 ; }
	local grep_args=()
	local docker_logs_args=()
	local parse_docker_logs_args=false
	while [[ $# -gt 0 ]]; do
	  case "$1" in
	    --) parse_docker_logs_args=true ;;
	    *) if $parse_docker_logs_args; then
	    		docker_logs_args+=("$1")
	    	 else
	    	 	grep_args+=("$1")
	    	 fi ;;
	  esac
	  shift
	done
	local container
	local no_results=()
	while read -r container; do
		if docker logs "$container" "${docker_logs_args[@]}" 2>&1 | command grep -q "${grep_args[@]}"; then
			log.megasuccess "$container"
			docker logs "$container" "${docker_logs_args[@]}" 2>&1 | grep --color=always "${grep_args[@]}"
		else
			no_results+=("$container")
		fi
	done <<< "$(docker.containers.names)"
	if [[ -n "${no_results}" ]]; then
		log.megawarn "Containers without matches:"
		echo "${no_results// /, }"
	fi
}
# # docker.containers.logs.dump_all_except <OUT_DIR> [-w] [-e REGEX...]
# -w for overwrite log files if exist, and not append
# -e REGEX to exclude container (can be multiple)
# ## Example
# docker.containers.logs.dump_all_except dockerlogs -w -e reports -e frontend -e zookeeper -e jaeger -e email -e prometheus -e push -e grafana -e bucket -e gdpr -e elasticsearch -e kibana
function docker.containers.logs.dump_all_except() {
  if [[ -z "$1" ]]; then
    log.fatal "must specify out dir"
    return 1
  fi
  if [[ ! -d "$1" ]]; then
    log.warn "not a dir: $1"
    if ! confirm "create $1?"; then
      log.warn "aborting"
      return 3
    fi
    if ! vex mkdir "$1"; then
      log.fatal Failed
      return 1
    fi
  fi
  local outdir="$1"
  shift
  local overwrite
  local exclude_regexs=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
    -e)
      exclude_regexs+=("$2")
      shift 2 ;;
    -w)
      overwrite=true
      shift ;;
    *)
      log.fatal "unexpected arg: $1"
      return 1 ;;
    esac
  done

  local container_names=()
  while read -r full_container_name; do
    container_names+=("$full_container_name")
  done <<< "$(docker.containers.names)"
  local short_container_names=()
  local short_container_names_str
  import pyfns.sh --if-undefined=py.print
  if short_container_names_str=$(echo "${container_names[*]}" | py.print 'line[next(i for i, c in enumerate( lines[0]) if lines[1][i] != c ) -1 :]'); then
    echo "$short_container_names_str" | while read -r short_container_name; do
      short_container_names+=("$short_container_name")
    done
  else
    log.warn "failed running python go get short container names; defaulting to full container names"
    short_container_names=("${container_names[@]}")
  fi
  log.debug "short_container_names: $short_container_names"
  # First pass: set file permissions and empty their contents if -w arg
  for container_name in "${short_container_names[@]}"; do
    if [[ ! -e "$outdir"/"$container_name".log ]]; then
      continue
    fi
    sudo chmod 777 "$outdir"/"$container_name".log
    if [[ -s "$outdir"/"$container_name".log ]]; then

      if [[ -n "$overwrite" ]]; then
        # empty file even if it's skipped
        echo "" >"$outdir"/"$container_name".log
      else
        for reg in "${exclude_regexs[@]}"; do
          if echo "$container_name" | grep -qP "$reg"; then
            continue 2
          fi
        done
        echo "\n\n\n\n==============================[  $(date)  ]==============================\n\n\n\n" >>"$outdir"/"$container_name".log
      fi
    fi
  done
  # second pass
  local i
  for ((i = 0; i < ${#short_container_names}; i++)); do
    local container_name="${short_container_names[i]}"
    log.debug "container_name: $container_name"
    for reg in "${exclude_regexs[@]}"; do
      if echo "$container_name" | grep -qP "$reg"; then
        log.notice "skipping $container_name"
        continue 2
      fi
    done
    local full_container_name="${container_names[i]}"
    log.success "dumping: $full_container_name"
    (docker logs "$full_container_name" --follow 2>/dev/null >> "$outdir"/"$container_name".log &)
  done

}

# # docker.containers.logs.dump <OUT_DIR> [-i REGEX...] [-w]
function docker.containers.logs.dump() {
  if [[ -z "$1" ]]; then
    log.fatal "must specify out dir"
    return 1
  fi
  if [[ ! -d "$1" ]]; then
    log.warn "not a dir: $1"
    if ! confirm "create $1?"; then
      log.warn "aborting"
      return 3
    fi
    if ! vex mkdir "$1"; then
      log.fatal Failed
      return 1
    fi
  fi
  local outdir="$1"
  shift
  local overwrite
  local include_regexs=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
    -i)
      include_regexs+=("$2")
      shift 2 ;;
    -w)
      overwrite=true
      shift ;;
    *)
      log.fatal "unexpected arg: $1"
      return 1 ;;
    esac
  done

  local container_names=()
  while read -r full_container_name; do
    container_names+=("$full_container_name")
  done <<< "$(docker.containers.names)"
  local short_container_names=()
  local short_container_names_str
  import pyfns.sh --if-undefined=py.print
  if short_container_names_str=$(echo "${container_names[*]}" | py.print 'line[next(i for i, c in enumerate( lines[0]) if lines[1][i] != c ) -1 :]'); then
    while read -r short_container_name; do
      short_container_names+=("$short_container_name")
    done <<< "$short_container_names_str"
  else
    log.warn "failed running python go get short container names; defaulting to full container names"
    short_container_names=("${container_names[@]}")
  fi
  log.debug "short_container_names: $short_container_names"
  # First pass: set file permissions and empty their contents if -w arg
  for container_name in "${short_container_names[@]}"; do
    if [[ ! -e "$outdir"/"$container_name".log ]]; then
      continue
    fi
    # sudo chmod 777 "$outdir"/"$container_name".log
    if [[ -s "$outdir"/"$container_name".log ]]; then

      if [[ -n "$overwrite" ]]; then
        # empty file even if it's skipped
        echo "" >"$outdir"/"$container_name".log
      else
        for reg in "${include_regexs[@]}"; do
          if command grep -qP "$reg" "$container_name"; then
            printf "\n\n\n\n==============================[  %s  ]==============================\n\n\n\n" "$(date)" >>"$outdir"/"$container_name".log
          fi
        done
      fi
    fi
  done
  # second pass
  local i
  for ((i = 0; i < ${#short_container_names}; i++)); do
    local container_name="${short_container_names[i]}"
    #    log.debug "container_name: $container_name"
    local full_container_name="${container_names[i]}"
    for reg in "${include_regexs[@]}"; do
      if command grep -qP "$reg" "$container_name"; then
        log.success "dumping: $full_container_name into $outdir/$container_name.log"
        (docker logs "$full_container_name" --follow 2>/dev/null >>"$outdir"/"$container_name".log &)
      fi
    done
  done

}

# # docker.containers.logs.empty_dumped_files <LOGS_LOCATION>
function docker.containers.logs.empty_dumped_files() {
  if [[ -z "$1" ]]; then
    log.fatal "must specify out dir"
    return 1
  fi
  if [[ ! -d "$1" ]]; then
    log.warn "$1 does not exist, not emptying anything"
    return 1
  fi
  command ls "$1" | while read -r file; do
    echo "" >"$1/$file" && log.success "emptied $file" || log.warn "failed emptying $file"

  done
}

# # docker.containers.logs.clear <--all / SERVICE...>
function docker.containers.logs.clear(){
  if [[ ! "$1" ]]; then
    log.fatal "$0: not enough args (got ${#$})"
    return 1
  fi

  if [[ "$1" == --all ]]; then
    sudo su -p -c "docker compose ps --all | cut -d $'\n' -f 3- | cut -d ' ' -f 1 | while read -r full_container_name; do logfile=\"\$(docker inspect --format=\"{{.LogPath}}\" \"\$full_container_name\")\"; echo \"\x1b[1m\$full_container_name\x1b[0m\"; du -h \$logfile; sudo echo '' > \$logfile; echo 'CLEARED\n'; done"
    return $?
  fi
  for service in $@; do
    sudo su -<<-EOF
    logfile=$(docker inspect --format='{{.LogPath}}' $service)
    logsize="$(du -h "$logfile" | cut -d $'\t' -f 1)"
    echo "" > $logfile
    echo "Cleared $service logs $logsize"
EOF
  done
  return $?
}

alias d.con.i=docker.containers.ids
alias d.con.n=docker.containers.names
alias d.con.s=docker.containers.stop
alias d.con.r=docker.containers.remove
alias d.con.l.dae=docker.containers.logs.dump_all_except
alias d.con.l.d=docker.containers.logs.dump
alias d.con.l.edf=docker.containers.logs.empty_dumped_files
alias d.con.l.c=docker.containers.logs.clear
alias d.con.l.g=docker.containers.logs.grep

}

# ---------[ Services ]-----------
{

# # docker.services.names [--active]
function docker.services.names() {
  if [[ "$1" == --active ]]; then
    local containers=$(docker.containers.names)
    local service
    docker-compose ps --services | while read -r service; do
      if command grep -q "$service" <<< "$containers"; then
        echo "$service"
      fi
    done | sort -h
  else
    docker-compose ps --services | sort -h
  fi
  return $?
}

# # docker.services.stop [-e, --exclude EX_REGEX [-e, --exclude EX_REGEX...]]
# Does `docker compose stop` on `docker compose ps --services`.
# ## Example
# docker.services.stop -e kafka -e zookeeper
function docker.services.stop() {
  log.title "docker.services.stop($*)"
  local dont_stop=()
  local positional=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
    -e|--exclude)
      dont_stop+=("$2")
      shift 2 ;;
    *)
      log.fatal "unknown argument: $1"
      return 1 ;;
    esac
  done
  set -- "${positional[@]}"
  log.debug "dont_stop: ( ${dont_stop[*]} )"
  local stop_these=()
  local service
  for service in $(docker.services.names); do
    for skip_regex in "${dont_stop[@]}"; do
      if echo "$service" | command grep --color=never -q -P "$skip_regex"; then
        log.notice "skipping $service"
        continue 2
      fi
    done
    stop_these+=("$service")
  done
  log.debug "stop_these: ( ${stop_these[*]} )"
  if [[ -z "$stop_these" ]]; then
    # nothing to stop
    return 0
  fi
  vex docker compose stop "${stop_these[*]}"
  return $?

}

# # docker.services.restart [--active]
# docker.services.restart --active | while read -r s; do docker logs $s | grep InconsistentClusterIdException; done
function docker.services.restart() {
  docker.services.names "$@" | xargs -n1 -P "${#$}" docker compose restart
}

# # docker.services.get_Dockerfile <dirname>
# docker.services.get_Dockerfile customconfig
function docker.services.get_Dockerfile() {
  if [[ -z "$1" ]]; then
    log.fatal "${0} expecting 1 SERVICE arg, got nothing"
    return 1
  fi
  setopt localoptions globsubst
  local service="$1"
	shift
  local matches=("**/${service}/Dockerfile")
  if [[ -z "$matches" ]]; then
		log.fatal "No Dockerfile found for $service"
		return 1
	fi
	if [[  "${#matches[@]}" -ge 2 ]]; then
		log.fatal "Ambiguous, got ${#matches[@]} Dockerfiles for ${service}: ${matches[*]}"
		return 1
	fi
  printf "%s" "${matches[1]}"
}

alias d.s.n=docker.services.names
alias d.s.s=docker.services.stop
alias d.s.r=docker.services.restart
alias d.s.D=docker.services.get_Dockerfile

}

# ---------[ Networks ]-----------
{

# # docker.networks.ids [docker network ls args...]
# Convenience for `docker network ls -q "$@"`.
function docker.networks.ids() {
  vex docker network ls -q "$@"
}

# # docker.networks.names [docker network ls args...]
# Convenience for `docker network ls "$@" | awk 'FNR >= 2 {print $3}'`.
function docker.networks.names() {
  vex "docker network ls "$@" | awk 'FNR >= 2 {print \$2}'"
}

# # docker.networks.remove [docker network rm args...]
# Removes all networks except `bridge`, `host`, `null` and `none`; then prunes.
function docker.networks.remove() {
  log.title "docker.networks.remove $*"
  [[ "$1" ]] && {
    local network_name
    docker.networks.names | while read -r network_name; do
      [[ "$network_name" =~ (bridge|host|null|none) ]] && continue
      vex docker network rm "$network_name" "$@"
    done
  }
  vex docker network prune -f

}
alias d.n.i=docker.networks.ids
alias d.n.r=docker.networks.remove
alias d.n.n=docker.networks.names
# complete -o default -C 'compgen -W "-f --filter --format --help --no-trunc -q --quiet"' docker.networks.ids docker.networks.names

}

# ---------[ Volumes ]-----------
{

function docker.volumes.ids() {
  vex docker volume ls -q "$@"
}


# # docker.volumes.remove [VOLUME... [docker volume rm OPTIONS]]
function docker.volumes.remove() {
  log.title "docker.volumes.remove($*)"

  local remove_these=()
  local docker_volume_rm_args=()
  if [[ "$1" ]]; then
		while [[ $# -gt 0 ]]; do
			case "$1" in
			-*) docker_volume_rm_args+=("$1") ;;
			*) remove_these+=("$1") ;;
			esac
			shift 1
		done
	else
		remove_these=("$(docker.volumes.ids)")
	fi
  log.debug "remove_these: ( ${remove_these[*]} )"
  local volume_id
  echo "${remove_these[*]}" | while read -r volume_id; do
    vex docker volume rm -f "$volume_id" "${docker_volume_rm_args[@]}"
  done
  vex docker volume prune -f
  return $?

}

alias d.v.i=docker.volumes.ids
alias d.v.r=docker.volumes.remove

}

# ---------[ docker compose ]-----------
{
# # docker.compose.diff <DOCKER_COMPOSE_FILE_1> <DOCKER_COMPOSE_FILE_2>
function docker.compose.diff() {
  if [[ -z "$2" ]]; then
    log.fatal "$0 requires 2 file paths"
    return 1
  fi
  python3 -OO -IBqc "import yaml
from pathlib import Path
f1 = set(yaml.load(Path('''$1''').open(), yaml.loader.Loader)['services'])
f2 = set(yaml.load(Path('''$2''').open(), yaml.loader.Loader)['services'])
print(f'\n\x1b[1monly in first file:\x1b[0m\n')
for k in sorted(f1 - f2):
    print(k)
print(f'\n\x1b[1monly in second file:\x1b[0m\n')
for k in sorted(f2 - f1):
    print(k)
  "
}

# # docker.compose.services [DOCKER_COMPOSE_FILE=docker-compose.yaml]
# Prints out the names of the services in DOCKER_COMPOSE_FILE
function docker.compose.services() {
  local docker_compose_file="${1:-docker-compose.yaml}"
  python3 -OO -IBqc "import yaml
for k in  sorted( list ( yaml.load(open('''${docker_compose_file}'''), yaml.loader.Loader )['services'] ) ):
    print(k)
  "
}

# # docker.compose.deps <SERVICE> [SERVICE...]
# ## Examples:
# ```bash
# docker.compose.deps gateway-isp
# docker.compose.deps gateway-isp emailgateway
# ```
function docker.compose.deps() {
  log.title "docker.compose.deps($*)"
  if [[ ! "$1" ]]; then
    log.fatal "$0: Not enough args (expected at least 1 service)"
    return 1
  fi

  python3 -OO -IBq <<EOF
#!/usr/bin/python3
import sys
import yaml
from pathlib import Path
from collections import defaultdict
from pprint import pprint as pp

def usage():
    this_file = Path(sys.argv[0]).name
    print(f'''
Usage:
------

python3 {this_file} <SERVICE> [SERVICE...]

Examples:
  python3 {this_file} gateway-isp
  python3 {this_file} gateway-isp emailgateway
    ''')


def main():
    services = '$@'.split()
    if len(services) < 1:
        print('NOT ENOUGH ARGUMENTS')
        usage()

        sys.exit(1)
    docker_compose_yml = Path('./docker-compose.yaml')
    docker_compose = yaml.load(docker_compose_yml.open(), yaml.loader.Loader)
    docker_compose_services = docker_compose.get('services', {})

    for service in services:
        if service not in docker_compose_services:
            sys.exit(f'{service} does not exist in {docker_compose_yml} services')

    # dependencies[ accounts ] : { direct : set, indirect : set, unified : set }
    dependencies = defaultdict(dict)
    all_unified_dependencies = set()

    print(f'\033[4;1;97mINDIVIDUAL SERVICES\033[0m\n', file=sys.stderr)
    for service in services:
        dependencies[service]['direct'] = set()
        dependencies[service]['indirect'] = set()
        #    dependencies[service]['unified'] = set()
        direct_deps = docker_compose_services.get(service, {}).get('depends_on')
        if direct_deps:
            dependencies[service]['direct'] |= set(direct_deps)
            for direct_dep in dependencies[service]['direct']:
                indirect_deps = docker_compose_services.get(direct_dep, {}).get('depends_on')
                if indirect_deps:
                    dependencies[service]['indirect'] |= set(indirect_deps)
        dependencies[service]['unified'] = dependencies[service]['direct'] | dependencies[service]['indirect']
        if len(services) > 1:
            all_unified_dependencies |= dependencies[service]['unified']
        print(f'\033[4;1m{service}\033[0m', file=sys.stderr)
        print(f'\033[4mdirectly depends on:\033[0m', file=sys.stderr)
        [print(s, file=sys.stderr) for s in sorted(dependencies[service]['direct'])]
        print(f'\n\033[4mits dependencies depend on:\033[0m', file=sys.stderr)
        [print(s, file=sys.stderr) for s in sorted(dependencies[service]['indirect'])]
        print(f'\n\033[4munion of all of the above:\033[0m', file=sys.stderr)
        [print(s, file=sys.stderr if all_unified_dependencies else sys.stdout) for s in sorted(dependencies[service]['unified'])]
        print('\n', file=sys.stderr)

    if all_unified_dependencies:
        print(f'\033[4;1;97mTHE {len(dependencies)} SERVICES ABOVE, IN TOTAL, DEPEND ON:\033[0m\n', file=sys.stderr)
        [print(s) for s in sorted(all_unified_dependencies)]


if __name__ == '__main__':
    main()

EOF
  return $?
}

# # docker.compose.create_file_without_services <IN_PATH> <OUT_PATH> <SERVICE> [SERVICE...]
function docker.compose.create_file_without_services() {
  if [[ -z "$3" ]]; then
    log.fatal "$0: Not enough args (expected at least 3; <IN_PATH> <OUT_PATH> <SERVICE> [SERVICE...])"
    return 1
  fi
  local inpath="$1"
  shift
  local outpath="$1"
  shift
  local services=("$@")
  python3 -OO -IBqc "import yaml
from pathlib import Path
import sys
inpath = Path('''$inpath''')
if not inpath.exists():
    sys.exit(f'{inpath} does not exist')
outpath = Path('''$outpath''')
if outpath.exists():
    sys.exit(f'{outpath} exists')
filedata = yaml.load3(inpath.open(), yaml.loader.Loader)
services_to_remove = '''$services'''.split()
for remove_this_service in services_to_remove:
    try:
        del filedata['services'][remove_this_service]
    except KeyError:
        print(f'Ignoring KeyError: {remove_this_service} does not exist in {inpath}')
with open(outpath, 'w') as outfile:
    yaml.dump(filedata, outfile)
# print(filedata['services'])
  "
  return $?
}

# # docker.compose.create_file_without_all_services_except <IN_PATH> <OUT_PATH> <SERVICE> [SERVICE...] [-n, --dry-run]
function docker.compose.create_file_without_all_services_except() {
  if [[ -z "$3" ]]; then
    log.fatal "$0: Not enough args (expected at least 3: <IN_PATH> <OUT_PATH> <SERVICE> [SERVICE...] [-n, --dry-run])"
    return 1
  fi
  local inpath="$1"
  shift
  local outpath="$1"
  shift
  local services=("$@")
  python3 -OO -Iqc "import yaml
from pathlib import Path
import sys
inpath = Path('''$inpath''')
if not inpath.exists():
    sys.exit(f'failed: {inpath} does not exist')
outpath = Path('''$outpath''')
if outpath.exists() and outpath.samefile(inpath):
    sys.exit(f'failed: {inpath} and {outpath} are the same file')
docker_compose = yaml.load(inpath.open(), yaml.loader.Loader)
services_to_keep = set('''$services'''.split())

dry_run=False

for arg in set(services_to_keep):
    # -n, --dry-run hack
    if arg in ('-n', '--dry-run'):
        dry_run=True
        services_to_keep.remove(arg)
        break


services_to_remove = set(docker_compose['services'].keys()) - services_to_keep
print(f'\n\x1b[1mkeeping:\x1b[0m\n')
[print(s) for s in sorted(services_to_keep)]
print(f'\n\x1b[1mremoving:\x1b[0m\n')
[print(s) for s in sorted(services_to_remove)]

if dry_run:
    print(f'\n\x1b[1mnot writing anything, dry run\x1b[0m')
else:
    for remove_this_service in services_to_remove:
        try:
            del docker_compose['services'][remove_this_service]
        except KeyError:
            print(f'Ignoring KeyError: {remove_this_service} does not exist in {inpath}')

    with open(outpath, 'w') as outfile:
        yaml.dump(docker_compose, outfile)

    print(f'\n\x1b[1mwrote to {outfile} successfully\x1b[0m')
  "
  return $?
}

# # docker.compose.up [docker compose-FILE SUFFIX...] <SERVICE...> [-e,--entrypoint ENTRYPOINT] [docker compose UP ARG...]
# Examples:
# ```bash
# docker.compose.up dev patch
# docker.compose.up job_operator
# ```
function docker.compose.up(){
  import arr.sh --if-undefined arr.contains
  local docker_compose_files=(-f docker-compose.yaml)
  local -a available_services
  available_services=($(docker.compose.services)) || return $?
  local services=()
  local docker_compose_up_args=(-d)
  local entrypoint
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -e|--entrypoint*)
        if [[ "$1" == *=* ]]; then
          entrypoint="${1/*=/}"
        else
          entrypoint="$2"
          shift
        fi ;;
      *)
        if [[ -e "docker-compose-${1}.yaml" ]] && ! (( ${docker_compose_files[(Ie)"docker-compose-${1}.yaml"]} )); then
          docker_compose_files+=(-f "docker-compose-${1}.yaml")
        elif [[ -e "docker-compose-${1}.yml" ]] && ! (( ${docker_compose_files[(Ie)"docker-compose-${1}.yml"]} )); then
          docker_compose_files+=(-f "docker-compose-${1}.yml")
        elif [[ "$1" = -* ]]; then
          docker_compose_up_args+=("$1")
        elif (( ${available_services[(Ie)${1}]} )); then
          services+=("$1")
        else
          log.warn "$1 is not a docker-compose-${1}.y*ml file, not a docker compose up argument, nor a known service." -L -x -n
          confirm "Do you want to add $1 to the list of services anyway?" || return 1
          services+=("$1")
        fi ;;
    esac
		shift
  done

  if [[ "$entrypoint" ]]; then
    local last_specified_service
    if ! last_specified_service="$(arr.last "${services[@]}")"; then
      log.fatal "entrypoint was specified, but no services specified. Need at least one service."
      return 1
    fi
    local docker_compose_entrypoint_content="$(printf "version: '3'\nservices:\n  %s:\n    user: root\n    entrypoint: %s" "$last_specified_service" "$entrypoint")"
    local docker_compose_file
    local entrypoint_docker_compose_file

    # if a docker compose file with matching content already exists, use it instead of creating a new one
    for docker_compose_file in *y*ml; do
      if diff -qwEbBZ "$docker_compose_file" <(printf "%b" "$docker_compose_entrypoint_content") &>/dev/null; then
        log.success "Found $docker_compose_file file with entrypoint: $entrypoint"
        entrypoint_docker_compose_file="$docker_compose_file"
        break
      fi
    done
    if [[ ! "$entrypoint_docker_compose_file" ]]  # create a docker compose file
    then
      local random_str="$(randstr 4)"
      entrypoint_docker_compose_file="docker-compose-$random_str.yaml"
      printf %b "$docker_compose_entrypoint_content" > "$entrypoint_docker_compose_file"
      log.success "Created $docker_compose_file file with ${Cc}entrypoint: $entrypoint"
    fi
    docker_compose_files+=(-f "$entrypoint_docker_compose_file")
  fi

	[[ -z "$services" ]] && services=(${available_services[@]})
  vex docker compose "${docker_compose_files[@]}" up "${docker_compose_up_args[@]}" "${services[@]}"
}

alias d.c.diff=docker.compose.diff
alias d.c.s=docker.compose.services
alias d.c.deps=docker.compose.deps
alias d.c.cw=docker.compose.create_file_without_services
alias d.c.cwe=docker.compose.create_file_without_all_services_except
alias d.c.u=docker.compose.up

}

# ---------[ exec ]-----------

# # de.bash <CONTAINER> [bash options...]
function de.bash(){
	local container="$1"
  shift 1 || { log.error "$0: Not enough args (expected 1, got ${#$}). Usage:\n$(docstring "$0")"; return 2; }
  docker exec -it "$container" bash "$@"
}

# ---------[ General ]-----------

{

function docker.destroy_everything_except_images() {
  log.megatitle "Running docker compose down -v --remove-orphans"
  vex docker compose down -v --remove-orphans
  log.megatitle "Removing all containers"
  vex docker.containers.remove
  log.megatitle "Removing all networks"
  vex docker.networks.remove
  log.megatitle "Removing all volumes"
  vex docker.volumes.remove --all
  log.megatitle "Stopping all services"
  vex docker.services.stop
}

function docker.destroy_everything() {
  docker.destroy_everything_except_images
  log.megatitle "Removing all images"
  docker.images.remove --all
  docker system prune --volumes --all --force
}

# # docker.down_build_up <SERVICE> [SERVICE...]
function docker.down_build_up(){
  if [[ ! "$1" ]]; then
    log.fatal "$0: Not enough args (expected 1, got ${#$}. Usage: $0 <SERVICE> [SERVICE...])"
    return 1
  fi

  for service in "$@"; do
    if ! docker.services.get_Dockerfile "$service"; then
      log.fatal "Could not find Dockerfile of '$service'"
      return 1
    fi
  done
  log.megatitle "docker compose down -v"
  if ! vex docker compose -f docker-compose.yaml -f docker-compose-dev.yaml -f docker-compose-patch.yaml down -v; then
    log.fatal "failed docker compose down"
    return 1
  fi
  log.megatitle "docker.images.build_by_service $*"
  if ! docker.images.build_by_service "$@"; then
    log.fatal "failed docker.images.build_by_service"
    return 1
  fi
  log.megatitle "docker compose up -d"
  if ! vex docker compose -f docker-compose.yaml -f docker-compose-dev.yaml -f docker-compose-patch.yaml up -d; then
    log.fatal "failed docker compose up"
    return 1
  fi
  return 0



}

# # docker.export_container_vars
function docker.export_container_vars(){
  local container_names=()
  local short_container_names=()
  local full_container_name
  docker.containers.names | while read -r full_container_name; do
    container_names+=("$full_container_name")
    short_container_names+=("$(echo "$full_container_name" | cut -d _ -f 2)")
  done

  local i container_name
  for ((i = 1; i < (( ${#short_container_names} + 1 )); i++)); do
    container_name=$(echo "${short_container_names[i]}" | tr '[:lower:]' '[:upper:]' | tr -d '-')
    full_container_name="${container_names[i]}"
    eval "export $container_name=$full_container_name"
    log.debug "exported: $container_name=$full_container_name"
  done
}

# # docker.restart
# Restart docker engine
function docker.restart(){
  log.megatitle "NOT Restarting docker engine"
  # sudo systemctl daemon-reload && sudo systemctl restart docker
  # sudo service docker restart
  # sudo systemctl restart docker.socket; sudo systemctl restart docker.service
}

alias d.deei=docker.destroy_everything_except_images
alias d.de=docker.destroy_everything
alias d.dbu=docker.down_build_up
alias d.ecv=docker.export_container_vars

}

# ---------[ Postgres ]-----------

# # de.psql <CONTAINER> [-U, --username USERNAME=postgres] [-h, --host HOST=host.docker.internal] [psql options]
# Examples:
# ```bash
# de.psql pqls-service-db-1 -c "SELECT tablename FROM pg_catalog.pg_tables WHERE schemaname != 'pg_catalog' AND schemaname != 'information_schema';"
# de.psql pqls-service-db-1 -c "SELECT * FROM blueprint"
# de.psql app-test-db-1 -c 'DROP DATABASE app_db;'
# ```
function de.psql(){
	# -d postgres
	local username
	local host
	zparseopts -D -E - U::=username -username::=username h::=host -host::=host
	local container="$1"
	shift 1 || { log.error "$0: Not enough args (expected 1, got ${#$}). Usage:\n$(docstring "$0")"; return 2; }
	[[ $username ]] && username=${username#*=} || username=postgres
	[[ $host ]] && host=${host#*=} || host=host.docker.internal
	log.debug "username: ${username} | host: ${host}"
	docker exec -it "$container" psql -U "$username" -h "$host" "$@"
}

