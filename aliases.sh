#!/usr/bin/env zsh
# Sourced second after environment.sh and before log.sh

# ----------------------------------
# *** Platform-Dependent Aliases ***
# ----------------------------------

if [[ "$OS" = macos ]]; then
	source "aliases.mac.sh"
elif [[ "$PLATFORM" == UNIX ]]; then
	source "aliases.linux.sh"
else
	source "aliases.win.sh"
fi

# ----------------------
# *** System Aliases ***
# ----------------------

alias e=echo
alias e'?'='echo $?'

alias quit=exit
alias qui=exit
alias qy=exit
alias quy=exit
alias qi=exit
alias qu=exit
alias qqu=exit
alias exi=exit
alias eit=exit
alias eix=exit
alias exot=exit
alias exut=exit
alias xite=exit
alias EXIT=exit
alias X=exit
alias x=exit

alias ts=typeset
alias p=print

alias op='omz plugin'
alias opl='omz plugin load'
alias opi='omz plugin info'

hash -d land="$LAND"
hash -d comp="$LAND/completions"
hash -d dev="$DEV"
hash -d desk="$HOME/Desktop"
hash -d doc="$HOME/Documents"
hash -d dl="$HOME/Downloads"
hash -d pic="$HOME/Pictures"
hash -d lib="$HOME/Library"
hash -d appsup="$HOME/Library/Application Support"
hash -d llm="$HOME/Library/Application Support/io.datasette.llm"
hash -d t="$HOME/Library/Application Support/io.datasette.llm/templates"
hash -d ob="$HOME/Documents/remote"

# ----------------------
# *** Custom Aliases ***
# ----------------------
alias b=bat
alias c=command
alias ca=cursor-agent
alias clauded='CLAUDE_CODE_OAUTH_TOKEN=$(<~/.claude-code-oauth-token) claude --dangerously-skip-permissions'
alias claudedh='CLAUDE_CODE_OAUTH_TOKEN=$(<~/.claude-code-oauth-token) /usr/local/Caskroom/claude-code/2.0.43/claude --dangerously-skip-permissions --model=haiku'
alias codexd='codex --dangerously-bypass-approvals-and-sandbox'
alias fdd='fd -t d'
alias fdf='fd -t f'
alias ds=docstring
alias n=nvim
alias o='(){ [[ "$1" ]] && { open "$@"; return $? ; } ; open .; }'
compdef _open=o
alias f=fd
alias r=rg
alias l=less
alias typora='open -b abnerworks.Typora'

# ----------------------
# *** Global Aliases ***
# ----------------------


# https://docs.openwebui.com/getting-started/env-configuration/
function ows(){
	export ENABLE_LOGIN_FORM=true
	export ENABLE_OAUTH_SIGNUP=true
	export ENABLE_SIGNUP=true
	export ENABLE_REALTIME_CHAT_SAVE=true
	export DEFAULT_USER_ROLE=user
	export WEBUI_SECRET_KEY=gilad
	export ENABLE_CODE_EXECUTION=true
	export ENABLE_CODE_INTERPRETER=true
	export RAG_WEB_SEARCH_RESULT_COUNT=1
	export RAG_WEB_SEARCH_CONCURRENT_REQUESTS=1
	export ENABLE_WEBSOCKET_SUPPORT=true
	export ENABLE_AUTOCOMPLETE_GENERATION=true
	export PDF_EXTRACT_IMAGES=true
	export ENABLE_IMAGE_GENERATION=true
	export IMAGES_OPENAI_BASE_URL=https://api.openai.com/v1/chat/completions
	export IMAGES_OPENAI_API_KEY=$(<~/.openai-api-key)
	export IMAGES_GEMINI_API_KEY=$(<~/.gemini-api-key)
	export IMAGES_GEMINI_API_BASE_URL=https://generativelanguage.googleapis.com/v1beta
	export AUDIO_TTS_OPENAI_API_BASE_URL=https://api.openai.com/v1/audio/speech
	export AUDIO_TTS_OPENAI_API_KEY=$(<~/.openai-api-key)
	export AUDIO_STT_OPENAI_BASE_URL=https://api.openai.com/v1/audio/transcriptions
	export AUDIO_STT_OPENAI_API_KEY=$(<~/.openai-api-key)
	# export TAVILY_API_KEY=$(<~/.tavily-api-key)
	# export TAVILY_EXTRACT_DEPTH=5
	# export EXA_API_KEY=$(<~/.exa-api-key)
	# export SERPAPI_API_KEY=$(<~/.serpapi-api-key)
	export PERPLEXITY_API_KEY=$(<~/.perplexity-api-key)
	# export GOOGLE_PSE_API_KEY=$(<~/.google-pse-api-key)
	# export GOOGLE_PSE_ENGINE_ID=7458e8e468f1749e5
# 	if [[ -e $HOME/dev/open-webui/backend/start.sh ]]; then
#     $HOME/dev/open-webui/backend/start.sh
#   else
#     open-webui serve
#   fi
}

