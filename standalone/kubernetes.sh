# https://download-ib01.fedoraproject.org/pub/epel/7/x86_64/Packages/
# xclip: https://download-ib01.fedoraproject.org/pub/epel/7/x86_64/Packages/x/xclip-0.12-5.el7.x86_64.rpm

alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'


[[ -f "/root/.local/share/lscolors.sh" ]] && source "/root/.local/share/lscolors.sh"

export COLORTERM=truecolor
export TERM=xterm-256color

unalias ls 2>/dev/null
function ls(){
  local dest="${1:-$PWD}"
  command ls "$dest" -Flahv --color=auto --group-directories-first "${@:2}" && \
  printf "\n\x1b[1;97m%s\x1b[0m\n\n" "$(realpath "$dest")"
}
function cd() { builtin cd "$@" && ls ; }

# =========================================
# ===============[ kubectl ]===============
# =========================================
# https://kubernetes.io/docs/reference/kubectl/cheatsheet/
# kubectl -n "${K_NS}" delete pods rsevents-66468bd865-4jpqv
# kubectl -n "${K_NS}" scale deployment --replicas=0 rsevents
# KUBE_EDITOR=micro k edit deployments.apps rsevents
# cat dashboard_token dashboard_url

export K_NS="${K_NS:-gilad-sandbox}"

alias kg="kubectl -n ${K_NS}"
#complete -F __start_kubectl kg
#kubectl completion bash | sed -E 's/(complete -o default .*-F __start_kubectl) kubectl/\1 kg/g' | source /dev/stdin # maybe not needed?

# kubectl get deployments.apps -n "${K_NS}" gateway-isp -o yaml | sed 's/image: secure-management\/gateway-isp:30.1.500.87/image: local-0\/gateway-isp:latest/g' | kubectl replace -f /dev/stdin
k -n gilad-sandbox describe deployments eta-api

function k.pod(){
  kubectl -n "${K_NS}" get pods --no-headers | grep "${1}" | cut -d ' ' -f 1
}
function k.all.greplogs() {
	local pod
	kubectl -n "${K_NS}}" get pods --no-headers | cut -d ' ' -f 1 | while read -r pod; do
		if ! res="$(kubectl -n "${K_NS}" logs "$pod" | grep "$@")" || [[ -z "$res" ]]; then
			continue
		fi
		printf "\n\x1b[97;1m%s:\x1b[0m\n" "${pod}"
		echo "$res"
	done
}
function k.all.grepenv(){
	local pod
	kubectl -n "${K_NS}}" get pods --no-headers | cut -d ' ' -f 1 | while read -r pod; do
		if ! res="$(kubectl -n "${K_NS}" exec -t "$pod" -- env 2>/dev/null | grep "$@")" || [[ -z "$res" ]]; then
			continue
		fi
		printf "\n\x1b[97;1m%s:\x1b[0m\n" "${pod}"
		echo "$res"
	done
}

function k.pods.names(){
  log.debug "kubectl -n ${K_NS} get pods --no-headers $* | cut -d ' ' -f 1"
  kubectl -n "${K_NS}" get pods --no-headers "$@" | cut -d ' ' -f 1
  return $?
}

function k.logs(){
  local app="$1"
  shift || return 1
  log.debug "kubectl -n ${K_NS} logs -l app=$app -f"
  kubectl -n "${K_NS}" logs -l app="$app" -f
  return $?
}

function k.nodeofpod(){
  local app="$1"
  shift || return 1
  log.debug "kubectl -n ${K_NS} get pods -o wide -l app=$app | grep $app | grep -E -o 'k8s-n-[0-9]+'"
  kubectl -n "${K_NS}" get pods -o wide -l app="$app" | grep "$app" | grep -E -o 'k8s-n-[0-9]+'
}

function k.asmver(){
  # kubectl -n "${K_NS}}" get asm-version -o jsonpath='{.items[0].metadata.name}'
  local app="$1"
  shift || return 1
  log.debug "kubectl -n ${K_NS} get pods -l app=$app -o yaml | grep -o -m1 -E \"image: .*$app:(.+)\""
  kubectl -n "${K_NS}" get pods -l app="$app" -o yaml | grep -o -m1 -E "image: .*$app:(.+)"
}

