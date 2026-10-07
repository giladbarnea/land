#!/usr/bin/env zsh
# Sourced second after environment.sh and before log.sh

: "${THIS_SCRIPT_DIR:=$(dirname -- "$0")}"

# ----------------------------------
# *** Platform-Dependent Aliases ***
# ----------------------------------

if [[ "$OS" = macos ]]; then
	source "$THIS_SCRIPT_DIR/aliases.mac.sh"
elif [[ "$PLATFORM" == UNIX ]]; then
	source "$THIS_SCRIPT_DIR/aliases.linux.sh"
else
	source "$THIS_SCRIPT_DIR/aliases.win.sh"
fi

# ----------------------
# *** System Aliases ***
# ----------------------

alias e=echo
alias e'?'='echo $?'
alias g=grep
alias gi='grep -i'
alias gie='_(){ local patterns=("$@"); local grep_args=(-i -P); local pattern; for pattern in "${patterns[@]}"; do grep_args+=(-e "$pattern"); done; grep "${grep_args[@]}" ; }'
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
hash -d iclouddocs=/Users/giladbarnea/Library/Mobile\ Documents/com\~apple\~CloudDocs/
hash -d t="$HOME/Library/Application Support/io.datasette.llm/templates"
hash -d c="$HOME/.claude"

# ----------------------
# *** Custom Aliases ***
# ----------------------
alias b=bat
alias c=command
alias ca=cursor-agent

#region claude aliases
alias :claude='/usr/bin/env -u CLAUDE_CODE_OAUTH_TOKEN -u ANTHROPIC_API_KEY claude --dangerously-skip-permissions'

alias claudehappy='() { if [[ -f ~/.claude-code-personal-1y-oauth-token ]]; then happy --claude-env CLAUDE_CODE_OAUTH_TOKEN="$(<~/.claude-code-personal-1y-oauth-token)" --yolo "$@"; else echo "[claudehappy] error: ~/.claude-code-personal-1y-oauth-token does not exist" ; return 1; fi ; }'

_claude_models=(fable:f opus:o sonnet:s haiku:h)
_claude_extended_models=(fable opus sonnet)
# Suffixes: low=l, medium=m, high=h, xhigh=x, max=max (medium stays `m` so `max` is unambiguous).
_claude_standard_levels=(low:l medium:m high:h)
_claude_extended_levels=(${_claude_standard_levels[@]} xhigh:x max:max)

# claudeo (Opus), claudeo-no (Opus non-interactive), claudeox (Opus xhigh), claudeox-no (Opus xhigh non-interactive), etc.
for _claude_model_entry in "${_claude_models[@]}"; do
    _claude_model="${_claude_model_entry%%:*}"
    _claude_model_suffix="${_claude_model_entry##*:}"
    _claude_alias="claude${_claude_model_suffix}"
    alias "${_claude_alias}"=":claude --model=${_claude_model}"
    alias "${_claude_alias}-no"="${_claude_alias} --no-session-persistence -p"
    _claude_levels=(${_claude_standard_levels[@]})
    (( ${_claude_extended_models[(Ie)$_claude_model]} )) && _claude_levels=(${_claude_extended_levels[@]})
    for _claude_level_entry in "${_claude_levels[@]}"; do
        _claude_level="${_claude_level_entry%%:*}"
        _claude_level_suffix="${_claude_level_entry##*:}"
        alias "${_claude_alias}${_claude_level_suffix}"="${_claude_alias} --effort ${_claude_level}"
        alias "${_claude_alias}${_claude_level_suffix}-no"="${_claude_alias}${_claude_level_suffix} --no-session-persistence -p"
    done
done
unset _claude_models _claude_extended_models _claude_model_entry _claude_model _claude_model_suffix _claude_alias _claude_levels _claude_level_entry _claude_level _claude_level_suffix
#endregion claude aliases

#region codex aliases
alias codexd='/usr/bin/env -u OPENAI_API_KEY codex --yolo'
compdef _codex codexd