# ** Editors: Pycharm, VSCode, Nvim etc **
# -----------------------------------------
function define_editors_aliases(){

	# # editpages <EDITOR> [QUERY] [EDITOR_ARGS...]
	# ## Examples
	# ```bash
	# editpages code altair --wait
	# editpages micro
	# ```
	# function editpages(){
	# 	log.title "$0($*)"
	# 	editfile "$@" -f "$HOME/dev/termwiki/termwiki/private_pages/pages.py"
	# }

	type pycharm &>/dev/null && {
		if [[ "$PLATFORM" = UNIX ]]; then
			# * MacOS or Linux
			alias pc='() { virtual_env="$VIRTUAL_ENV"; deactivate 2>/dev/null; pycharm "${@}"; [[ "$virtual_env" ]] && source "$virtual_env/bin/activate" ; }'
		else
			if [[ "$WSL_DISTRO_NAME" ]]; then
				if type fd &>/dev/null; then
					if latest_pycharm_dir="$(fd -t d . "$WINHOME"/AppData/Local/JetBrains/Toolbox/apps/PyCharm-P/ch-0  --max-depth=1 | while read -r d; do basename "$d"; done | sort -r | head -1)"; then
						pycharm_exe="$(fd 'pycharm64.exe$' "$WINHOME/AppData/Local/JetBrains/Toolbox/apps/PyCharm-P/ch-0/$latest_pycharm_dir")"
						alias pycharm="$pycharm_exe"
						alias pc="$pycharm_exe"
					fi
				else
					echo "[$0][WARN] fd is not installed, not defining pycharm aliases" 1>&2
				fi
			else
				# todo: check if pycharm.cmd exists first
				alias pycharm='pycharm.cmd'
				alias pc=pycharm
			fi
		fi
	}
	
	# # cur [cursor opts...] [--new-workspace[=workspace_name]]
	# Automatically loads the workspace file if it exists.
	# Specifying --new-workspace will create and use a new workspace file. Only applicable if 
	function cur() {
		function _escape(){
			printf '%q' "$1"
		}
		local workspace_specified=false
		local create_new_workspace=false
		local -a specified_dirs=()
		local -a specified_files=()
		local -a cursor_args=()
		local root_dir
		local arg
		for arg in "$@"; do
			if [[ "$arg" = *.code-workspace ]]; then
				[[ -e "$arg" ]] && { 
					workspace_specified=true
					cursor_args+=("$arg")
				}
				[[ ! -e "$arg" ]] && {
					confirm "'$arg' doesn’t exist. Create it instead?" && create_new_workspace="$arg"
				}
				continue
			fi
			if [[ -d "$arg" ]]; then
				specified_dirs+=("$arg")
				cursor_args+=("$arg")
				continue
			fi
			
			if [[ "$arg" = --new-workspace ]]; then
				create_new_workspace=true
			elif [[ -f "$arg" ]]; then
				specified_files+=("$arg")
				cursor_args+=("$arg")
				continue
			else
				cursor_args+=("$arg")
			fi
		done
		
		# Escape `cursor_args` in-place for the rest of the flow.
		local -a escaped_cursor_args=()
		for arg in "${cursor_args[@]}"; do
			escaped_cursor_args+=("$(_escape "$arg")")
		done
		cursor_args=("${escaped_cursor_args[@]}")
		unset escaped_cursor_args

		[[ "$workspace_specified" = true && "$create_new_workspace" != false ]] && {
			log.warn "Workspace file was specified, but --new-workspace was also specified. Ignoring --new-workspace."
			create_new_workspace=false
		}
		[[ "${#specified_dirs[@]}" -ge 2 && "$create_new_workspace" != false ]] && {
			log.warn "Multiple directories were specified, and --new-workspace was also specified. Don't know which one is root, so ignoring --new-workspace."
			create_new_workspace=false
		}
		
		# cur ~/dev/
		if [[ "${#specified_dirs[@]}" -eq 1 ]]; then
			root_dir="${specified_dirs[1]}"
		
		# cur
		elif [[ "${#specified_dirs[@]}" -eq 0 && "${#specified_files[@]}" -eq 0 ]]; then
			root_dir="${PWD}"
		
		# cur like/this.py
		elif [[ "${#specified_dirs[@]}" -eq 0 && "${#specified_files[@]}" -eq 1 ]]; then
		    local specified_file_dir="${specified_files[1]:h}"
		    if [[ -d "$specified_file_dir" && "$specified_file_dir" != "$PWD" ]]; then
			    if confirm "Use '$specified_file_dir' as root directory?"; then
				    root_dir="$specified_file_dir"
				else
					root_dir="${PWD}"
				fi
			fi
		fi
		if [[ "$workspace_specified" = true ]]; then
			cursor editor "${cursor_args[@]}"
			return $?
		fi
		# shellcheck disable=SC1036
		local -a code_workspace_files=("${root_dir}"/*.code-workspace(N))  # (N) means no error if no files are found
		if [[ -n "${code_workspace_files[@]}" && "$create_new_workspace" != false ]]; then
			log.warn "--new-workspace was specified, but ${#code_workspace_files[@]} were found in ${root_dir} dir. Ignoring --new-workspace."
			create_new_workspace=false
		fi
		if [[ -z "${code_workspace_files[@]}" ]]; then
			if [[ "$create_new_workspace" != false ]]; then
				local workspace_filename
				case "$create_new_workspace" in
					(true) workspace_filename="${root_dir:t}" ;;
					(*) workspace_filename="${create_new_workspace%.code-workspace}" ;;
				esac
				# Generate a base darkness (20-80)
				local base=$(( (RANDOM % 60) + 20 ))
				# Set RGB channels. 
				# We keep Red as the anchor and add slight jitter (+/- 5) to Green and Blue.
				local r=$base
				local g=$(( base + (RANDOM % 10) - 5 ))
				local b=$(( base + (RANDOM % 10) - 5 ))
				# Format as Hex
				local random_color="$(printf '#%02x%02x%02x' "$r" "$g" "$b")"
				jq -n --arg color "$random_color" '{"folders": [{"path": "."}], "settings": {"peacock.color": $color}}' > "${root_dir}/${workspace_filename}.code-workspace"
				cursor editor "$(_escape "${root_dir}/${workspace_filename}.code-workspace")" "${cursor_args[@]}"
				return $?
			fi
			cursor editor "${cursor_args[@]}"
			return $?
		fi
		if [[ "${#code_workspace_files[@]}" -eq 1 ]]; then
			set -x
			cursor editor "$(_escape "${code_workspace_files[1]}")" "${cursor_args[@]}"
			set +x
			return $?
		fi
		local chosen_workspace_file
		local choices="${$(typeset code_workspace_files)#*=}"
		chosen_workspace_file="$(input "Choose a workspace file:" --choices="$choices")"
		cursor editor "$(_escape "$chosen_workspace_file")" "${cursor_args[@]}"
		return $?
	}
	
	
	
	local -a editors=(
		# code
		# pc
		# sublime
		bat
		nvim
		cursor
		cur
		l    # less
		cat  # cat
	)
	local -A aliases_file_paths=(                                                 
		zshhist  "$HOME/.zsh_history"                                     
		zshrc    "$HOME/.zshrc"                                           
		pages    "$HOME/dev/termwiki/termwiki/private_pages/pages.py"     
		scripts  "$LAND"                                               
	)

	# Initialize HISTORY_IGNORE base                      
	local hist_ignore_base="${${HISTORY_IGNORE:-'()'}:0:-1}"  # Remove closing parenthesis
	local hist_ignore_values='' 
	
	# Create aliases dynamically for each editor-file combination         
	local editor target_name target_path                                  
	# shellcheck disable=SC1058,1072,1073,1009
	for editor in $editors; do
		for target_name target_path in ${(kv)aliases_file_paths}; do              
			alias "${editor}${target_name}"="$editor '$target_path'"      
			hist_ignore_values+="|${editor}${target_name}"                
		done                                                              
	done 

	# export HISTORY_IGNORE="${${HISTORY_IGNORE:-'()'}:0:-1}|pczshhist|pczshrc|pcpages|pcscripts|codezshhist|codezshrc|codepages|codescripts|micropages|sublimepages|nvimpages)"


	# * window management aliases: gethexid, getwinid, getpid, getwindowname
	# local filename stem
	# if [[ "$WINMGMT" ]]; then
	#   declare _winmgmt_file
	#   for _winmgmt_file in "$WINMGMT"/get*.py; do
	#     filename=${_winmgmt_file##*/}    # gethexid.py
	#     stem=${filename%.*}              # gethexid
	#     alias "${stem}"="(){ python3.9 -OO -SBq $WINMGMT/$filename \"\$1\" --stdout-result --no-log --no-notif ; }"
	#   done
	# fi

	# * DEBUGFILE
	if [[ "$PYTHONDEBUGFILE" ]]; then
		for editor in $editors; do                                        
			alias "${editor}debug"="$editor '$PYTHONDEBUGFILE'"           
		done
	fi

	# Handle scripts directory aliases                                    
	local script subdir filename stem prefix cmd                                         
	for subdir in . hooks; do                                             
		for script in "${LAND}/${subdir}"/*.*sh; do                      
			filename=${script##*/}                                  
			stem=${filename%.*}                                     
			# Create aliases for each editor plus 're' (source)           
			for prefix in re $editors; do                                 
				if [[ "$prefix" = re ]]; then
					cmd='source'
				else
					cmd="$prefix"
				fi
				alias "${prefix}${stem}"="$cmd '$script'"                 
				hist_ignore_values+="|${prefix}${stem}"                   
			done                                                          
		done                                                              
	done

	# Update HISTORY_IGNORE                                               
	[[ -n "$hist_ignore_values" ]] && export HISTORY_IGNORE="${hist_ignore_base}${hist_ignore_values})"

}; define_editors_aliases