function k.exec-bash(){
  local pod="$1"
  shift || return 1
  log.debug "kubectl -n ${K_NS} exec -it $pod -- bash \"$*\""
  kubectl -n "${K_NS}" exec -it "$pod" -- bash "$@"
}
function k.port-forward(){
  :
  kubectl -n "${K_NS}" port-forward deployment/mongo 28015:27017
  kubectl -n "${K_NS}" port-forward pods/mongo-75f59d57f4-4nd6q 28015:27017
  kubectl -n "${K_NS}" port-forward mongo-75f59d57f4-4nd6q 28015:27017

  # Listen on port 6666 on all addresses, forwarding to 5000 in the pod. Afterwards -> curl 0.0.0.0:6666/customization/fonts
  kubectl -n "${K_NS}" port-forward --address 0.0.0.0 customconfig-6864b5db87-lmhnk 6666:5000
}

function k.configmap(){
  :
  # kubectl edit configmap -n <namespace> <configMapName> -o yaml
  # mkdir rs-mult
  # k create configmap rs-mult-cmap --from-file=/root/rs-mult   # must abs path

  # spec:
  #   volumes:
  #     - name: rs-mult-vol-main
  #       configMap:
  #         name: rs-mult-main
  #         defaultMode: 420
  #     - name: rs-mult-vol-test-mocks
  #       configMap:
  #         name: rs-mult-test-mocks
  #         defaultMode: 420
  #     - name: rs-mult-vol-infra-eb-consumers-proto-consumer
  #       configMap:
  #         name: rs-mult-infra-eb-consumers-proto-consumer
  #         defaultMode: 420
  #     - name: rs-mult-vol-infra-eb-consumers-init
  #       configMap:
  #         name: rs-mult-infra-eb-consumers-init
  #         defaultMode: 420
  #   containers:
  #     volumeMounts:
  #       - name: rs-mult-vol-main
  #         mountPath: /app/main/test
  #         readOnly: true
  #         # subPath: sync_handler.py

  # env:
  # - name: RSEVENTS_TESTS_TIMESTAMP
  #   value: '2022-01-02T10:35:05Z'
  # - name: RSEVENTS_TESTS_ACCOUNT_ID
  #   value: GILAD_ACCOUNT_0
  # - name: RSEVENTS_TESTS_DEVICE_ID
  #   value: GILAD_DEVICE_ID_0
  # - name: RSEVENTS_TESTS_ROUTER_ID
  #   value: GILAD_DEVICE_ID_0
  # - name: RSEVENTS_TESTS_USER_ID
  #   value: GILAD_USER_0
  # - name: STATISTICS_INTERVAL_MS
  #   value: '333'
}


# =======================================
# ===============[ Kafka ]===============
# =======================================
#  exec -ti into kafka
#  unset JMX_PORT
#
# -----[ General ]-----
function kafka.general(){
	# https://docs.cloudera.com/runtime/7.2.10/kafka-managing/topics/kafka-manage-cli-overview.html <- examples for each .sh file
 # List topics:
 kafka-topics.sh --list --zookeeper zookeeper:2181

 # find logs with size > 0
 find bitnami/kafka/data/ -name *.log -size +0b -ls | grep TOPIC | sort -r

 unset JMX_PORT; /opt/bitnami/kafka/bin/kafka-run-class.sh kafka.tools.DumpLogSegments --deep-iteration –print-data-log --files /bitnami/kafka/data/__consumer_offsets-10/00000000000000000000.log

 # How many unconsumed messages in topic:
 kafka-consumer-groups.sh --bootstrap-server kafka:9092 --group rsevents --describe --offsets | grep TOPIC | awk '{lag+=$6} END {print lag}'

 # Delete messages:
 /opt/bitnami/kafka/bin/kafka-configs.sh --bootstrap-server kafka:9092 --topic TOPIC --alter --add-config retention.ms=0
 # OR:
 sed -i 's/delete.topic.enable=false/delete.topic.enable=true/g' /opt/bitnami/kafka/config/server.properties
 /opt/bitnami/kafka/bin/kafka-topics.sh --zookeeper localhost:2181 --delete --topic TOPIC
 # OR:
 echo ' {"partitions": [{"topic": "TOPIC", "partition": 0, "offset": 80000}], "version":1 }' > offsetfile.json
 kafka-delete-records.sh --bootstrap-server localhost:9092 --offset-json-file ./offsetfile.json
 for i in $(seq 100); do kafka-delete-records.sh --bootstrap-server localhost:9092 --offset-json-file <( echo "{\"partitions\": [{\"topic\": \"TOPIC\", \"partition\": $i, \"offset\": -1}], \"version\":1 }" ); done

 # Performance test:
 kafka-consumer-perf-test.sh --bootstrap-server localhost:9092 --topic TOPIC --messages 100000 | cut -d ',' -f 5-6
}

# -----[ Publish ]-----
function kafka.publish(){
  kafka-console-producer.sh --broker-list localhost:9092 --topic TOPIC
  #>{"device_event_blocked_traffic":{"message":{"timestamp":"2021-08-23T15:53:00Z","trace_id":"trace_id"}}}
}

