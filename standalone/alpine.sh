#!/bin/bash
# wget https://raw.githubusercontent.com/giladbarnea/land/master/standalone/alpine.sh --no-check-certificate
# source ./alpine.sh --no-c --no-zsh --no-pip --no-upgrade
# source ./alpine.sh --pylibs --systools --no-zsh

printf "\n------[ %s ]------\n\n" "$(basename "${BASH_SOURCE[0]}")"

##############################################################################
#                     		Sourcing, logging and shims
##############################################################################

[ -z "$THIS_SCRIPT_DIR" ] && THIS_SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]:-$0}")")"
export TERM=xterm-256color
export COLORTERM=truecolor
declare HAS_INTERNET_CONNECTION=true

{
	[ "$(type -t log.info)" = function ] && {
		log.success "log.info() is already defined, not fetching util.sh and log.sh"
		return 0
	}
	for _log_alias in $(alias | grep log | cut -d = -f 1 | cut -d ' ' -f 2); do
		unalias "$_log_alias"
	done
	unset isdefined vex runcmds &>/dev/null
	# source "$THIS_SCRIPT_DIR"/util.sh &>/dev/null && return 0
	if nc -vz -w 1 www.google.com 443 &>/dev/null; then
		# ! type wget &>/dev/null && apk add --no-cache wget && sleep 0.5
		# source <(wget --quiet -T 5 --retry-connrefused=off -O- https://raw.githubusercontent.com/giladbarnea/land/master/{util,log}.sh --no-check-certificate)
		! type curl &> /dev/null && apk add --no-cache curl
		echo "Fetching and sourcing log.sh and util.sh..." 1>&2
		source <(curl --silent https://raw.githubusercontent.com/giladbarnea/land/master/{log,util}.sh)
	else
		echo "nc www.google.com failed!" 1>&2
		HAS_INTERNET_CONNECTION=false
	fi
}

#source_util_and_log_scripts


if [ "$(type -t log.info)" != function ]; then
  HAS_INTERNET_CONNECTION=false
  echo "[ERROR] 'log.info' is not a function, looks like importing util.sh failed. Probably no network access. HAS_INTERNET_CONNECTION: ${HAS_INTERNET_CONNECTION}" 1>&2
  declare positional_args=(--no-install)
  set -- "${positional_args[@]}"
  for level in debug info warn error fatal good title megafatal megasuccess megatitle megawarn notice prompt; do
    eval "alias log.${level}='echo \"[${level}]\"'"
  done
  function isdefined(){ type "$1" &> /dev/null ; }
  function vex(){ echo "Running: $*"; "$@" ; }
  function runcmds(){ for cmd in "$@"; do vex "$cmd"; done; }
else
	HAS_INTERNET_CONNECTION=true
  ! isdefined curl && {
    log.info "Installing curl in the background"
    (apk add --no-cache curl &) &>/dev/null
  }

fi


declare DEBUGFILE_PATH
declare PDBRC_PATH
declare PIP_LIST
declare PIP_LIST_V

# # _pip_list [pip list args...]
# Uses / caches `pip list` and `pip list -v` (exact)
function _pip_list(){
  if [[ "$1" == -v ]]; then
    [[ "$2" ]] && {
      command pip list "$@"
      return $?
    }
    [[ ! "$PIP_LIST_V" ]] && {
    	# "$@" includes -v
      PIP_LIST_V="$(command pip list "$@")"
      exitcode=$?
    }
    if [ $exitcode != 0 ]; then
      command pip list "$@"
    else
      echo "$PIP_LIST_V"
    fi
    return $exitcode
  else
    [[ "$1" ]] && {
      command pip list "$@"
      return $?
    }
    [[ ! "$PIP_LIST" ]] && {
      PIP_LIST="$(command pip list "$@")"
      exitcode=$?
    }
    if [ $exitcode == 0 ]; then
      echo "$PIP_LIST"
    else
      command pip list "$@"
    fi
    return $exitcode
  fi
}
function pip(){
  local args=(--disable-pip-version-check)
  [[ "$1" == list ]] && {
    _pip_list "${@:2}"
    return $?
  }
  if [[ "$1" == install || "$1" == uninstall ]]; then
    PIP_LIST=
    PIP_LIST_V=
  fi
  if [[ "$1" == install && "$2" != "-"* && "$3" != "-"* ]]; then
    args+=(-q --retries=2)
  fi

  command pip "$@" "${args[@]}"
}


if python -m rich &>/dev/null; then
	function prettyjson(){ python -m json.tool --sort-keys | python -m rich.json -i 4 /dev/stdin ; }
elif isdefined bat; then
	function prettyjson(){ python -m json.tool --sort-keys | bat -l json -p ; }
else
	function prettyjson(){ python -m json.tool --sort-keys ; }
fi

function pcurl(){
  curl --silent "$@" | prettyjson
}

##############################################################################
#                     		Helpers and Batch functions
##############################################################################

function safe_append_to_PYTHONPATH(){
	local item="$1"
	shift || return 1
	[[ "$item" == "" || -z "$item" ]] && return 1
	[[ "$PYTHONPATH" =~ .*"${item%/}"/?(:|$) ]] && return 0
	export PYTHONPATH="${PYTHONPATH}:${item}"
	return 0
}
# download_file <URL> <OUTPATH> [--fg]
function download_file(){
  if ! $HAS_INTERNET_CONNECTION; then
    log.error "download_file $* | no network connection, returning 1"
    return 1
  fi
  local url="$1"
  local outpath="$2"
  local background=true
  if [[ "$3" == --fg ]]; then
    background=false
  elif [[ -n "$3" ]]; then
    log.warn "Unknown option: $3. Ignoring."
  fi
  if ! shift 2; then
    log.fatal "download_file(): Expected 2-3 args, got ${#$}. Usage: download_file <URL> <OUTPATH> [--fg]"
    return 1
  fi
  log.title "Downloading ${outpath}, background: $background"
  if $background; then
    (wget --quiet --no-check-certificate -O "$outpath" "$url" --no-check-certificate &) &>/dev/null
    return 0
  else
    wget --no-check-certificate -O "$outpath" "$url" --no-check-certificate
    return $?
  fi
}
function add_apk_repos(){
  log.title add_apk_repos
  local modified=false
  local repo
  for repo in alpine/edge/community alpine/edge/main alpine/edge/testing; do
    if ! grep -q "$repo" /etc/apk/repositories; then
      log.info "Adding $repo to apk repos" -x
      echo "https://dl-cdn.alpinelinux.org/$repo" >>/etc/apk/repositories
      modified=true
    fi
  done

	if $modified; then
	  log.megatitle "Updating apk" -x
	  vex apk update
	else
	  log.success "/etc/apk/repositories already included community and main, nothing modified"
	fi

}
function install_utils(){
	install_rg="${utils[rg]}"
	utils[rg]=false
	if $install_rg; then
	  ! isdefined download_release && {
	    import deployme.sh
	  }
	  # Async in the background, so install_ripgrep fn will have the file already
	  (download_release BurntSushi/ripgrep x86_64-unknown-linux-musl -o ripgrep.tar.gz &) &>/dev/null
	fi
	for x in "${!utils[@]}"; do
	  if ${utils[$x]} && ! isdefined "$x"; then
			log.megatitle "Installing $x" -x
			apk add --update $x
	  fi
	done
	if $install_rg; then
	  install_ripgrep
	fi
}

function install_clibs(){
  log.megatitle "Installing c-related libs" -x
  add_apk_repos
  # Old:
  # apk add .build-deps build-dependencies gcc musl-dev libgcc g++
  # apk add --no-cache python-dev python3-dev python2-dev pkgconfig libc-dev musl libc6-compat linux-headers build-base libffi-dev
  # apk add g++ #
  runcmds ---no-exit-on-error \
    'apk add --no-cache --virtual .build-deps gcc musl-dev libgcc # g++ # build-dependencies' \
    'apk add --no-cache python3-dev python2-dev pkgconfig libc-dev musl libc6-compat linux-headers build-base libffi-dev # python-dev' \
    'apk add g++'
}

function install_pylibs(){
  log.megatitle "install_pylibs()" -x
	if ! isdefined pip; then
	  log.megafatal "'pip' not found; not installing pylibs. https://bootstrap.pypa.io/get-pip.py"
	  return 1
	fi
	if ! echo ${pylibs[@]} | grep -q true; then
	  log.warn "No pylibs is true: not installing pylibs"
	  return
	fi
	local x
	local enabled_pylibs=()
	for x in "${!pylibs[@]}"; do
	  if ${pylibs[$x]}; then
	    if [[ "$x" == pdbpp ]]; then
	      install_pdbpp
	    elif [[ "$x" == ipython ]]; then
	      install_ipython
	    elif [[ "$x" == birdseye ]]; then
	      install_birdseye
	    else
	      log.megatitle "Installing $x" -x
	      enabled_pylibs+=("$x")
	    fi
	  fi
	done
  if [[ "${enabled_pylibs[*]}" ]]; then
    pip install "${enabled_pylibs[@]}"
  fi
}

##############################################################################
#                     		Installers (specific)
##############################################################################

function install_pdbpp(){
  log.megatitle "Installing pdbpp" -x
  local should_install=true
  local pdbpp_pkg pdbpp_rev pdbpp_path
  read -r pdbpp_pkg pdbpp_rev pdbpp_path <<< "$(pip list | grep pdbpp)"
  if [[ -n "$pdbpp_pkg" ]]; then
    if echo "$pdbpp_rev" | grep -q '+g'; then
      log.success "Local forked pdbpp already installed"
      should_install=false
    else
      if confirm "pdbpp vanilla is installed, not fork. Install fork over vanilla?" --no-validate; then
        vex pip uninstall pdbpp
      else
        should_install=false
      fi
    fi
  fi
  if $should_install; then

  	# If we have net access, install git
  	# Otherwise try to install from local wheels and return regardless
    if ! isdefined git; then
      log.title "Installing git" -x
      if vex apk add --update git; then
        sleep 0.5
      else
        local pdbpp_deps=(fancycompleter
                          pdbpp
                          Pygments
                          pyrepl
                          six
                          wmctrl)
        local dep
        for dep in "${pdbpp_deps[@]}"; do
          pip install --no-deps /app/packages/wheels/"$dep"*
        done
        return
      fi
    fi

		# Try to pip install -e
		# First try existing pdbpp dirs in PATH and PYTHONPATH
		# Then try in /app/main/src/pdbpp
		# Lastly just pip install from git into /app/main/src/pdbpp
    local searchpaths="$PATH"
    [[ -n "$PYTHONPATH" ]] && searchpaths+=:"$PYTHONPATH"
    local pathdir
    for pathdir in $(echo "$searchpaths" | tr : $'\n'); do
      if [ -d "$pathdir"/pdbpp ]; then
        if vex pip install -e "$pathdir"/pdbpp; then
        	should_install=false
        else
        	should_install=true
        fi
        break
      fi
    done

    if $should_install && [[ -d /app/main/src/pdbpp ]]; then
      pdbpp_path="/app/main/src/pdbpp"
      vex pip install -e /app/main/src/pdbpp
      should_install=false
    fi

    if $should_install; then
      pdbpp_path="/app/main/src/pdbpp"
      vex pip install -e "git+https://github.com/giladbarnea/pdbpp.git@dev#egg=pdbpp"
    fi
  fi # </should_install>

	# If pdbpp is a git repo, checkout 'dev' branch
  if [[ -d "$pdbpp_path/.git" ]]; then
  	local _gitHEAD="$(head -n 1 $pdbpp_path/.git/HEAD)"
  	if [[ ${_gitHEAD##*/} == dev ]]; then
      log.success "pdbpp is already on dev branch"
    else
      log.title "Checking out dev branch in $pdbpp_path"
      runcmds \
        'builtin cd "$pdbpp_path"' \
          'git checkout dev' \
          'git pull'
      vex builtin cd /app/main
    fi
  fi

  [[ -d "$pdbpp_path/testing" ]] && rm -rf "$pdbpp_path/testing"

	# PYTHONBREAKPOINT
  export PYTHONBREAKPOINT="pdbpp.set_trace"
  log.success "PYTHONBREAKPOINT: $PYTHONBREAKPOINT"

	# Find / download .pdbrc.py and set PDBRC_PATH
  if [[ "$PDBRC_PATH" ]]; then
    if [[ -e "$PDBRC_PATH" ]]; then
      log.success ".pdbrc.py exists in $PDBRC_PATH, not downloading"
    else
      log.warn "PDBRC_PATH is set to $PDBRC_PATH, but it doesn't exist. Finding possibly existing .pdbrc.py and downloading if needed"
      PDBRC_PATH=
    fi
  fi

  if [[ ! "$PDBRC_PATH" ]]; then
    log.debug "no PDBRC_PATH, finding under /app..."
    local pdbrc_path
    [ -d /app ] && pdbrc_path="$(find /app -maxdepth 2 -name .pdbrc.py -print -quit)"
    if [[ ! "$pdbrc_path" ]]; then
      download_file "https://gist.github.com/giladbarnea/25ccc142e31817123a3e88ee358e471f/raw" "$HOME/.pdbrc.py"
      PDBRC_PATH="$HOME/.pdbrc.py"
    else
      log.success ".pdbrc.py was found in $pdbrc_path, not downloading"
      PDBRC_PATH="$pdbrc_path"
    fi
  fi
}

function install_ipython(){
	if ! isdefined ipython; then
		log.megatitle "Installing ipython" -x
    if ! $HAS_INTERNET_CONNECTION; then
      local ipython_deps=(ipython
                          matplotlib_inline
                          pexpect
                          backcall
                          pygments
                          pickleshare
                          jedi
                          setuptools
                          prompt_toolkit
                          traitlets
                          decorator
                          stack_data
                          parso
                          ptyprocess
                          wcwidth
                          pure_eval
                          executing
                          asttokens
                          six)
      local dep
      for dep in "${ipython_deps[@]}"; do
        pip install --no-deps /app/packages/wheels/"$dep"*
      done
      return
    fi
    if ! isdefined git; then
      log.title "Installing git" -x
      apk add --update git
    fi
    if ! vex pip install -e "git+https://github.com/ipython/ipython.git#egg=ipython"; then
      return 1
    fi
	fi

  pip install ipython_autoimport

  if ! confirm "Clone giladbarnea/.ipython?" --no-validate; then
    return 0
  fi
	if [[ ! -d ~/.ipython ]]; then
	  vex git clone https://github.com/giladbarnea/.ipython ~/.ipython
	elif [[ -d ~/.ipython/.git ]]; then
	  local orig_pwd="$(pwd)"
	  builtin cd ~/.ipython && git pull
	  builtin cd "$orig_pwd"
  fi
}

function install_birdseye(){
	log.megatitle "Installing birdseye" -x
	if ! apk list -I | grep -q -F 'g++'; then
		log.title "Installing g++" -x
		apk add --update g++
	fi
	vex pip install birdseye
}

function install_zsh(){
	log.megatitle "Installing zsh" -x
	download_file "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh" zsh_install.zsh
	apk add --update zsh
	if echo ${utils[@]} ${systools[@]} | grep -q true; then
      log.info "Upgrading apk (again)"
      apk upgrade
    fi
    log.megatitle "Installing Oh My Zsh" -x

  	bash ./zsh_install.sh
  	git clone https://github.com/zsh-users/zsh-autosuggestions "${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions" &&
  	git clone https://github.com/zdharma/fast-syntax-highlighting.git "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/fast-syntax-highlighting"

  	[[ -f ~/.zshrc ]] && sed -i 's/plugins=(git)/plugins=(zsh-autosuggestions fast-syntax-highlighting git)/g' ~/.zshrc
}

function install_ripgrep(){
	log.megatitle "Installing ripgrep" -x
	if [[ ! -f "ripgrep.tar.gz" ]]; then
    if { ! pgrep wget && ! pgrep curl ; } &>/dev/null; then
      log.warn "ripgrep.tar.gz does not exist, and wget or curl process not found, downloading..."
      ! isdefined download_release && {
        import deployme.sh
      }
      download_release BurntSushi/ripgrep x86_64-unknown-linux-musl -o ripgrep.tar.gz
    fi
	fi
	local exitcode
	runcmds ---log-only-errors \
	  'tar -xvf ripgrep.tar.gz' \
	  'mv ripgrep-*x86_64-unknown-linux-musl/rg /usr/bin/' \
	  'rm -rf ripgrep-*x86_64-unknown-linux-musl'
	exitcode=$?
	if [ $exitcode != 0 ]; then
    log.error "Failed installing ripgrep"
    return $exitcode
	fi
	if isdefined rg; then
	  log.success "Installed ripgrep"
	  return 0
	else
	  log.error "rg is not defined"
	  return 1
	fi
}

##############################################################################
#            Tool-related setup functions (aliases, env vars etc)
##############################################################################

function setup_debugfile(){
  # todo: maybe patch sizecustomize.py?
  log.megatitle "setup_debugfile()" -x
  local debugfile_was_already_set
	if [[ "$DEBUGFILE_PATH" ]]; then
	  debugfile_was_already_set=true
	else
	  debugfile_was_already_set=false
	  log.debug "no DEBUGFILE_PATH, finding under /app..."
	  [ -d /app ] && DEBUGFILE_PATH="$(find /app -maxdepth 2 -name debug.py -print -quit)"
	fi
	if [[ ! "$DEBUGFILE_PATH" ]]; then
		DEBUGFILE_PATH=/app/packages/debug.py
		download_file "https://gist.github.com/giladbarnea/c70149fd997a56695675e0e88984a288/raw" "$DEBUGFILE_PATH"
	fi
  if [[ -e "$DEBUGFILE_PATH" ]]; then
    log.success "$DEBUGFILE_PATH exists"
    if pip list 2>&1 | grep -q rich; then
      log.success "rich already installed"
    else
      log.title "Installing rich (because debugfile)"
      vex pip install rich
    fi
    if [[ "$PYTHONSTARTUP" != "$DEBUGFILE_PATH" ]]; then
      export PYTHONSTARTUP="$DEBUGFILE_PATH"
      log.success "PYTHONSTARTUP: $PYTHONSTARTUP"
      return 0
    fi
  else
    log.fatal "Failed downloading debug.py"
    return 1
  fi
}
function setup_prof(){
  # mkdir -p profiling
  function prof.empty(){
    if ! confirm "Empty profiling/?" --no-validate; then return 0; fi
    rm -v profiling/*
  }
}
function setup_vmq(){
  alias v=vmq-admin
  alias vs='vmq-admin session'
  alias vss='vmq-admin session show'
  alias vssx='vmq-admin session show --client_id --is_online --mountpoint --peer_host --peer_port --user --topic --online_messages --offline_messages --session_pid'
  alias vc='vmq-admin cluster'
  alias vcs='vmq-admin cluster show'
  alias vn='vmq-admin node'
  alias vp='vmq-admin plugin'
  alias vps='vmq-admin plugin show'
  alias vt='vmq-admin trace'
  alias vtc='vmq-admin trace client'

  alias vw='vmq-admin webhooks' # cache
  alias vws='vmq-admin webhooks show'
  function vt() { vmq-admin trace client client-id="$1"; }
  function viewconf(){
    local pager
    if isdefined bat; then
      pager=bat
    else
      # shellcheck disable=SC2209
      pager=cat
    fi
    if [ "$1" = --no-comments ]; then
      "$pager" /vernemq/etc/vernemq.conf | grep -Ev '^\s*#' | grep -E '.+'
    else
      "$pager" /vernemq/etc/vernemq.conf
    fi
  }
  # shellcheck disable=SC2139
  alias editconf="$EDITOR /vernemq/etc/vernemq.conf"
  log.megatitle "Defined vmq aliases:" -x
  if isdefined rg; then
    alias v?='alias | rg -e vmq-admin -e vernemq'
  else
    alias v?='alias | grep -e vmq-admin -e vernemq'
  fi
  v?
  # docker inspect $MQTT01 | grep -B1 '/vernemq/etc",' | head -1 | cut -d : -f 2 | grep -Po '(?<=")[\w/_]+(?=")'
}
function setup_pytest(){
	log.title "setup_pytest()" -x
  alias pytest &>/dev/null && return 0
  local pytest_ini
  pytest_ini="$(find "$PWD" -maxdepth 2 -name pytest.ini)"
  local pythonpath_modified=false
  local testdir="$(echo "$PWD"/tes*/)"
  if [ -d "$testdir" ]; then
  	safe_append_to_PYTHONPATH	"$testdir" && pythonpath_modified=true
  	local test_subdir
		while read -r test_subdir; do
			[ ! -d "$test_subdir" ] && continue
			safe_append_to_PYTHONPATH "$test_subdir" && pythonpath_modified=true
		done < <(find "$testdir" -mindepth 1 -maxdepth 1 -type d ! -name '.*' ! -name '_*')
  fi
  if $pythonpath_modified; then
		log.success "PYTHONPATH: $PYTHONPATH"
	fi
  local base_command="vex python -m pytest -s -W ignore::DeprecationWarning --ignore=src/pdbpp"
  # shellcheck disable=SC2139
  if [[ -e "$pytest_ini" ]]; then
    alias pytest="$base_command -c $pytest_ini"
  else
    alias pytest="$base_command"
  fi
  log.success "$(alias | grep pytest)"
}
function setup_fzf(){
	log.title "setup_fzf()" -x
  local preview_window_opts=down:wrap
  if isdefined fd; then
    export FZF_DEFAULT_COMMAND='fd -HI'
  else
    export FZF_DEFAULT_COMMAND='find .'
  fi
  export FZF_DEFAULT_OPTS="--preview-window=${preview_window_opts} --tiebreak=length,end,begin,index --border=none --cycle --reverse --exit-0 --select-1 --inline-info --ansi --tabstop=2 --no-bold"
}
function setup_ls(){ # tries with exa if defined
	log.title "setup_ls()" -x
	if isdefined exa; then
		function ls(){
			local dest
			if [[ "$1" && -d "$1" ]]; then
				dest="${1}"
				shift
			else
				dest="$PWD"
			fi
			local exa_args=(
				--classify # file types (-F)
				--all # .dot (-a)
				--header # Permissions Size etc (-h)
				--long # table (-l)
				--group-directories-first
				--icons
				# --color=always
				"$@"
			)
			local sort=name
			while [[ $# -gt 0 ]]; do
				case "$1" in
				-s | --sort*)
					if [[ "$1" == *=* ]]; then
						sort=${1#*=}
						shift
					else
						sort="$2"
						shift 2
					fi ;;
				*) exa_args+=("$1"); shift;;
				esac
			done
			exa_args+=(--sort="$sort")
			exa "$dest" "${exa_args[@]}" 2>/dev/null
			printf "\n\x1b[1;97m%s\x1b[0m\n\n" "$(realpath "$dest")"
		}
		alias lst='ls --tree'
		alias lst2='ls --tree --level=2'
		alias lst3='ls --tree --level=3'
	else
		function ls(){
			local dest="${1:-$PWD}"
			command ls "$dest" -Flahv --color=auto --group-directories-first "${@:2}" && \
			printf "\n\x1b[1;97m%s\x1b[0m\n\n" "$(realpath "$dest")"
		}
	fi
}

##############################################################################
#            Main flow
##############################################################################

declare positional=()
declare no_install=false
declare -A systools=([c]=false [zsh]=false [git]=false [pip]=false [grep]=false)
declare systools_keys=${!systools[@]}
declare -A utils=([fzf]=false [exa]=false [bat]=false [micro]=false [fd]=false [xclip]=false [rg]=false [htop]=false)
declare utils_keys=${!utils[@]}
declare -A pylibs=([rich]=false [ipython]=false [pdbpp]=false [pudb]=false [ipython_autoimport]=false [icecream]=false [birdseye]=false [snoop]=false)
declare pylibs_keys=${!pylibs[@]}

function _toggle_systools(){
  for x in "${!systools[@]}"; do
    systools[$x]="$1"
  done
  log.info "Set ${systools_keys// /, } to $1"
}
function _toggle_utils(){
  for x in "${!utils[@]}"; do
    utils[$x]="$1"
  done
  log.info "Set ${utils_keys// /, } to $1"
}
function _toggle_pylibs(){
  for x in "${!pylibs[@]}"; do
    pylibs[$x]="$1"
  done
  log.info "Set ${pylibs_keys// /, } to $1"
}
function I(){ printf '\033[3m%b\033[0m' "$*" ; }
while [[ $# -gt 0 ]]; do
  case "$1" in
	-h|--help)
		log.megatitle "source ./alpine [-h, --help] [--no-install] [OPTIONS]" -x
		echo 'Packages and tools can be set in batch or specifically,'
		printf 'or disabled altogether with '; I '--no-install '; printf '(which defines basic env vars and aliases.)\n'
		log.notice "\nBatch flags:\n" -x -n -L
		printf '  utils:\n'
		printf '\t%s\n' "$(I ${utils_keys// /, })"
		printf '  pylibs:\n'
		printf '\t%s, \n\tplus %s and %s.\n' "$(I ${pylibs_keys// /, })" "$(I .pdbrc.py)" "$(I debug.py)"
		printf '  systools:\n'
		printf '\t%s\n' "$(I ${systools_keys// /, })"
		printf "\nAll three (utils, pylibs, systools) can be set e.g\n  %s, which enables them all; \n  %s, which disables them all; and \n  %s, which enables all and disables all others.\n" $(I '--utils') $(I '--no-utils') $(I '--only-utils')
		printf "\nSpecific flags:\n"
		echo "  Any item in the lists above can be --item or --no-item. Example:"
		I '  --exa --no-xclip --no-ipython\n'
		printf "\nCommands can be accumulated, i.e:\n"
		I "  source ./alpine.sh --only-utils --ipython --no-xclip\n"
		I "  source ./alpine.sh --pylibs --systools --no-zsh\n"
    if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
      exit 0
    else
      return 0
    fi ;;
	--no-install)
	  no_install=true
	  log.info "no_install=true, this overrides everything"
	  shift ;;
	--only-*)
	  only_what=${1##--only-}
	  if [[ $only_what == systools ]]; then
		  _toggle_systools true
		  _toggle_pylibs false
		  _toggle_utils false
	  elif [[ $only_what == pylibs ]]; then
		  _toggle_systools false
		  _toggle_pylibs true
		  _toggle_utils false
	  elif [[ $only_what == utils ]]; then
      _toggle_systools false
      _toggle_pylibs false
      _toggle_utils true
    else
      log.warn "dont understand $1"
	  fi
		shift ;;
	--no-*)
	  no_what=${1##--no-}
    if [[ $no_what == systools ]]; then
		  _toggle_systools false
	  elif [[ $no_what == pylibs ]]; then
		  _toggle_pylibs false
	  elif [[ $no_what == utils ]]; then
      _toggle_utils false
    else
      if ! echo ${!utils[@]} ${!systools[@]} ${!pylibs[@]} | grep -q $no_what; then
        log.warn "$no_what is unknown, ignoring"
        shift
        continue
      fi
      if [[ ${systools[$no_what]} ]]; then
        systools[$no_what]=false
      elif [[ ${utils[$no_what]} ]]; then
        utils[$no_what]=false
      elif [[ ${pylibs[$no_what]} ]]; then
        pylibs[$no_what]=false
      fi
      log.info "$no_what=false"
	  fi
    shift ;;
	--*)
	  what=${1##--}
    if [[ $what == systools ]]; then
		  _toggle_systools true
	  elif [[ $what == pylibs ]]; then
		  _toggle_pylibs true
	  elif [[ $what == utils ]]; then
      _toggle_utils true
    else
      if ! echo ${!utils[@]} ${!systools[@]} ${!pylibs[@]} | grep -q "$what"; then
        log.warn "$what is unknown, ignoring"
        shift
        continue
      fi
      if [[ ${systools[$what]} ]]; then
        systools[$what]=true
      elif [[ ${utils[$what]} ]]; then
        utils[$what]=true
      elif [[ ${pylibs[$what]} ]]; then
        pylibs[$what]=true
      fi
      log.info "$what=true"
    fi
    shift ;;
	*)
	  log.warn "Unknown arg: $1"
	  positional+=("$1")
	  shift ;;
  esac
done

set -- "${positional[@]}"

if ! echo ${utils[@]} ${systools[@]} ${pylibs[@]} | grep -q true; then
  log.info "everything is false, equivalent to no_install=true"
  no_install=true
fi

if ! $no_install && echo ${utils[@]} ${systools[@]} ${pylibs[@]} | grep -q true; then
  if echo ${utils[@]} ${systools[@]} | grep -q true || ${pylibs[pdbpp]} || ${pylibs[ipython]}; then
    add_apk_repos
    if ! isdefined git; then
      log.title "Installing git" -x
      apk add --update git && sleep 0.5
    fi
  fi
  install_pylibs
  install_utils


	if "${systools[zsh]}" && ! isdefined zsh; then
    log.megatitle "Installing zsh" -x
    apk add --update zsh
	fi

	if "${systools[pip]}" && ! isdefined pip; then
		# TODO: https://bootstrap.pypa.io/get-pip.py if no pip
    log.megatitle "Upgrading pip, wheel, and setuptools" -x
    pip install -U pip wheel setuptools
	fi

	if "${systools[c]}"; then
		install_clibs
	fi

	if "${systools[zsh]}"; then
		install_zsh
	fi
fi

setup_ls
function cd(){ builtin cd "$@" && ls ; }

declare THIS_FILE="$(realpath "${BASH_SOURCE[0]}")"
realpine() { source "$THIS_FILE" "$@" ; } ;
alias e=echo

setup_pytest

# vernemq
isdefined vmq-admin && {
  setup_vmq
}

setup_debugfile
#setup_prof

isdefined fzf && {
	setup_fzf
}

if isdefined micro; then
  export EDITOR=micro
  log.success "EDITOR: ${EDITOR}"
elif [ ! "$EDITOR" ]; then
  export EDITOR=vi
fi
# export BETTER_EXCEPTIONS=1
export TERM=xterm-256color
export COLORTERM=truecolor
if ! grep -q "$HOME" <<< "$PATH"; then
  export PATH="$HOME":"$PATH"
fi

export PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '

if ! $no_install; then
  if [ -d /app/main/src ]; then
    declare package_name
    for dir in /app/main/src/*; do
      if [ ! -d "$dir" ]; then continue; fi
      package_name="$(basename "$dir")"
      if [ "$package_name" = pdbpp ]; then
        install_pdbpp
        continue
      elif pip list 2>&1 | grep -q "$package_name"; then
        log.success "Found $dir but $package_name already installed"
        continue
      fi
      if confirm "Found $dir. pip install -e $dir? Did not find $package_name in pip list" --no-validate; then
        if ! isdefined git; then
          log.title "Installing git" -x
          apk add --update git && sleep 0.5
        fi
        vex pip install -e "$dir" ---just-run
      fi
    done
  fi
fi
#export SM_LOGLEVEL=DEBUG
#export DEBUGFILE_RICH_TB=1
#export DEBUGFILE_NO_PATCH_PRINT=1