# ** Python Aliases **
# --------------------

# * Define python aliases
function define_python_aliases(){
	local -a python_versions=(14 13 12 11 10 9)
	local syspy_version=3.13

	local findexec
	if [[ ${builtins[whence]} ]]; then
		findexec=whence
	elif [[ ${builtins[which]} ]]; then
		findexec=which
	else
		findexec=where  # bummer
	fi

	# # _define_python_aliases_for_version <PYTHON_PATH> <PYTHON_MINOR_VERSION>
	# py39, pip39, pym39, ipy39, venv39 etc
	function _define_python_aliases_for_version(){
		local pypath="$1"
		local v="$2"
		alias "py3${v}"="$pypath -Bq"
		alias "py3${v}S"="$pypath -OO -ISBq"
		alias "pym3${v}"="py3${v} -m"
		alias "pyc3${v}"="py3${v} -c"
		alias "pyc3${v}S"="py3${v} -OO -ISBqc"
		# alias "pip3${v}"="pym3${v} pip"
		alias "ipy3${v}"="pym3${v} IPython"
		alias "ipy3${v}S"="IPYTHON_DIR=/tmp PYTHONSTARTUP= ipy3${v}"  # rm -rf extensions nbextensions profile_default .ipynb_checkpoints
		alias "venv3${v}"="venv $pypath"
	}

	# When inside a virtual env, these take the venv's execs
	local found py_exec_path py_exec_ver
	for py_exec_ver in "${python_versions[@]}"; do
		found=false
		if py_exec_path="$("$findexec" "python3.${py_exec_ver}" 2>/dev/null)"; then
			found=true
		elif [[ "$PLATFORM" = WIN && -x "$PROGFILES/Python3${py_exec_ver}/python.exe" ]]; then
			py_exec_path="'$PROGFILES/Python3${py_exec_ver}/python.exe'"
			found=true
		fi
		[[ $found = true ]] && _define_python_aliases_for_version "$py_exec_path" "${py_exec_ver}"
	done

	alias syspy="$("$findexec" "python${syspy_version}" 2>/dev/null)"

	# Static aliases
	alias py="python3"
	alias pym="python3 -m"
	alias pyc="python3 -c"
	alias ipy="ipython"

	alias pipi="pip install"
	alias pipl="pip list -v"
	alias piplg="pip list -v | grep -i"

}; define_python_aliases