_gpt_models=(gpt-6-astra:a gpt-6.1-sol:s gpt-5.6-terra:t gpt-6-luna:l)
_gpt_levels=(low:l medium:m high:h xhigh:x max:max)
_codex_unique_levels=(ultra:u)

# codexll (Luna low), codextm (Terra medium), codexsx (Sol xhigh), codexau (Astra ultra), etc.
for _codex_model_entry in "${_gpt_models[@]}"; do
    _codex_model="${_codex_model_entry%%:*}"
    _codex_model_suffix="${_codex_model_entry##*:}"
    _codex_alias="codex${_codex_model_suffix}"
    alias "${_codex_alias}"="codexd --model=${_codex_model}"
    for _codex_level_entry in "${_gpt_levels[@]}" "${_codex_unique_levels[@]}"; do
        _codex_level="${_codex_level_entry%%:*}"
        _codex_level_suffix="${_codex_level_entry##*:}"
        alias "${_codex_alias}${_codex_level_suffix}"="${_codex_alias} --config=\"model_reasoning_effort=${_codex_level}\""
    done
done
unset _codex_model_entry _codex_model _codex_model_suffix _codex_alias _codex_level_entry _codex_level _codex_level_suffix _codex_unique_levels
#endregion codex aliases

#region pi aliases
_pi_claude_extended_models=(claude-fable-5-1:f claude-opus-5-5:o claude-sonnet-5-5:s)
_pi_claude_standard_models=(claude-haiku-4-5:h)
_pi_no_arguments=(--no-extensions --no-prompt-templates --no-themes --no-session --no-skills)
_pi_nono_arguments=( ${_pi_no_arguments[@]} --no-tools --no-context-files)

# # _define_pi_aliases <ALIAS> <MODEL> <LEVEL_ENTRIES...>
# pics, pics-no, pics-nono, picsx, picsx-no, picsx-nono, etc.
function _define_pi_aliases() {
    local alias_name="$1"
    local model="$2"
    shift 2
    local level_entry level level_suffix
    alias "${alias_name}"="pi --model ${model}"
    alias "${alias_name}-no"="${alias_name} ${(j: :)_pi_no_arguments}"
    alias "${alias_name}-nono"="${alias_name} ${(j: :)_pi_nono_arguments}"
    for level_entry in "$@"; do
        level="${level_entry%%:*}"
        level_suffix="${level_entry##*:}"
        alias "${alias_name}${level_suffix}"="${alias_name} --thinking ${level}"
        alias "${alias_name}${level_suffix}-no"="${alias_name}${level_suffix} ${(j: :)_pi_no_arguments}"
        alias "${alias_name}${level_suffix}-nono"="${alias_name}${level_suffix} ${(j: :)_pi_nono_arguments}"
    done
}

# pica, pics, pict, picl
for _pi_model_entry in "${_gpt_models[@]}"; do
    _define_pi_aliases "pic${_pi_model_entry##*:}" "openai-codex/${_pi_model_entry%%:*}" "${_gpt_levels[@]}"
done

# pif, pio, pis
for _pi_model_entry in "${_pi_claude_extended_models[@]}"; do
    _define_pi_aliases "pi${_pi_model_entry##*:}" "anthropic/${_pi_model_entry%%:*}" "${_claude_extended_levels[@]}"
done

# pih
for _pi_model_entry in "${_pi_claude_standard_models[@]}"; do
    _define_pi_aliases "pi${_pi_model_entry##*:}" "anthropic/${_pi_model_entry%%:*}" "${_claude_standard_levels[@]}"
done
unfunction _define_pi_aliases
unset _pi_model_entry _pi_claude_extended_models _pi_claude_standard_models _pi_no_arguments _pi_nono_arguments _claude_standard_levels _claude_extended_levels _gpt_models _gpt_levels
#endregion pi aliases