# -----[ Consume ]-----
function kafka.consume(){
  kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic TOPIC --from-beginning
  kafka-console-consumer.sh --bootstrap-server kafka-0:9092 --topic ...
  kafka-console-consumer.sh --bootstrap-server kafka-0:9092 --whitelist 'as-rs.*|as-rsevents.*|hs-routers.*|as-hs.*'
}

# -----[ Certs ]-----
function kafka.certs(){
  kubectl -n "${K_NS}" get secret kafka-external-certificates -o jsonpath="{.data['ca\.crt']}" | base64 --decode > /tmp/ca.crt
  kubectl -n "${K_NS}" get secret kafka-external-certificates -o jsonpath="{.data['client\.key']}" | base64 --decode > /tmp/client.key
  kubectl -n "${K_NS}" get secret kafka-external-certificates -o jsonpath="{.data['client\.crt']}" | base64 --decode > /tmp/client.crt
  # or (doesn't completely work):
  # shellcheck disable=SC2259
  ssh $todd kubectl -n "${K_NS}" get secret kafka-external-certificates -o jsonpath="{.data}" \
    | python3 <<-EOF
  import json, sys, base64
  data = json.loads(sys.stdin.read())
  def decode(key):
      return base64.decodebytes(data[key].encode()).decode()
  print(decode('ca.crt'))
EOF
}

# -----[ Connections ]------
function kafka.connections(){
  external_ip="$(k -n "${K_NS}" get svc | grep istio-ingress | python -c 'from sys import stdin; print(stdin.read().split()[3])')"    # e.g 10.xxx.xxx.13
  kafka_host="$(kubectl -n "${K_NS}" get vs | grep -Eo 'kafka.default.[[:alpha:]]+')"   # e.g kafka.default.todd
  ### In /etc/hosts file:
  # <external_ip> isp.default.<machine_name>
  # <external_ip> kafka.default.<machine_name>
  kafka_external_port="$(kubectl -n "${K_NS}" get svc | grep kafka-0 | grep -Po '(?<=:)\w+')"   # e.g 30094
}

# =======================================
# ===============[ Zsh ]=================
# =======================================

function setup_zsh(){
    if { [[ -z "$ZSH" || ! -d "$ZSH" ]] && [[ -d "$HOME/.oh-my-zsh" ]] ; }; then
      # ZSH var is not set, or $ZSH is not a directory, but "$HOME/.oh-my-zsh" is a directory
      export ZSH="$HOME/.oh-my-zsh"
    fi
    if [[ -d "$ZSH" ]]; then
      # See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
      # refined, josh, fino-time
      ZSH_THEME="fino-time"

      plugins=()
      if [[ -d "$ZSH/custom/plugins/zsh-autosuggestions" ]]; then
        plugins+=(zsh-autosuggestions)
      fi
      plugins+=(copybuffer extract kubectl colored-man-pages helm)
      if [[ -d "$ZSH/custom/plugins/fast-syntax-highlighting" ]]; then
        plugins+=(fast-syntax-highlighting)
      fi

      source "$ZSH"/oh-my-zsh.sh

      setopt extendedglob
      setopt auto_menu
      bindkey -M emacs "^ "  _expand_alias
    else
      echo "[WARN] \$ZSH Does not exist: $ZSH" 1>&2
      if type complete &>/dev/null; then
        source <(kubectl completion zsh)
      fi
    fi

}
if [[ -n "$ZSH_VERSION" ]]; then
  if [[ "${SHELL##*/}" == zsh ]]; then
    setup_zsh
  fi
else # not ZSH_VERSION
#  if type complete &>/dev/null; then   # i think .bashrc already loads completions
#    source <(kubectl completion bash)
#    # if [[ -f /root/kg-completion-bash ]]; then
#    #   source /root/kg-completion-bash
#    # fi
#    # if [[ -f /root/k-completion-bash ]]; then
#    #   source /root/k-completion-bash
#    # fi
#  fi
  export PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
fi

declare istio_path=$(find /opt -maxdepth 1 -type d -name 'istio*')
if [ -e "$istio_path" ]; then
  export ISTIO_PATH="$istio_path"
  export PATH="$ISTIO_PATH/bin:$PATH"
  autoload bashcompinit
  bashcompinit
  source "$ISTIO_PATH"/tools/istioctl.bash 2>/dev/null
fi

if type micro &>/dev/null; then
	export EDITOR=micro
fi

#{ ! type isdefined \
#  && source <(wget -qO- https://raw.githubusercontent.com/giladbarnea/bashscripts/master/util.sh) ;

#} &>/dev/null