# ** 3rd-party tools **
# ---------------------
function define_docker_aliases(){
	[[ -z "${aliases[d]}" ]] && alias d=docker
	alias lzd="lazydocker"
	declare -i _since
	# shellcheck disable=SC2139,SC2140
	for _since in 0 1 2 3 4 5; do
		alias dl"${_since}"="docker logs --since=${_since}m"
		alias dlt"${_since}"="docker logs --timestamps --since=${_since}m"
		alias dlf"${_since}"="docker logs --follow --since=${_since}m"
		alias dlft"${_since}"="docker logs --timestamps -f --since=${_since}m"
	done
	unset _since
	alias dl='docker logs'
	alias dlt='docker logs --timestamps'
	alias dlf='docker logs --follow'
	alias dlft='docker logs --follow --timestamps'
	alias de='docker exec'
	alias da='docker attach'
	alias db='docker build'
	alias dps='docker ps'
	alias di='docker inspect'
	alias dn='docker network'
	alias ds='docker stop'

	alias dc='docker compose'
	alias dci='docker compose images'
	alias dcd='docker compose down'
	alias dcu='docker compose up'
	alias dcr='docker compose restart'

	alias dcrlf0='(){ docker compose restart "$1"; docker logs --follow --since=0m "$1" ; }'
	alias dcrlf1='(){ docker compose restart "$1"; docker logs --follow --since=1m "$1" ; }'
	alias dcrlf2='(){ docker compose restart "$1"; docker logs --follow --since=2m "$1" ; }'
	alias dcrlf3='(){ docker compose restart "$1"; docker logs --follow --since=3m "$1" ; }'

	alias d\?='alias | grep -P "(?<=\=)[\W]*\bdocker\b" | if type bat &>/dev/null; then bat -l bash -p; else cat /dev/stdin; fi'

}; # define_docker_aliases

# * Node aliases
# --------------