# # pi [opts...]
# Thin `pi` wrapper. Normalizes passing prompts from stdin, positionally, or both. 
function pi() {
	local stdin
	local full_prompt
	local running_interactively=true
	local -a args_besides_prompt=()
	local -a prompt_parts=()
  # Note: should be checked for completeness opportunistically (`pi --help`)
	local -a options_that_take_value=(
		--provider
		--model
		--api-key
		--system-prompt
		--append-system-prompt
		--mode
		--session
		--session-id
		--fork
		--session-dir
		--name
		--models
		--tools
		--exclude-tools
		--thinking
		--extension
		--skill
		--prompt-template
		--theme
		--use-theme
		--tui-mode
		--export
		--fff-mode
		--fff-frecency-db
		--fff-history-db
		--subagents-workflow-file
		--mcp-config
		-e
		-n
		-t
		-xt
	)

	if is_piped; then
		stdin="$(<&0)"
	fi
	[[ -z "$stdin" ]] && { command pi "$@"; return $?; }

	while [[ "$#" -gt 0 ]]; do
		case "$1" in
			--list-models|--list-models=*)
				command pi "${args_besides_prompt[@]}" "$@"
				return $?
				;;
			--print|-p)
				running_interactively=false
				args_besides_prompt+=("$1")
				shift
				;;
			--*=*)
				args_besides_prompt+=("$1")
				shift
				;;
			--)
				shift
				prompt_parts+=("$@")
				break
				;;
			@*)
				args_besides_prompt+=("$1")
				shift
				;;
			-*)
				args_besides_prompt+=("$1")
				if [[ ${options_that_take_value[(Ie)$1]} -gt 0 ]]; then
					[[ "$2" ]] || { print -u2 -- "pi: Missing value for $1"; return 1; }
					args_besides_prompt+=("$2")
					shift 2
				else
					shift
				fi
				;;
			*)
				prompt_parts+=("$1")
				shift
				;;
		esac
	done

	full_prompt="$stdin"
	if [[ "${#prompt_parts[@]}" -gt 0 ]]; then
		local positional_prompt="$(printf "%s\n\n" "${prompt_parts[@]}")"
		full_prompt="$(printf "%s\n\n%s" "$stdin" "$positional_prompt")"
	fi

	if [[ "$running_interactively" = true ]]; then
		command pi "${args_besides_prompt[@]}" "$full_prompt" < /dev/tty
	else
		# Over stdin, not argv: a prompt around 1 MB as a positional argument crashes pi with "RangeError: Maximum call stack size exceeded".
		print -r -- "$full_prompt" | command pi "${args_besides_prompt[@]}"
	fi
}

function :gemini() {
	local -a args_besides_prompt=()
	local full_prompt
	local specified_interactive_flag=false
	local specified_noninteractive_flag=false
	local running_interactively=true
	while [[ "${#}" -gt 0 ]]; do
		if [[ "$1" = -* ]]; then
			args_besides_prompt+=("$1")
			if [[ "$1" = -i || "$1" = --prompt-interactive ]]; then
				specified_interactive_flag=true
			fi
			if [[ "$1" = -p || "$1" = --prompt ]]; then
				specified_noninteractive_flag=true
				running_interactively=false
			fi
			shift
			continue
		fi
		if [[ -z "$full_prompt" ]]; then
			full_prompt="$1"
			shift
			continue
		fi
		# If the current argument has more than one word, treat it as an intentional extension of the prompt.
		if [[ ${(w)#1} -gt 1 ]]; then
			log.warn "More than one positional argument was specified. Adding the current one to the prompt: $(shorten "$1" -m 30)"
			full_prompt="$(printf "%s\n%s" "$full_prompt" "$1")"
	
		# Otherwise, treat it as a regular positional argument.
		else
			args_besides_prompt+=("$1")
		fi
		shift
	done
	if is_piped; then
		local stdin="$(cat)"
		if [[ -n "$stdin" ]]; then
			log.debug 'Piped and not empty'
			full_prompt="$(printf "%s\n%s" "$stdin" "$full_prompt")"
			if [[ "$specified_interactive_flag" = false && "$specified_noninteractive_flag" = false ]]; then
			    args_besides_prompt+=(-i)
			fi
		fi
	fi
	if [[ "$running_interactively" = true ]]; then
		GEMINI_API_KEY=$(<~/.gemini-api-key-free-tier-Generative-Language-Client) gemini "${args_besides_prompt[@]}" "$full_prompt" < /dev/tty
	else
	    log.debug 'Running non-interactively'
		GEMINI_API_KEY=$(<~/.gemini-api-key-free-tier-Generative-Language-Client) gemini "${args_besides_prompt[@]}" "$full_prompt" 2>&1 < /dev/tty \
			| grep -v -E 'DEP0040|to show where the warning|YOLO mode is enabled|Both GOOGLE_API_KEY|Hook registry initialized'
	fi
}
function geminip() {
	:gemini --yolo --model=gemini-3.1-pro-preview "$@"
}
function geminif() {
	:gemini --yolo --model=gemini-3-flash-preview "$@"
}
function geminifl() {
	:gemini --yolo --model=gemini-3-1-flash-lite-preview "$@"
}
compdef _gemini :gemini geminip geminif geminifl

alias fdd='fd -t d'
alias fdf='fd -t f'
alias ds=docstring
alias n=nvim
o(){ [[ "$1" ]] && { open "$@"; return $? ; } ; open .; }
compdef _open o
alias f=fd
alias r=rg
alias l=less
alias g=grep
alias typora='open -b abnerworks.Typora'
alias jqc='jq --color-output'
alias headroom="uvx --with=fastapi,uvicorn'[standard]',httpx'[http2]',tree-sitter --from 'headroom-ai[ml,code,memory,relevance,image]' headroom"

# ----------------------
# *** Global Aliases ***
# ----------------------


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
				root_dir="${PWD}"
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
		code
		# pc
		# sublime
		tode
		bat
		nvim
		n    # nvim
		cursor
		cur
		l    # less
		cat  # cat
	)
	local -A aliases_file_paths=(                                                 
		zshhist  "$HOME/.zsh_history"                                     
		zshrc    "$HOME/.zshrc"                                           
		land  "$LAND"                                               
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
	
	unfunction define_editors_aliases

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

	unfunction define_python_aliases
}; define_python_aliases


# ** 3rd-party tools **
# ---------------------
# function define_docker_aliases(){
# 	[[ -z "${aliases[d]}" ]] && alias d=docker
# 	alias lzd="lazydocker"
# 	declare -i _since
# 	# shellcheck disable=SC2139,SC2140
# 	for _since in 0 1 2 3 4 5; do
# 		alias dl"${_since}"="docker logs --since=${_since}m"
# 		alias dlt"${_since}"="docker logs --timestamps --since=${_since}m"
# 		alias dlf"${_since}"="docker logs --follow --since=${_since}m"
# 		alias dlft"${_since}"="docker logs --timestamps -f --since=${_since}m"
# 	done
# 	unset _since
# 	alias dl='docker logs'
# 	alias dlt='docker logs --timestamps'
# 	alias dlf='docker logs --follow'
# 	alias dlft='docker logs --follow --timestamps'
# 	alias de='docker exec'
# 	alias da='docker attach'
# 	alias db='docker build'
# 	alias dps='docker ps'
# 	alias di='docker inspect'
# 	alias dn='docker network'
# 	alias ds='docker stop'

# 	alias dc='docker compose'
# 	alias dci='docker compose images'
# 	alias dcd='docker compose down'
# 	alias dcu='docker compose up'
# 	alias dcr='docker compose restart'

# 	alias dcrlf0='(){ docker compose restart "$1"; docker logs --follow --since=0m "$1" ; }'
# 	alias dcrlf1='(){ docker compose restart "$1"; docker logs --follow --since=1m "$1" ; }'
# 	alias dcrlf2='(){ docker compose restart "$1"; docker logs --follow --since=2m "$1" ; }'
# 	alias dcrlf3='(){ docker compose restart "$1"; docker logs --follow --since=3m "$1" ; }'

# 	alias d\?='alias | grep -P "(?<=\=)[\W]*\bdocker\b" | if type bat &>/dev/null; then bat -l bash -p; else cat /dev/stdin; fi'

# }; # define_docker_aliases
