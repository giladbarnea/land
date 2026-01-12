#!/usr/bin/env zsh

# llm.zsh: Wraps simonw/llm with sane(r) defaults, additional functionalities and improved UX.

typeset -g LLM_DEFAULT_TEMPLATE  # Deprecated, unused.



# # llm [llm options...] [-i, --inline-code-lexer LEXER=python] [--[no-]format-stdin] [--[no-]md] [--tag,--stdin-tag,-st TAG] [-q,--quiet] [--no-clear] [-w,--write PATH] [-re,--reasoning-effort {minimal,low,medium,high,auto} (default in model_options.json)]
# Wrapper for `simonw/llm` providing the following functionalities:
# 1. Formatting piped content for better prompt engineering.
# 2. Displaying the results in a markdown viewer.
# 3. Supporting URL attachments.  <- Buggy, commented out.
# 4. Writing the conversation to a file.
# 5. Auto-picking reasoning effort along with '-re' shortcut.
# Note:
# - `-s, --system` is mutually exclusive with `--template`, and takes precedence over it.
# Environment variables:
# - LLM_FORCE_MODEL: The model to use if specified. Overrides -m, --model.
# - LLM_FORCE_REASONING_EFFORT: The reasoning effort to use if specified. Overrides -re, --reasoning-effort.
function llm() {
	local -a frozen_original_args=("$@")
	local -a all_subcommands=(
		prompt
		aliases
		chat
		cluster
		cmd
		# cmdcomp  # Not currently installed.
		collections
		embed
		embed-models
		embed-multi
		fragments
		# These are commented on purpose: -m gemini or -m grok falsely recognized as the 'gemini' or 'grok' positional subcommands.
    	# gemini
    	# grok  
		install
		jq
		keys
		logs
		mistral
		models
		# notebook  # Not currently installed.
		openai
		openrouter
		plugins
		python
		schemas
		similar
		templates
		tools
		uninstall
		whisper-api
	)
	
	local -a supported_subcommands=(prompt chat cmd)    # Update completion at 'case $subcmd in'
	
	# Extract the first subcommand (making possible empty subcommand an explicit 'prompt' subcommand)
	local subcommand=prompt
	local arg supported_subcommand
	for arg in "$@"; do
		for a_subcommand in ${all_subcommands[@]}; do
			[[ "$arg" = "$a_subcommand" ]] && {
				subcommand="$arg"
				break 2
			}
		done
	done
	
	# If the subcommand is not supported by this wrapper, run vanilla llm and return the exit code.
	[[ 
		"${@[(r)--help]}" || "${@[(r)-h]}" || "${@[(r)--version]}"
		|| ! ${supported_subcommands[(r)$subcommand]} 
	]] && {
		[[ "$quiet" = false ]] && log.debug "$(typeset subcommand), running vanilla llm"
		command llm "$@"
		return $?
	}
	

	# Default values for functionalities
	local enable_piped_content_formatting=false
	local enable_markdown_viewer=false
	local default_template="${LLM_DEFAULT_TEMPLATE}"  # Deprecated.


	# Mapping of subcommands to functionalities they support
	local -a subcommands_supporting_markdown=(
		prompt
	)
	local -a subcommands_supporting_piped_content=(
		prompt
	)
	local -a subcommands_supporting_system_option=(
		chat prompt cmd cmdcomp
	)
	local -a subcommands_supporting_template_option=(
		prompt chat
	)
	local -a subcommands_supporting_model_option=(
		prompt chat cmd cmdcomp
	)
	local -a subcommands_supporting_clear_screen=(
		prompt
	)
	

	local markdown_inline_code_lexer
	local -a llm_opts=()
	local attachment
	local piped_content
	local stdin_tag
	local quiet=false
	local clear_screen=false
	local write_path _specified_write_path=false
	
	[[ "$LLM_FORCE_MODEL" ]] && {
		llm_opts+=(--model "$LLM_FORCE_MODEL")
	}

	[[ "$LLM_FORCE_REASONING_EFFORT" ]] && {
		llm_opts+=(-o reasoning_effort "$LLM_FORCE_REASONING_EFFORT")
	}

	# Adjust functionalities based on subcommand
	[[ ${subcommands_supporting_markdown[(r)$subcommand]} ]] \
			&& enable_markdown_viewer=true
	[[ ${subcommands_supporting_piped_content[(r)$subcommand]} ]] \
			&& enable_piped_content_formatting=true
	[[ ${subcommands_supporting_clear_screen[(r)$subcommand]} ]] \
		&& clear_screen=true
	
	local explicitly_specified_model
	local explicitly_specified_reasoning_effort
	local _system
	# Extract explicitly only options we want to manipulate. The rest go to *).
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--inline-code-lexer=*) markdown_inline_code_lexer="${1#*=}" ;;
			-i|--inline-code-lexer) markdown_inline_code_lexer="$2" ; shift ;;
			
			--attachment=*) attachment="${1#*=}" ;;
			-a|--attachment) attachment="$2" ; shift ;;

			--no-md) enable_markdown_viewer=false ;;
			--md) enable_markdown_viewer=true ;;
			
			--no-format-stdin) enable_piped_content_formatting=false ;;
			--format-stdin) enable_piped_content_formatting=true ;;
			
			-st=*|--tag=*|--stdin-tag=*) stdin_tag="${1#*=}" ;;
			-st|--tag|--stdin-tag) stdin_tag="$2" ; shift ;;
			
			-re|--reasoning-effort) 
				explicitly_specified_reasoning_effort="$2"; shift
				if [[ "$LLM_FORCE_REASONING_EFFORT" ]]; then
					log.warn "Ignoring specified reasoning effort '$explicitly_specified_reasoning_effort' because LLM_FORCE_REASONING_EFFORT is set to '$LLM_FORCE_REASONING_EFFORT'"
					continue
				fi
				llm_opts+=(-o reasoning_effort "$explicitly_specified_reasoning_effort") ;;
			-re=*|--reasoning-effort=*) 
				explicitly_specified_reasoning_effort="${1#*=}"
				if [[ "$LLM_FORCE_REASONING_EFFORT" ]]; then
					log.warn "Ignoring specified reasoning effort '$explicitly_specified_reasoning_effort' because LLM_FORCE_REASONING_EFFORT is set to '$LLM_FORCE_REASONING_EFFORT'"
					continue
				fi
				llm_opts+=(-o reasoning_effort "$explicitly_specified_reasoning_effort") ;;
			
			--system=*) 
				# Strip leading and trailing whitespace from system prompt
				_system="${1#*=}"
				_system="$(strip "$_system")"
				llm_opts+=(--system "$_system") 
				unset _system ;;
			-s|--system) 
				_system="$2"
				_system="$(strip "$_system")"
				llm_opts+=(--system "$_system") 
				unset _system
				shift ;;
				
			-m=*|--model=*) 
				explicitly_specified_model="${1#*=}"
				if [[ "$LLM_FORCE_MODEL" ]]; then
					log.warn "Ignoring specified model '$explicitly_specified_model' because LLM_FORCE_MODEL is set to '$LLM_FORCE_MODEL'"
					continue
				fi
				llm_opts+=(--model "$explicitly_specified_model") ;;
			-m|--model)
				explicitly_specified_model="$2"
				if [[ "$LLM_FORCE_MODEL" ]]; then
					log.warn "Ignoring specified model '$explicitly_specified_model' because LLM_FORCE_MODEL is set to '$LLM_FORCE_MODEL'"
					shift
					continue
				fi
				llm_opts+=(--model "$explicitly_specified_model")
				shift ;;
				
			-q|--quiet) quiet=true ;;
			--no-clear) clear_screen=false ;;

			--write=*) _specified_write_path=true; write_path="${1#*=}" ;;
			-w|--write) _specified_write_path=true; write_path="$2" ; shift ;;
			
			*) llm_opts+=("$1") ;;
		esac
		shift
	done
	
	
	if is_piped; then
		# piped_content_file=$(mktemp)
		# mime=$(tee "$piped_content_file" | file --mime-type - | awk '{print $2}')
		piped_content="$(<&0)"
	fi
	
	if is_piping || ! is_interactive; then
		[[ "$enable_markdown_viewer" = true ]] && {
			log.warn "Disabling markdown viewer because stdout is unavailable or shell is not interactive"
			enable_markdown_viewer=false
		}
		[[ "$clear_screen" = true ]] && {
			log.warn "Disabling clear screen because stdout is unavailable or shell is not interactive"
			clear_screen=false
		}
	fi
	
	# Functionality 1: Sane defaults
	
	# Pick out the prompt by exclusion. Hard coupled with the argument parsing at the beginning of the function.
	
	local -i i=1
	local -i prompt_arg_index
	local user_prompt
	local llm_opt
	while [[ $i -le ${#llm_opts[@]} ]]; do
		llm_opt="${llm_opts[$i]}"
		
		case "$llm_opt" in
			-o|--option) i+=3; continue ;;
			-p|--param) i+=3; continue ;;
			-at|--attachment-type) i+=3; continue ;;
			
			# Long or short -o=value or --option=value arguments
			-*=*) i+=1; continue ;;
			
			# Valueless bool flags
			-c|--continue) i+=1; continue ;;
			-n|--no-log) i+=1; continue ;;
			--log) i+=1; continue ;;
			--async) i+=1; continue ;;
			-u|--usage) i+=1; continue ;;
			-x|--extract) i+=1; continue ;;
			--xl|--extract-last) i+=1; continue ;;
			--no-stream) i+=1; continue ;;
			--td|--tools-debug) i+=1; continue ;;
			--ta|--tools-approve) i+=1; continue ;;
			--help) i+=1; continue ;;
			
			# Long or short '--option value' pairs.
			-*) i+=2; continue ;;
			*) 
				[[ ${all_subcommands[(r)$llm_opt]} ]] && {
					i+=1
					[[ "$quiet" = false ]] && log.debug "$(typeset llm_opt) is a supported subcommand, not setting it to \$user_prompt"
					continue
				}
				user_prompt="$llm_opt"
				prompt_arg_index=$i
				break
				;;
		esac
	done

	
	if [[ -z "$user_prompt" && "$quiet" = false ]]; then
		log.warn "Couldn't detect the positional prompt value"
	fi
	

	# Template. Mutually exclusive with `system` option, and takes precedence over it. Deprecated ($default_template is always empty.)
	if [[ -n "$default_template" ]] \
	    && ! .llm-has-opt "${llm_opts[@]}" -- '-t' '--template' \
		&& ! .llm-has-opt "${llm_opts[@]}" -- '-s' '--system' \
		&& ! .llm-has-opt "${llm_opts[@]}" -- '-c' '--continue' \
		&& ! .llm-has-opt "${llm_opts[@]}" -- '--cid' '--conversation'; then
		llm_opts+=(--template $default_template)
	fi
	
	
	
	# Functionality 2: Format piped content
	local has_piped_content=false
	[[ -n "$piped_content" ]] && has_piped_content=true
	if $enable_piped_content_formatting && $has_piped_content; then
		piped_content="$(.llm-xml-wrap -q "$piped_content" --stdin-tag "$stdin_tag")"
	fi
	
	
	# Functionality 3: Support URL attachments
	# local attachment_content formatted_attachment_content
	# if [[ "$attachment" = http*
	# 	|| "$attachment" = www* 
	# 	|| "$attachment" =~ '.*\.[[:alnum:]]{2,4}$' && ! -e "$attachment"
	# 	]]; then
	# 	attachment_content="$(cached llm-url-to-markdown "$attachment")"
	# 	formatted_attachment_content="$(.llm-xml-wrap -q "$attachment_content" --stdin-tag 'web page')"
	# 	piped_content+="$formatted_attachment_content"
	# 	has_piped_content=true
	# fi

	
	# Give the user prompt a header if the piped content is long and the prompt is short.
	if [[ "$user_prompt" && $has_piped_content = true ]]; then
		local -i piped_content_length="${#piped_content}"
		local -i prompt_length="${#user_prompt}"
		local _first_nonblank=${${(@f)user_prompt}:#(|[[:space:]])}
		
		# If the prompt doesn't start with "user", 
		# and the piped content is long, 
		# and the prompt is short
		# add a header to the prompt.
		if [[ "${_first_nonblank:l}" != *user* ]] \
			&& (( piped_content_length > 1000 )) \
			&& (( piped_content_length / prompt_length > 20 )) \
			then
			user_prompt="$(printf "\n\n---\n\n# User Message\n\n%s" "$user_prompt")"
		fi
		# printf is required for actual newlines.
		user_prompt="$(printf "%s\n\n%s" "$piped_content" "$user_prompt" | sed 's/\\0/NULLBYTE/g')"
		llm_opts[$prompt_arg_index]="$user_prompt"
	fi
	
	if [[ -z "$user_prompt" && $has_piped_content = true ]]; then
		user_prompt="$piped_content"
		llm_opts+=("$user_prompt")
	fi
	
	if [[ -n "$explicitly_specified_reasoning_effort" ]]; then
		case "$explicitly_specified_reasoning_effort" in
			auto)
				local auto_picked_reasoning_effort
				auto_picked_reasoning_effort="$(.llm-auto-reasoning-effort "$user_prompt")"
				llm_opts+=(-o reasoning_effort "$auto_picked_reasoning_effort") ;;
			*) 
				llm_opts+=(-o reasoning_effort "$explicitly_specified_reasoning_effort")
				;;
		esac
	fi
	
	# Recurse if multiple models are specified.
	# Because stdin can be consumed only once, this has to be done only at this late stage.
	if [[ "${explicitly_specified_model}" && "${explicitly_specified_model}" = *,* ]]; then
		local -a models=(${(s:,:)explicitly_specified_model})
		log.notice "Running llm with multiple models: ${(j:, :)models}"
		local -a llm_opts_without_model
		# Pluck out the model option and value from llm_opts:
		if [[ ${llm_opts[(r)--model=*]} ]]; then
			llm_opts_without_model=(${llm_opts:#--model=*})
		elif [[ ${${llm_opts[(r)--model]}:-${llm_opts[(r)-m]}} ]]; then
			local _opt_index=${llm_opts[(I)${llm_opts[(r)--model]:-${llm_opts[(r)-m]}}]}
			llm_opts_without_model=(${llm_opts:0:$_opt_index-1} ${llm_opts:$_opt_index+1})
		else 
			log.error "Can't happen. No model option found in llm_opts, and explicitly_specified_model is set to '$explicitly_specified_model'"
			return 1
		fi
		log.debug "llm_opts_without_model:"
		shortarr "$(typeset llm_opts_without_model)" -d '\n'
		local -A response_files=()
		local aggregated_response_file="$(mktemp).md"
		local model
		for model in "${models[@]}"; do
			response_files[$model]="$(mktemp)"
			log.notice "Invoking $model. Writing to ${response_files[$model]}"
			{ command llm "${llm_opts_without_model[@]}" --model "$model" > "${response_files[$model]}" ; } &
		done
		log.notice "Waiting for llms to finish..."
		wait
		log.notice "All processes finished. Aggregating responses."
		for model in "${models[@]}"; do
			{ 
				print -- "# $model\n\n"
				cat "${response_files[$model]}"
				print -- "\n\n"
				} >> "$aggregated_response_file"
		done
		if [[ $enable_markdown_viewer = true ]]; then
			# Clear the screen
			[[ "$clear_screen" = true ]] && echo -n $'\e[2J'
			[[ -n "$markdown_inline_code_lexer" ]] && {
				richmd "$aggregated_response_file" -i "$markdown_inline_code_lexer"
				return $?
			}
			richmd "$aggregated_response_file"
		fi
		return
	fi
	
	[[ "$write_path" ]] || write_path="$(mktemp)"
	[[ "$quiet" = false ]] && {
		log.debug "\n$(typeset subcommand enable_markdown_viewer enable_piped_content_formatting markdown_inline_code_lexer has_piped_content stdin_tag attachment write_path clear_screen | rs 0 2)"
		log.debug "${C0}llm_opts:${Cd}\n$(shortarr "$(typeset llm_opts)")"
	}
	print_hr
	
	
	# Run llm command
	local -i llm_exit_code=0
	if [[ $enable_markdown_viewer = true || $_specified_write_path = true ]]; then
		command llm "${llm_opts[@]}" | tee "$write_path"
		llm_exit_code=${pipestatus[1]}
	else
		command llm "${llm_opts[@]}"
		llm_exit_code=$?
	fi
	
	if [[ "$llm_exit_code" != 0 ]]; then
		log.error "llm command failed with exit code $llm_exit_code"
		return $llm_exit_code
	fi
	

	# Functionality 3: Display results in markdown viewer
	if [[ $enable_markdown_viewer = true ]]; then
		[[ -s "$write_path" ]] || {
			log.error "llm command returned empty output. Empty file: $write_path"
			return 1
		}

		# Clear the screen
		[[ "$clear_screen" = true ]] && echo -n $'\e[2J'
		[[ -n "$markdown_inline_code_lexer" ]] && {
			richmd "$write_path" -i "$markdown_inline_code_lexer"
			return $?
		}
		richmd "$write_path"
	fi
}

# region [-------- Subcommand Enhancements --------]

# # llm-logs [-n,--count COUNT=0 (All logs)] [--no-messages,--all-messages] [llm logs list options besides --json, -s,--short, -x,--extract, --xl,--extract-last, -r,--response, -u,--usage, -t,--truncate]
# Displays yaml logs of conversation_id, model, system, prompt, and response, truncated to $COLUMNS characters.
# Conversations are sorted chronologically, and by default, only the first message of each conversation_id is displayed.
# If --no-messages is specified, only the conversation_id, model, conversation_name, and datetime_utc fields are included.
# Unless --all-messages is specified, all messages of each conversation_id are included. Mutually exclusive with --no-messages.
function llm-logs(){
	local -a llm_list_opts=()
	local -i last_n=0
	local no_messages=false
	local include_all_messages=false
	while [[ $# -gt 0 ]]; do
		case "$1" in
			-n|--count) last_n="$2" ; shift ;;
			-n=*|--count=*) last_n="${1#*=}" ;;
			--no-messages=*) no_messages="${1#*=}" ;;
			--no-messages) no_messages=false ;;
			--all-messages=*) include_all_messages="${1#*=}" ;;
			--all-messages) include_all_messages=true ;;
			*) llm_list_opts+=("$1") ;;
		esac
		shift
	done
	
	if is_piped; then
		command llm logs list --count="${last_n}" --json  "${llm_list_opts[@]}" | .llm-truncate-conv-array --no-messages=$no_messages --all-messages=$include_all_messages
	else
		command llm logs list --count="${last_n}" --json  "${llm_list_opts[@]}" | .llm-truncate-conv-array --no-messages=$no_messages --all-messages=$include_all_messages | yq --prettyPrint
	fi
}

# # .llm-truncate-conv-array [--no-messages,--all-messages]
# Truncates each conversation in a conversation array (from llm logs list --json) by truncating the prompt, response, and system fields of each message, and by default, showing only the first message of each conversation_id.
# If --no-messages is specified, only the conversation_id, model, conversation_name, and datetime_utc fields are included.
# Unless --all-messages is specified, all messages of each conversation_id are included. Mutually exclusive with --no-messages.
# The output is a JSON array of truncated conversations.
function .llm-truncate-conv-array(){
	local no_messages=false
	local include_all_messages=false
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--no-messages=*) no_messages="${1#*=}" ;;
			--no-messages) no_messages=false ;;
			--all-messages=*) include_all_messages="${1#*=}" ;;
			--all-messages) include_all_messages=true ;;
			*)
				log.error "$0: Unsupported option: ${1}. Currently expects input from stdin."
				return 1
				;;
		esac
		shift
	done
	if $no_messages && $include_all_messages; then
		# Subtle bug: relies on defaults no_messages=false and include_all_messages=false.
		log.error "$0: --no-messages and --all-messages cannot be used together."
		return 1
	fi
	
	$include_all_messages && no_messages=false
	
	log.debug "$(typeset include_all_messages no_messages)"

	local -a jq_expressions
	if $no_messages; then
		jq_expressions=(
			'map({conversation_id, model, conversation_name, datetime_utc})'
			'unique_by(.conversation_id)'
		)
	else
		# Todo: account for line breaks. $((${#x} - ${#${x//'\n'/}}))
		local map_expression='map({conversation_id, model, conversation_name, datetime_utc, system, prompt, response})'
		local -a shortening_expressions=(
			# '    "prompt": "' is 15 chars, plus 3 for good measure, which is 9+9=18. Separator is 5 chars, which is 2+3=5.
			"map(.prompt |= if (length > $((COLUMNS-18))) then .[0:$((COLUMNS/2-9-2))] + \" ... \" + .[-$((COLUMNS/2-9-3)):] else . end)"

			# '    "response": "' is 17 chars, plus 3 for good measure, which is 10+10=20.
			"map(.response |= if (length > $((COLUMNS-20))) then .[0:$((COLUMNS/2-10-2))] + \" ... \" + .[-$((COLUMNS/2-10-3)):] else . end)"

			# '    "system": "' is 15 chars, plus 3 for good measure, which is 9+9=18.
			"map(.system |= if (length > $((COLUMNS-18))) then .[0:$((COLUMNS/2-9-2))] + \" ... \" + .[-$((COLUMNS/2-9-3)):] else . end)"
		)
		if $include_all_messages; then
			jq_expressions=(
				"$map_expression"
				"${shortening_expressions[@]}"
			)
		else
			jq_expressions=(
				"$map_expression"
				"unique_by(.conversation_id)"
				"${shortening_expressions[@]}"
			)
		fi
	fi
	local joined_jq_expressions="${(j. | .)jq_expressions}"
	jq "$joined_jq_expressions"
}


# # llm-response [-d,--delimiter CHAR] [llm logs list options besides -r,--response, -s,--short, -q,--query, -u,--usage, --json, -t,--truncate]
# Prints the N model responses (default 1).
# If -n is 1, prints the raw response of the last log.
# If -n is not 1, prints a JSON array of the responses.
# If -d,--delimiter is specified, prints the raw responses separated by the delimiter.
# Example: `llm-response -n 4 -d ---`.
function llm-response(){
	local -a llm_list_opts=()
	local -i last_n=1
	local delimiter
	while [[ $# -gt 0 ]]; do
		case "$1" in
			-n|--count) last_n="$2" ; shift ;;
			-n=*|--count=*) last_n="${1#*=}" ;;
			-d|--delimiter) delimiter="$2" ; shift ;;
			-d=*|--delimiter=*) delimiter="${1#*=}" ;;
			*) llm_list_opts+=("$1") ;;
		esac
		shift
	done
	case "$last_n" in
		1)
			[[ "$delimiter" ]] && {
				log.error "llm-response: -d,--delimiter is not supported with -n 1."
				return 1
			}
			command llm logs list -n "${last_n}" --response "${llm_list_opts[@]}" ;;
		# Upstream `llm logs --response` prints only the response of the last log, regardless of `-n`. So we parse it ourselves.
		*) 
			[[ "$delimiter" ]] && {
				command llm logs list -n "${last_n}" --json "${llm_list_opts[@]}" \
					| jq 'map(.response)' -r \
					| python3.13 -OBIS -c "import json; import sys; print(*json.loads(sys.stdin.read()), sep='\n${delimiter}\n')"
				return $?
			}
			command llm logs list -n "${last_n}" --json "${llm_list_opts[@]}" | jq 'map(.response)' -r ;;
	esac
}

# # llm-cids [-n,--count COUNT=0 (All logs)] [llm logs list options besides --json, -s,--short, -t,--truncate, -u,--usage]
# Prints the conversation ids of the last N logs.
function llm-cids(){
	local -a llm_list_opts=()
	local -i last_n=0
	while [[ $# -gt 0 ]]; do
		case "$1" in
			-n|--count) last_n="$2" ; shift ;;
			-n=*|--count=*) last_n="${1#*=}" ;;
			*) llm_list_opts+=("$1") ;;
		esac
		shift
	done
	command llm logs list --count="${last_n}" --json "${llm_list_opts[@]}" | jq -r '.[] | .conversation_id' | sort -u
}

# # llm-usage [llm logs list options besides -u,--usage, --json, -t,--truncate, -s,--short]
# Prints the cost of the last N logs in USD.
function llm-usage(){
	local -i last_n=1
	local -a python_program=(
		"import json"
		"import sys"
		"costs = {"
		"    'anthropic/claude-sonnet-4-0': dict(input=3.0, output=15.0, prompt_caching_write=3.75, prompt_caching_read=0.30),"
		"    'gemini/gemini-2.5-flash-lite-preview-06-17': dict(input=0.1, output=0.4, input_audio=0.3, batch_discount=0.5, output_includes_reasoning=True),"
		"    'gemini/gemini-2.5-flash': dict(input=0.3, output=2.5, images=1.238),"
		"    'gemini/gemini-2.5-pro': dict(input=1.25, output=10.0, context_caching=0.31, output_includes_reasoning=True),"
		"    'gpt-4.1-mini': dict(input=0.4, output=1.6, cached_input=0.1),"
		"    'gpt-4.1': dict(input=2.0, output=8.0, cached_input=0.5),"
		"    'gpt-5': dict(input=1.25, output=10.0, cached_input=0.125),"
		"    'gpt-5-mini': dict(input=0.25, output=2.0, cached_input=0.025),"
		"    'gpt-5-nano': dict(input=0.05, output=0.4, cached_input=0.005),"
		"    'o3-mini': dict(input=1.1, output=4.4),"
		"    'o3': dict(input=2.0, output=8.0, cached_input=0.5),"
		"    'openrouter/anthropic/claude-sonnet-4': dict(input=3.0, output=15.0, prompt_caching_write=3.75, prompt_caching_read=0.30),"
		"    'openrouter/google/gemini-2.5-flash-lite-preview-06-17': dict(input=0.1, output=0.4, input_audio=0.3, batch_discount=0.5, output_includes_reasoning=True),"
		"    'openrouter/google/gemini-2.5-flash': dict(input=0.3, output=2.5, images=1.238),"
		"    'openrouter/google/gemini-2.5-pro': dict(input=1.25, output=10.0, context_caching=0.31, output_includes_reasoning=True),"
		"    'openrouter/openai/gpt-5': dict(input=1.25, output=10.0, cached_input=0.125),"
		"    'openrouter/openai/gpt-5-mini': dict(input=0.25, output=2.0, cached_input=0.025),"
		"    'openrouter/openai/gpt-5-nano': dict(input=0.05, output=0.4, cached_input=0.005),"
		"    'openrouter/openai/o3-mini-high': dict(input=1.1, output=4.4),"
		"    'openrouter/openai/o3-mini': dict(input=1.1, output=4.4),"
		"    'openrouter/openai/o3': dict(input=2.0, output=8.0, cached_input=0.5),"
		"    'openrouter/x-ai/grok-4': dict(input=3.0, output=15.0),"
		"}"
		"messages = json.loads(sys.stdin.read())"
		"cost = 0"
		"M = 1000000"
		"for message in messages:"
		"    model = message['model']"
		"    in_tokens = message['input_tokens']"
		"    out_tokens = message['output_tokens']"
		"    reasoning_tokens_key = next((key for key in message.keys() if 'reasoning' in key), None)"
		"    reasoning_tokens = message.get(reasoning_tokens_key, 0)"
		"    cost += (in_tokens/M) * costs[model]['input'] + (out_tokens/M) * costs[model]['output'] + (reasoning_tokens/M) * costs[model]['reasoning']"
		"print(f'{cost:,.4f}')"
	)
	command llm logs list --count="${last_n}" --usage --json --truncate "$@" | \
	 python3.13 -OBIS -c "${(F)python_program}"
}


# # llm-conv-to-md <JSON_FILE/JSON_STRING/STDIN> [-s,--separator {md,xml,md+xml} (default md+xml)]
# Converts AI conversation JSON data to a "good enough" Markdown format.
# Usage:
#   llm-conv-to-md <json_file>
#   llm-conv-to-md '<json_string>'
#   cat data.json | llm-conv-to-md
# The output Markdown will have a YAML frontmatter with id, datetime_utc, and model (from conversation_model) from the first message.
# Depending on the separator, user and assistant messages will be formatted according to the following rules:
# - md+xml: Both <xml> tags and # User / # Assistant headers.
# - md: # User / # Assistant headers.
# - xml: <USER> / <ASSISTANT> tags.
# The default separator is md+xml.
function llm-conv-to-md() {
    local json_input
    local source_description
	local separator=md+xml
	while [[ $# -gt 0 ]]; do
	  case "$1" in
		--separator=*) separator="${1#*=}" ;;
		--separator) separator="$2" ; shift ;;
		*) 
			# Determine input source
			if [[ -f "$1" ]]; then # First argument is a file
				json_input=$(<"$1")
				source_description="file '$1'"
			else # First argument is a JSON string
				json_input="$1"
				source_description="string argument"
			fi
			;;
	  esac
	  shift
	done

    
    if [[ -z "$json_input" ]] && is_piped; then
		json_input=$(<&0)
	fi
    if [[ -z "$json_input" ]]; then
        log.error "No JSON input received."
		docstring -p "$0"
        return 1
    fi

    # Validate JSON and ensure it's an array
    if ! jq -e 'type == "array"' >/dev/null 2>&1 <<<"$json_input"; then
        local is_json_valid=false
        if jq -e . >/dev/null 2>&1 <<<"$json_input"; then
            is_json_valid=true
        fi
        if $is_json_valid; then
            log.error "Input from $source_description is valid JSON, but not a JSON array as expected for conversation data."
        else
            log.error "Invalid JSON input from $source_description."
        fi
        return 1
    fi

    # Handle empty array case
    if jq -e 'length == 0' >/dev/null 2>&1 <<<"$json_input"; then
        # Output valid frontmatter even for an empty array, with N/A values
        print -- "---"
        print -- "conversation_id: N/A (empty conversation)"
        print -- "datetime_utc: N/A (empty conversation)"
        print -- "model: N/A (empty conversation)"
        print -- "# Warning: JSON array was empty. No conversation messages to process."
        print -- "---"
        return 0
    fi

    # Generate Frontmatter from the first element
    # Using `// "N/A"` as a fallback for potentially missing fields
    jq -r '
        .[0] |
        "---\n" +
        "conversation_id: \(.conversation_id // "N/A")\n" +
        "datetime_utc: \(.datetime_utc // "N/A")\n" +
        "model: \(.conversation_model // "N/A")\n" +
        "---\n"
    ' <<<"$json_input"

    # Set up separator strings based on the chosen format
	local user_open_string
	local user_close_string
	local assistant_open_string
	local assistant_close_string
	case "$separator" in
		md+xml)
			user_open_string="$(printf "---\n<USER>\n# User")"
			user_close_string="$(printf "</USER>")"
			assistant_open_string="$(printf "---\n<ASSISTANT>\n# Assistant")"
			assistant_close_string="$(printf "</ASSISTANT>")"
			;;
		md)
			user_open_string="$(printf "---\n# User")"
			user_close_string="$(printf "\n")"
			assistant_open_string="$(printf "---\n# Assistant")"
			assistant_close_string="$(printf "\n")"
			;;
		xml)
			user_open_string="$(printf "---\n<USER>")"
			user_close_string="$(printf "</USER>")"
			assistant_open_string="$(printf "---\n<ASSISTANT>")"
			assistant_close_string="$(printf "</ASSISTANT>")"
			;;
		*)
			log.error "Unknown separator: $separator"
			return 1
			;;
	esac

    # Generate Messages with injected variables
    jq -r --arg user_open "$user_open_string" \
          --arg user_close "$user_close_string" \
          --arg assistant_open "$assistant_open_string" \
          --arg assistant_close "$assistant_close_string" '
        [
            .[] |
            (
                $user_open + "\n\n" +
                # Ensure prompt is treated as string; use empty string if null/missing
                (.prompt | if type == "string" then . else tostring end // "") +
                "\n" + $user_close + "\n\n" +
                $assistant_open + "\n\n" +
                # Ensure response is treated as string; use empty string if null/missing
                (.response | if type == "string" then . else tostring end // "") +
                "\n" + $assistant_close + "\n"
            )
        ] | join("\n\n") # Join the formatted message blocks with two newlines
    ' <<<"$json_input"
}

# # llm-templates-path [llm templates path]
# Wraps `llm templates path` to cache the `path` subcommand.
function llm-templates-path(){
	cached command llm templates path "$@"
}

# # llm-embed-dir COLLECTION DIRECTORY_PATH [-n,--dry-run]
# Embeds all files in a given directory. Leverages `fd` as a filter.
function llm-embed-dir(){
	
	local dry_run=false
	local collection
	local directory_path
	while [[ $# -gt 0 ]]; do
	  case "$1" in
		-n|--dry-run) dry_run=true ;;
		*) 
			collection="$1"
			directory_path="$2"
			shift 2 2>/dev/null || {
				log.error "Usage: llm-embed-dir COLLECTION DIRECTORY_PATH"
				return 1
			}
			break ;;
	  esac
	  shift
	done
	[[ ! "$collection" || ! -d "$directory_path" ]] && {
		log.error "Not enough arguments were provided."
		docstring -p "$0"
		return 1
	}
	local -a matching_files
	local -aU extensions
	matching_files=($(fd -t f . "$directory_path"))
	extensions=("${(@)matching_files:e}")
	[[ "$dry_run" = true ]] && {
		log.notice "Dry run: would embed the following ${#matching_files[@]} files:"
		print -l "${matching_files[@]}"
		log.notice "Which comes down to these ${#extensions[@]} extensions:"
		typeset extensions
		print -l "${(@)extensions#"''"}"
		return 0
	}

	local extension
	for extension in "${extensions[@]}"; do
		[[ ! "$extension" ]] && continue
		llm embed-multi "$collection" --files "$directory_path" "**/*.$extension"
	done
}


# endregion [-------- Subcommand Enhancements --------]

# region [-------- Templates --------]

# # simplify [llm options...]
# Simplifies the given input using the `simplify` template (assistant system prompt).
# Unsupported llm options: -t,--template
function simplify(){
	local -a llm_args=(
		--template "$(.llm-merge-templates assistant simplify)"
	)
	llm --stdin-tag 'text' --no-md --no-clear "$@" "${llm_args[@]}"
}

# # compress [-r,--rate {aggressive|high-quality=high-quality}] [llm options...]
# Compresses the given input using the `compress` template.
# Unsupported llm options: -s,--system
function compress(){
	local rate=high-quality
	local -a llm_opts
	while [[ $# -gt 0 ]]; do
		case "$1" in
			-r|--rate) rate="$2" ; shift ;;
			-r=*|--rate=*) rate="${1#*=}" ;;
			*) llm_opts+=("$1") ;;
		esac
		shift
	done
	log.debug "$(typeset rate)"
	llm "${llm_opts[@]}" --no-clear --system "$(llm-template .compress_base | yq .${rate})"
}

# # merge [llm options...] [--plan,--no-plan (default: --no-plan)] [--prompt-append PROMPT_APPEND] [--strategy {default,pick-best}]
# Merges two texts into one.
# 'pick-best' strategy doesn't try to squish overlapping items, but instead picks the best as-is. Implies --plan.
# TODO:
# If data is piped, assumes that is already formatted (--no-stdin-format by default.)
# If two positional arguments are given, ignores stdin and formats them with <text 1> and <text 2> by default.
# If one positional argument is given, ignores stdin and formats it with "Given the following:"
function merge(){
	local -a llm_opts
	# local -a merge_targets
	# local should_format_stdin=false
	# local has_piped_content=false
	local plan=false
	local prompt_append
	local strategy  # default, pick-best
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--plan) plan=true ;;
			--no-plan) 
				plan=false 
				[[ "$strategy" != "default" ]] && {
					log.error "Strategy '$strategy' implies --plan."
					return 1
				}
				strategy=pick-best
				;;
			--prompt-append) prompt_append="$2" ; shift ;;
			--prompt-append=*) prompt_append="${1#*=}" ;;
			-X|--strategy) strategy="$2" ; shift ;;
			--strategy=*) strategy="${1#*=}" ;;
			*) llm_opts+=("$1") ;;
		esac
		shift
	done
	[[ "$strategy" != "default" ]] && plan=true
	
	# local system_prompt="$(llm-template merge)"
	local system_prompt="Merge the given texts into a single text.
Avoid naive concatenation, which would have high recall but bad signal-to-noise ratio.
A good merge eliminates redundancies by selecting or creating the best version of any overlapping content.
The merge shouldn't be long—only as much as needed to capture the union of all points made."
	if [[ "$plan" = false ]]; then
		# Bug: positional prompt has to be specified by the user.
		llm --system "$system_prompt" "${llm_opts[@]}"
		return $?
	fi
	
	local plan_prompt='Only tell me which points are shared between the texts, which are unique to the first text, and which are unique to the second text. If there are contradictory items between the texts, mention them. Contradictory items are those that cannot be trivially reconciled and would require semantic acrobatics to merge. Reference the item names as they appear in the original texts.'
	log.notice "Planning..."
	differentiate "${llm_opts[@]}" -q --no-md --no-clear
	log.notice "Merging with $strategy strategy..."
	local merge_prompt='Ok, great. Now perform the merge. Unique items (appear in only one text) should be copied exactly as-is, unchanged. Items that appear in both texts should be merged according to your instructions. If you have indeed detected contradictory items in your last response, do not merge them, but mention them as is at the end of the response.'
	case "$strategy" in
		default) : ;;
		pick-best)
			merge_prompt+='
Instructions on how to merge items that appear in both texts: pick the best item out of the two, and copy it as-is; discard the other.'
			;;
		*) log.error "Unknown strategy: $strategy"
			return 1
			;;
	esac
	if [[ -n "$prompt_append" ]]; then
		merge_prompt+=" $prompt_append"
	fi
	llm --continue "$merge_prompt" -q "${llm_opts[@]}"
}

# # differentiate [llm options...]
# Outlines the common and the unique to each of the two texts.
function differentiate(){
	local -a llm_opts=("$@")
	
	# local system_prompt="$(llm-template merge)"
	local system_prompt="Merge the given texts into a single text.
Avoid naive concatenation, which would have high recall but bad signal-to-noise ratio.
A good merge eliminates redundancies by selecting or creating the best version of any overlapping content.
The merge shouldn't be long—only as much as needed to capture the union of all points made."
	
	system_prompt+='
Only tell me which points are shared between the texts, which are unique to the first text, and which are unique to the second text. If there are contradictory items between the texts, mention them. Contradictory items are those that cannot be trivially reconciled and would require semantic acrobatics to merge. Reference the item names as they appear in the original texts.'
	log.notice "Differentiating..."
	llm --system "$system_prompt" "${llm_opts[@]}"
}

# # agents [llm options...]
# Breaks down the given input into a list of tasks and executes them in parallel.
# The input is processed into a YAML list of objects (under a single root `tasks` key), each with the following keys:
# - task_goal: The goal of the task.
# - success_criteria: When to consider the task complete.
# - stop_criteria: When to stop and output the results accumulated so far.
# - do: recommended actions to take to achieve the task goal.
# - avoid: actions to avoid during execution.
# - methodology: The methodology to use to achieve the task goal.
# - expected_challenges: A list of expected challenges that may arise and how to address them.
# The list is parsed with `yq` and set into the `tasks` array.
# Each task is executed asynchronously via `coproc` zsh builtin: `llm -m anthropic/claude-sonnet-4-0 "$task"`.
function agents(){
	# Can use this template:
	# For each LLM, find the latest inference API pricing (sometimes called “completions” or “chat completions”) from the provider’s official website or documentation. Pricing is usually shown in a table with input and output columns, and sometimes additional columns for reasoning/thinking, images, or other modalities: <aliases.json>. Most providers have two price tiers based on a token threshold (e.g., 200K): one for conversations below the threshold and a higher tier for conversations above it. Your task: extract the price for each available column (in addition to input/output) for the below-threshold tier (“conversation is not yet big”). If both tiers are listed, report both.
	setopt localoptions errreturn pipefail
	local -a llm_opts
	local -a tasks
	local input_content
	local quiet=false
	
	# Parse arguments
	while [[ $# -gt 0 ]]; do
		case "$1" in
			-q|--quiet) quiet=true ;;
			*) llm_opts+=("$1") ;;
		esac
		shift
	done
	
	# Get input content
	if is_piped; then
		input_content="$(<&0)"
	else
		log.error "No input provided. Please pipe content to agent."
		return 1
	fi
	
	[[ -z "$input_content" ]] && {
		log.error "Empty input provided."
		return 1
	}
	
	# System prompt for breaking down into tasks
	local task_breakdown_prompt='Break down the given input into a list of specific, actionable tasks that can be executed in parallel. Return the result as syntactically valid YAML with a single root key "tasks" containing an array of task objects. Each task object must have the following exact keys. Their values are strings:

- task_goal: A clear, specific goal for this task.
- success_criteria: Concrete criteria for when this task is complete
- stop_criteria: When to stop and output results accumulated so far
- do: Recommended actions to take to achieve the task goal
- avoid: Actions to avoid during execution
- methodology: The methodology/approach to use
- expected_challenges: List of expected challenges and how to address them

Make tasks as independent as possible so they can run in parallel. If the user input describes a task that needs to be performed for each X, Y, Z, then create a task for each X, Y, Z.
The instructions for the tasks should be descriptive rather than prescriptive. Be clear and cohesive.

Only break down into tasks. Do not add an aggregation task.

Format Instructions:
Output valid, parsable YAML as instructed. Do not write any explanations, introductions, signoffs, or any other text — just the YAML.
'
	
	[[ "$quiet" = false ]] && log.notice "Breaking down input into parallel tasks..." -L -x
	
	# Generate task breakdown
	local tasks_yaml_file="$(mktemp).yaml"
	local task_breakdown_output
	task_breakdown_output="$(echo "$input_content" | llm "Follow your system instructions." --system "$task_breakdown_prompt" -m 5m -re low --no-md --quiet --no-clear "${llm_opts[@]}")" || {
		log.error "Failed to generate task breakdown"
		return 1
	}
	
	echo "$task_breakdown_output" > "$tasks_yaml_file"
	
	# Validate and parse YAML
	if ! yq '.tasks' "$tasks_yaml_file" >/dev/null 2>&1; then
		log.error "Invalid YAML structure. Expected 'tasks' root key."
		[[ "$quiet" = false ]] && {
			log.error "Generated output ($tasks_yaml_file):"
			cat "$tasks_yaml_file"
		}
		return 1
	fi
	
	# Extract tasks array
	local -i task_count
	task_count="$(yq '.tasks | length' "$tasks_yaml_file")"
	
	[[ $task_count -eq 0 ]] && {
		log.error "No tasks found in breakdown."
		return 1
	}
	
	yq "$tasks_yaml_file"
	
	confirm "Execute these $task_count tasks?" || return 1
	
	[[ "$quiet" = false ]] && log.info "Executing $task_count tasks in parallel..." -L -x
	
	# Prepare temporary files for task results
	local -a task_result_files
	local -a task_pids
	local -A task_coproc_names
	local -i i
	
	for ((i=1; i<=task_count; i++)); do
		task_result_files[$i]="$(mktemp)"
	done
	log.debug "$(typeset task_result_files tasks_yaml_file)"
	
	# Execute each task in parallel using coproc
	# Here, `i` is for yaml array index, so it's 0-based.
	for ((i=0; i<task_count; i++)); do
		local task_yaml="$(yq ".tasks[$i]" "$tasks_yaml_file")"
		local task_goal="$(yq '.task_goal' <<< "$task_yaml")"
		
		[[ "$quiet" = false ]] && log.notice "Starting task $((i+1))/$task_count: $task_goal" -L -x
		
		# Format task as a comprehensive prompt
		local task_prompt="$(printf "Execute this task:\n\n%s\n\nProvide a comprehensive response addressing the task goal." "$task_yaml")"
		
		# Start coprocess for this task
		# We need to be careful with coproc naming and management
		# fix: this is unused?
		local coproc_name="task_$((i+1))"
		task_coproc_names[$((i+1))]="$coproc_name"
		
		# Use a subshell to handle each task independently
		(
			# Execute the LLM command and save result
			{
				llm "$task_prompt" -m @gemini --no-md --quiet --no-clear "${llm_opts[@]}" > "${task_result_files[$((i+1))]}" 2>&1
				echo $? > "${task_result_files[$((i+1))]}.exitcode"
			}
		) &
		
		task_pids[$((i+1))]="$!"
	done
	
	# Wait for all tasks to complete
	local -i completed_count=0
	local -i failed_count=0
	
	# Here, `i` is for zsh array index, so it's 1-based.
	for ((i=1; i<=task_count; i++)); do
		local pid="${task_pids[$i]}"
		
		if wait "$pid"; then
			completed_count+=1
			[[ "$quiet" = false ]] && log.info "Task $i completed successfully" -L -x
		else
			failed_count+=1
			[[ "$quiet" = false ]] && log.error "Task $i failed" -L -x
		fi
	done
	
	[[ "$quiet" = false ]] && log.info "Completed: $completed_count/$task_count tasks ($failed_count failed)" -L -x
	
	# Aggregate and display results
	local results_file="$(mktemp)"
	log.debug "$(typeset results_file)"
	{
		echo "# Agent Task Execution Results"
		echo
		echo "**Summary:** $completed_count/$task_count tasks completed ($failed_count failed)"
		echo
		
		# Here, `i` is for yaml array index, so it's 0-based.
		for ((i=0; i<task_count; i++)); do
			local task_goal="$(yq ".tasks[$i].task_goal" "$tasks_yaml_file")"
			local exit_code=0
			
			if [[ -f "${task_result_files[$((i+1))]}.exitcode" ]]; then
				exit_code="$(<"${task_result_files[$((i+1))]}.exitcode")"
			fi
			
			echo "## Task $((i+1)): $task_goal"
			
			if [[ $exit_code -eq 0 ]]; then
				echo "**Status:** ✅ Completed"
			else
				echo "**Status:** ❌ Failed (exit code: $exit_code)"
			fi
			
			echo
			if [[ -s "${task_result_files[$((i+1))]}" ]]; then
				cat "${task_result_files[$((i+1))]}"
			else
				echo "*No output generated*"
			fi
			echo
			echo "---"
			echo
		done
	} > "$results_file"
	
	log.info "Results ($results_file):" -L -x
	# Display results
	cat "$results_file"
	
	return $failed_count
}


# # zshai [llm options...]
# Uses the `zshai` template (assistant system prompt).
# Unsupported llm options: -s,--system
function zshai(){
	setopt localoptions errreturn
	local parsed_zshai_system_prompt="$(.llm-interpolate-template-variables zshai)"
	llm --system "$parsed_zshai_system_prompt" --no-md --no-clear "$@" 
	llm-code-block --lexer zsh
}

# # zshcmd [-m,--model MODEL]
# Uses the `zshcmd` system prompt and the default model.
function zshcmd(){
	setopt localoptions errreturn pipefail
	local parsed_zshcmd_system_prompt="$(.llm-interpolate-template-variables zshcmd)"
	llm --extract-last --no-md --system "$parsed_zshcmd_system_prompt" --no-clear "$@" | copee
}

# # pyai [llm options...]
# Uses the `pyai` template.
# Unsupported llm options: -t,--template, -s,--system
function pyai(){
	setopt localoptions errreturn
	local parsed_pyai_system_prompt="$(.llm-interpolate-template-variables pyai)"
	llm --system "$parsed_pyai_system_prompt" --no-md --no-clear "$@"
	llm-code-block
}

# # pycmd [-m,--model MODEL]
# Uses the `pycmd` template.
# Unsupported llm options: -t,--template, -s,--system
function pycmd(){
	setopt localoptions errreturn
	local parsed_pycmd_system_prompt="$(.llm-interpolate-template-variables pycmd)"
	llm --system "$parsed_pycmd_system_prompt" --no-md --no-clear "$@"
}


# # llmpy [python options...]
# Convenience wrapper for `llm python`.
function llmpy(){ 
	command llm python "$@"
}


# # ppx @use:.ppx
function ppx(){ .ppx "$@" -m sonar-pro ; }
# # ppx+ @use:.ppx
function ppx+(){ .ppx "$@" -m sonar-reasoning-pro ; }
# # ppx++ @use:.ppx
function ppx++(){ .ppx "$@" -m sonar-deep-research ; }

# # .ppx USER_MESSAGE -m,--model {sonar-pro,sonar-reasoning-pro,sonar-deep-research} [-re,--reasoning-effort {low,medium,high=medium}] [-sm,--search-mode {web,academic=web}] [--after DATE=1/1/1900] [--before DATE=today] [-ss,--search-size {low,medium,high=high}] [--no-md]
# https://docs.perplexity.ai/api-reference/chat-completions-post
# - --after and --before: '3/1/2025', 'March 1, 2025'
function .ppx(){
	local user_message
	local model  # sonar-pro, sonar-reasoning-pro, sonar-deep-research
	local reasoning_effort=medium
	local search_mode=web
	local search_size=high
	local after='1/1/1900'
	local before='today'
	local markdown_viewer=true
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--no-md) markdown_viewer=false ;;
			
			-m|--model) model="$2" ; shift ;;
			-m=*|--model=*) model="${1#*=}" ;;
			
			-re|--reasoning-effort) reasoning_effort="$2" ; shift ;;
			-re=*|--reasoning-effort=*) reasoning_effort="${1#*=}" ;;
			
			-sm|--search-mode) search_mode="$2" ; shift ;;
			-sm=*|--search-mode=*) search_mode="${1#*=}" ;;
			
			-ss|--search-size) search_size="$2" ; shift ;;
			-ss=*|--search-size=*) search_size="${1#*=}" ;;
			
			--after) after="$2" ; shift ;;
			--after=*|--after=*) after="${1#*=}" ;;
			
			--before) before="$2" ; shift ;;
			--before=*|--before=*) before="${1#*=}" ;;
			
			*) [[ -n "$user_message" ]] && {
				log.error "User message already provided: $user_message"
				docstring -p "$0"
				return 1
			}
			user_message="$(jq -Rs <<< "$1")" ;;
		esac
		shift
	done
	[[ -z "$model" ]] && {
		log.error "Model not provided"
		docstring -p "$0"
		return 1
	}
	[[ -z "$user_message" ]] && {
		log.error "User message not provided"
		docstring -p "$0"
		return 1
	}
	local temp_response_file="$(mktemp)"
	local temp_raw_response_file="$(mktemp)"
	local temp_usage_file="$(mktemp)"
	local temp_raw_jsonlines_file="$(mktemp)"
	local temp_citations_file="$(mktemp)"
	local temp_search_results_file="$(mktemp)"
	log.debug "$(typeset model temp_response_file temp_raw_response_file temp_usage_file temp_citations_file temp_search_results_file temp_raw_metadata_file)"
	local -i http_exit_code=0
	local base_url='https://api.perplexity.ai/chat/completions'
	# | tee >(jq -r '.usage.num_search_queries // empty' 2>/dev/null | grep -v '^$' | head -1 > "$temp_usage_file") \
	# >(jq -r 'if .citations then (.citations | map("- " + .) | join("\n")) else empty end' 2>/dev/null | grep -v '^$' | head -1 > "$temp_citations_file") \
	# >(jq -r 'if .search_results then (.search_results | map("- [" + .title + "](" + .url + ")" + (if .date then " (" + .date + ")" else "" end)) | join("\n")) else empty end' 2>/dev/null | grep -v '^$' | head -1 > "$temp_search_results_file") \
	# Available param: search_recency_filter, search_domain_filter, return_related_questions, use_openrouter
	http --ignore-stdin --json --body --check-status --stream POST "$base_url" \
		accept:application/json \
		content-type:application/json \
		"Authorization:Bearer $(<~/.perplexity-api-key)" \
		stream=true \
		include_reasoning=true \
		reasoning_effort="${reasoning_effort}" \
		search_mode="${search_mode}" \
		search_size="${search_size}" \
		after="${after}" \
		before="${before}" \
		max_tokens=16000 \
		temperature=0 \
		model="${model}" \
		'messages[0][role]=user' \
		"messages[0][content]='${user_message}'" 2>/dev/null \
		| tee "$temp_raw_response_file" \
		| sed 's/^data: //g' \
		| tee "$temp_raw_jsonlines_file" \
		| jq -r '.choices[0].delta.content' --join-output --unbuffered \
		| tee "$temp_response_file"
	http_exit_code=${pipestatus[1]}
	if [[ "$http_exit_code" != 0 ]]; then
		log.error "POST request to $base_url failed with exit code ${http_exit_code}. Raw response file: ${temp_raw_response_file}. Response file: ${temp_response_file}. Printing raw response file:"
		cat "$temp_raw_response_file"
		log.error "Exiting ${http_exit_code}"
		return $http_exit_code
	fi
	
	# Extract and display additional metadata after streaming completes
	local metadata_output=""
	local last_chunk="$(jq -r --slurp '.[-1]' "$temp_raw_jsonlines_file")"
	jq -r '.usage.num_search_queries // empty' <<< "$last_chunk" > "$temp_usage_file"
	jq -r 'if .citations then (.citations | map("- " + .) | join("\n")) else empty end' <<< "$last_chunk" > "$temp_citations_file"
	jq -r 'if .search_results then (.search_results | map("- [" + .title + "](" + .url + ")" + (if .date then " (" + .date + ")" else "" end)) | join("\n")) else empty end' <<< "$last_chunk" > "$temp_search_results_file"
	
	# Read metadata from temp files
	local num_search_queries
	[[ -s "$temp_usage_file" ]] && num_search_queries="$(<"$temp_usage_file")"
	
	local citations
	[[ -s "$temp_citations_file" ]] && citations="$(<"$temp_citations_file")"
	
	local search_results
	[[ -s "$temp_search_results_file" ]] && search_results="$(<"$temp_search_results_file")"
	
	# Build metadata output
	if [[ -n "$num_search_queries" ]]; then
		metadata_output+="## Search Queries\nUsed $num_search_queries search queries\n\n"
	fi
	
	if [[ -n "$citations" ]]; then
		metadata_output+="## Citations\n$citations\n\n"
	fi
	
	if [[ -n "$search_results" ]]; then
		metadata_output+="## Search Results\n$search_results\n\n"
	fi
	
	if [[ -n "$metadata_output" ]]; then
		echo -e "\n\n$metadata_output" >> "$temp_response_file"
	fi
	
	# Display main content
	if $markdown_viewer; then
		# Clear the screen
		echo -n $'\e[2J'
		richmd "$temp_response_file" -i python
	else
		cat "$temp_response_file"
	fi
	
	# Clean up temporary files
	rm -f "$temp_usage_file" "$temp_citations_file" "$temp_search_results_file"
}

alias claudeai='(){ llm "$@" -m claude ; }'
alias claude+='(){ llm "$@" -m claude+ ; }'  # Should probably be '-m cluade' with '-o thinking true -o thinking_budget ...'

alias geminiai='(){ llm "$@" -m gemini ; }'
alias flashlite='(){ llm "$@" -m flashlite ; }'
alias flash='(){ llm "$@" -m flash ; }'
alias 'flash+'='(){ llm "$@" -m @flash -o thinking_budget 8000 ; }'

# # grok [llm options...]
# Uses the `grok` model.
# Also provides convenience CLI (short and long options) for the following grok-unique API options:
# "search_mode": "off",
# "max_search_results": "20",
# "search_from_date": "1900-01-01",
# "search_to_date": "2027-01-01",
# "return_citations": true,
# "search_sources": [
# 		"web",
# 		"x"
# ]
function grok(){
	local search_mode=off
	local max_search_results=undefined
	local search_from_date=undefined
	local search_to_date=undefined
	local return_citations=undefined
	local search_sources=undefined
	while [[ $# -gt 0 ]]; do
		case "$1" in
			-sm|--search-mode) search_mode="$2" ; shift ;;
			-sm=*|--search-mode=*) search_mode="${1#*=}" ;;
			-mr|--max-search-results) max_search_results="$2" ; shift ;;
			-mr=*|--max-search-results=*) max_search_results="${1#*=}" ;;
			--from) search_from_date="$2" ; shift ;;
			--from=*) search_from_date="${1#*=}" ;;
			--to) search_to_date="$2" ; shift ;;
			--to=*) search_to_date="${1#*=}" ;;
			--citations) return_citations="$2" ; shift ;;
			--citations=*) return_citations="${1#*=}" ;;
			--sources) search_sources=($2) ; shift ;;
			--sources=*) search_sources=(${1#*=}) ;;
		esac
		shift
	done
	# If any of the options are not undefined, turn on search_mode
	local -U options=($max_search_results $search_from_date $search_to_date $return_citations $search_sources)
	
	
	[[ "$max_search_results" == "undefined" ]] && max_search_results=20
	[[ "$search_from_date" == "undefined" ]] && search_from_date=1900-01-01
	[[ "$search_to_date" == "undefined" ]] && search_to_date=2027-01-01
	[[ "$return_citations" == "undefined" ]] && return_citations=true
	[[ "$search_sources" == "undefined" ]] && search_sources=(web x)
	llm "$@" -m grok \
		-o search_mode "$search_mode" \
		-o max_search_results "$max_search_results" \
		-o search_from_date "$search_from_date" \
		-o search_to_date "$search_to_date" \
		-o return_citations "$return_citations" \
		-o search_sources "$search_sources" \
		"$@"
}

alias '5'='(){ llm "$@" -m gpt-5 ; }'
alias '5m'='(){ llm "$@" -m gpt-5-mini ; }'
alias '5n'='(){ llm "$@" -m gpt-5-nano ; }'

alias o1='(){ llm "$@" -m o1 ; }'
alias o1pro='(){ llm "$@" -m o1pro ; }'

alias o3='(){ llm "$@" -m o3 ; }'
alias o3m='(){ llm "$@" -m o3m ; }'

alias o4m='(){ llm "$@" -m o4m ; }'


# endregion [-------- Templates --------]

# region --------[ Internal Functions ]--------

# # llm-template <TEMPLATE_NAME_OR_PATH[.yml|yaml|md|txt]_OR_PROMPT> [-r, --raw]
# Searches for (with .llm-template) then prints the content of the template. Interpolates variables.
# If -r or --raw is provided, the content of the template file is printed as is.
# Otherwise, if there is only one key in the template yaml, the value of that key is printed.
# If there are multiple keys, the entire content of the template file is printed.
# ## Examples:
# ```bash
# $ llm-template has-single-key
# You are a helpful assistant...
# $ llm-template /path/to/has-multiple-keys.yaml
# system: You are a helpful assistant...
# prompt: Do this and that...
# $ llm-template "Bla bla actual user prompt"
# Bla bla actual user prompt
# ```
function llm-template(){
	# -- Get Template Content
	local template_name 
	local raw=false
	while [[ $# -gt 0 ]]; do
		case "$1" in
		-r|--raw) raw=true ;;
		*) [[ -n "$template_name" ]] && {
			log.error "Template name already provided: $template_name"
			docstring -p "$0"
			return 1
		}
		template_name="$1" ;;
		esac
		shift
	done
	
	template_content="$(.llm-template "$template_name")"
	[[ $? -ne 0 || -z "$template_content" ]] && {
		log.error "Failed to read content of template '$template_name'"
		return 1
	}
  
  	# -- Interpolate variables
	.llm-interpolate-template-variables "$template_content"
}

# # .llm-template <TEMPLATE_NAME_OR_PATH[.yml|yaml|md|txt]_OR_PROMPT>
# Searches for (with .llm-template-path) then prints the content of the template, no variable interpolation.
# Yaml files with multiple keys are printed as-is.
# In yaml files with a single key, the only value is printed.
function .llm-template(){
	local template_name="$1"
	local template_path
	[[ -z "$template_name" ]] && {
		log.error "No template name provided"
		docstring -p "$0"
		return 1
	}

	if ! template_path="$(.llm-template-path "$template_name" 2>/dev/null)"; then
		# Template NAME is not empty, so I guess it's the prompt itself 🤷
		# Other functions rely on this idempotency.
		print -- "$template_name"
		return 0
	fi
	
	local template_content
	if [[ "$template_path" =~ \.ya?ml$ ]]; then
		# If there is only one key, return the value of that key. Otherwise, return the entire file content.
		yq --no-colors 'select(keys | length > 1) // .[keys[0]] | .' "$template_path"
	else
		cat "$template_path"
	fi
	return 0
}

# # .llm-template-path <TEMPLATE_NAME_OR_PATH[.yml|yaml|md|txt]>
# Given a template stem, name or path, with or without any of the supported extensions,
#  performs a recursive search in the templates directory and prints the full path of the matching template file.
# Example:
# ❯ .llm-template-path detect-duplication  # /path/to/templates/code/detect-duplication.yaml
function .llm-template-path(){
	[[ -f "$1" ]] && {
		print -- "$1"
		return 0
	}
	setopt localoptions extendedglob
	local -aU files
	local file
	# files=( **/"$1" **/"$1".(|yml|yaml|md|txt) )
	local templates_path="$(llm-templates-path)"
	files=( "$1"(|.(yml|yaml|md|txt))(N) )
	[[ "$templates_path" != "$PWD" ]] && files+=( "$templates_path"/**/"$1"(|.(yml|yaml|md|txt))(N) )
	case "${#files[@]}" in
		0)
			log.error "No template found for given arg: $1"
			return 1
		;;
		1)
			print -- "${files[1]}"
			return 0
		;;
		*)
			log.error "More than one template matches given arg: ${(j., .)files[@]}"
			return 1
		;;
	esac
}

# # .llm-merge-templates <TEMPLATE_NAME_OR_PATH_1> <TEMPLATE_NAME_OR_PATH_2>
# Merges two LLM template YAML files and returns the name of the template (file stem), for consumption via `llm -t <template_name>`.
# The merged file is self-deleted after 10 seconds.
# Currently assumes:
# - The provided yaml files have different keys (e.g. `system` and `prompt`)
function .llm-merge-templates(){
	setopt localoptions errreturn
	local template_1_full_path="$(.llm-template-path "$1")"
	local template_2_full_path="$(.llm-template-path "$2")"
	local templates_path="$(llm-templates-path)"
	# shellcheck disable=SC2301  # Command subst is ok here.
	local tmp_template_name="${"$(mktemp --dry-run)":t}"
	local tmp_template_file="${templates_path}/${tmp_template_name}.yaml"
	yq eval-all "select(fileIndex == 0) * select(fileIndex == 1)" "$template_1_full_path" "$template_2_full_path" > "${tmp_template_file}"
	print -- "${tmp_template_name}"

	# Launch cleanup in background
	realasync " 
		sleep 10
		rm '${tmp_template_file}'
		if [[ -f '${tmp_template_file}' ]]; then 
			notif.error 'Failed to delete temporary file ${tmp_template_file}'
		else
			notif.success 'Deleted temporary file ${tmp_template_file}'
		fi
	"
}

# # .llm-interpolate-template-variables <TEMPLATE_NAME_OR_PATH[.yaml]_OR_PROMPT_OR_VAR>
# Interpolates variables in a given template file or prompt.
# Returns the interpolated prompt as a string.
# Currently assumes:
# - variables have a period for ${file.key}.
# - `file` findable by `llm-template`.
# Examples:
# ```bash
# .llm-interpolate-template-variables pycmd
# 'You are PythonAssistant.'
# 
# .llm-interpolate-template-variables assistants/zshai
# 'You are ZshAssistant.'
# 
# .llm-interpolate-template-variables '${.zsh_base.role-definition}'
# 'You are ZshAssistant.'
# 
# .llm-interpolate-template-variables '${.zsh_base}'  # ✘
# 
# .llm-interpolate-template-variables compress-history
# 'Please compress a lengthy, ...'
# 
# .llm-interpolate-template-variables text/compress-history.md
# 'Please compress a lengthy, ...'
# ```
function .llm-interpolate-template-variables(){
	local template_prompt="$(.llm-template "$1")"
	
	# # .extract_vars <string>
	# Prints space-separated ${file1.key} ${file2} ...
	function .extract_vars() {
		local _input="$1"
		local _remaining="$_input"
		while [[ "$_remaining" =~ '\$\{([^}]*)\}' ]]; do
			print -- "$match[1]"
			_remaining="${_remaining#*\}}"
		done
	}
	local -a template_vars=($(.extract_vars "$template_prompt"))
	
	# # .read_var <var_string>
	# Given a var like ${file.key}, returns the value of the $key in $file.
	function .read_var() {
		local _var="$1"
		local _file_name="${_var%.*}"  # .zsh_base
		local _file_path="$(.llm-template-path "$_file_name")"  # .../.zsh_base.yaml
		local _key="${_var##*.}"  # role-definition
		local _interpolated_value=$(yq -r ".$_key" "$_file_path" 2>/dev/null)  # You are ZshAssistant.
		[[ $_interpolated_value == "null" ]] && return 1
		print -- "$_interpolated_value"
	}
	local var_value
	for var in ${template_vars[@]}; do
		var_value="$(.read_var "$var")"
		[[ $? -ne 0 || -z "$var_value" ]] && {
			log.error "Unable to find value for variable $var"
			return 1
		}
		template_prompt="${template_prompt//\$\{${var}\}/${var_value}}"
	done
	print -- "$template_prompt"
}

# # .llm-auto-reasoning-effort <USER_MESSAGE>
# Returns either minimal, low, medium, or high.
function .llm-auto-reasoning-effort(){
	setopt localoptions errreturn
	local user_message="$(xt -q -t 'user_query' "$1")"
	local reasoning_effort
	local classifier_prompt="$(printf 'A user wants to query the LLM with the following:
%s

The user can set a reasoning_effort parameter to the API request payload. The available values are minimal, low, medium and high. Higher reasoning gives the model a better chance at tackling complex and difficult requests successfully, but takes appropriately more time. minimal is practically an instant response, up to high which can take anywhere from 30 seconds to a 1~2 minutes. What reasoning_effort value would you use for this particular user query? Only answer with the chosen value (minimal / low / medium / high), no intros, no explanations, no quotes, nothing else. Just the value in a single word.' "$user_message")"
	local classifier_response="$(command llm -m gpt-5-mini -o reasoning_effort minimal "$classifier_prompt")"
	case "$classifier_response" in
		minimal|low|medium|high) ;;
		*)
			log.warn "Invalid classifier response for reasoning effort: ${classifier_response}. Getting default value."
			classifier_response="$(command llm models options show $(command llm models default) | cut -d ' ' -f 2)" || {
				log.error "Failed to get default reasoning effort for default model. Falling back to medium."
				classifier_response="medium"
			}
			
		;;
	esac
	log.notice "Auto-picked reasoning effort: $classifier_response"
	print -- "$classifier_response"	
}
# # .llm-has-opt <ARGS...> -- <OPT_STRING [OPT_STRING...]>
# Helper function to check if any of the given options are set.
function .llm-has-opt() {
	local -a args
	local -a opt_strings
	local parse_args=true
	while [[ $# -gt 0 ]]; do
	case "$1" in
		--) parse_args=false ;;
		*) 
		if $parse_args; then
			args+=("$1")
		else
			opt_strings+=("$1")
		fi
	esac
	shift
	done
	local arg next_arg opt_string
	local -i i
	local -i args_len=${#args[@]}
	for ((i=1; i<args_len; i++)); do
		arg="${args[$i]}"
		next_arg="${args[$i+1]}"
		for opt_string in ${opt_strings[@]}; do
			.llm-opt-matches "$arg" "$next_arg" "$opt_string" && return 0
		done
	done
	return 1
}

# # .llm-opt-matches <ARG> <NEXT_ARG> <OPT_STRING>
# $ .llm-opt-matches '-o' 'temperature=2' '-o temperature'     # Returns 0
function .llm-opt-matches(){
	local arg="$1"
	local next_arg="$2"
	local opt_string="$3"
	[[ "$arg" = "$opt_string" || "$arg" = "$opt_string="* ]] && return 0
	[[ "$arg $next_arg" = "$opt_string" || "$arg $next_arg" = "$opt_string="* ]] && return 0
	[[ "$next_arg" = "$opt_string" || "$next_arg" = "$opt_string="* ]] && return 0
	return 1
}

# # .llm-extract-code-block
# Extracts a code block from the given content by the given 1-based index among the code blocks.
# If there are no code blocks in the content, the function returns 1.
# If the index argument is not specified, only if there is a single code block in the content, this content is printed and the function returns 0. If there is more than one code block, or no blocks, the function returns 1.
function .llm-extract-code-block(){
	[[ -z "$1" ]] && { log.error "Markdown text not provided."; return 1; }
	local markdown_text="$1"
	local index_arg="$2"

	local -a fence_indices
	fence_indices=($(print -r -- "$markdown_text" | awk '/^```/ {print NR}'))

	local -i num_fences=${#fence_indices[@]}
	local -i num_blocks=$((num_fences / 2))
	local -i target_block_index

	if (( num_blocks == 0 )); then
		if [[ -z "$index_arg" ]]; then
			log.error "No code blocks found in the input."
		else
			log.error "No code blocks found. Cannot extract block at index $index_arg."
		fi
		return 1
	fi

	# At this point, num_blocks >= 1
	if [[ -z "$index_arg" ]]; then
		if (( num_blocks == 1 )); then
			target_block_index=1
		else
			log.error "Ambiguous: $num_blocks code blocks found. Please specify an index."
			return 1
		fi
	else
		if ! [[ "$index_arg" =~ ^[1-9][0-9]*$ ]]; then
			log.error "Index must be a positive integer. Got: '$index_arg'"
			return 1
		fi
		local -i requested_index=$((index_arg))

		# num_blocks is guaranteed to be > 0 here, so no need to check that again.
		if (( requested_index > num_blocks )); then
			log.error "Index $requested_index is out of bounds. Only $num_blocks code block(s) found."
			return 1
		fi
		target_block_index=$requested_index
	fi

	# Calculate 1-based line numbers for the content of the target block
	local -i opener_fence_line_nr=${fence_indices[$(( (target_block_index - 1) * 2 + 1 ))]}
	local -i closer_fence_line_nr=${fence_indices[$(( target_block_index * 2 ))]}

	local -i content_start_line_nr=$((opener_fence_line_nr + 1))
	local -i content_end_line_nr=$((closer_fence_line_nr - 1))
	local block_content=""

	if (( content_start_line_nr <= content_end_line_nr )); then
		block_content=$(print -r -- "$markdown_text" | awk -v start="$content_start_line_nr" -v end="$content_end_line_nr" '
			NR >= start && NR <= end {
				if (NR == start) {
					printf "%s", $0;
				} else {
					printf "\n%s", $0;
				}
			}
			# No END block needed as printf handles accumulation implicitly with no trailing newline unless content exists
		')
	fi

	print -r -- "$block_content"
	return 0
}


# # .llm-xml-wrap <CONTENT,STDIN,FILEPATH> [-t,--tag,-st,--stdin-tag TAG] [-q,--quiet]
# Prepends "Given the following" to the return value of `xt "$@"`
function .llm-xml-wrap() {
	local content
	local tag
	local -a original_args=("$@")
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--tag=*|--stdin-tag=*) tag="${1#*=}" ;;
			-t|--tag|-st|--stdin-tag) tag="$2" ; shift ;;
			-*) : ;;
			*) content="$1" ;;
		esac
		shift
	done
	local tagged_content formatted_content
	if [[ "$tag" ]]; then
	  tagged_content="$(xt "${original_args[@]}")"
	  local tag_space_separated="${tag//_/ }"
	  local tag_underscores_separated="${tag// /_}"
 	  formatted_content="$(printf "Given the following %s:\n\n%s" "${tag_space_separated}" "${tagged_content}")"
	else
 	  formatted_content="$(printf "Given the following:\n\n%s" "$content")"
	fi
	print -r -- "$formatted_content"
}

typeset -a UNINTERESTING_MODELS=(
	 '(OpenAI Chat: |OpenAI: openai/)(o1|o3|o4)'
	 '(OpenAI Chat: |OpenAI: openai/|OpenAI Completion: )(chatgpt-4o|gpt-(3|4))'
	 'Anthropic Messages: anthropic/claude.(2|3)'
	 'Anthropic Messages: anthropic/claude.sonnet.4.0'
	 'Anthropic: claude-instant-1'
	 'Anthropic: claude.2'
	 'GeminiPro: gemini/gemini-(1|2.0|pro)'
	 'GeminiPro: gemini/gemini-exp-(1114|1121|1206)'
	 # Old gemini versions:
	 'GeminiPro: gemini/gemini-2.5-flash-preview-(04-17|05-20)'
	 'GeminiPro: gemini/gemini-2.5-pro-.+(03-25|05-06|06-05)'
	 
	 
	 '(Grok: |xAI: xAI(completion)?/)grok-(2|3)'
	 'nothingi+sreal'
	 'sonar$'
	 01-ai
	 aetherwiing
	 agentica-org
	 ai21
	 aion-labs
	 all-hands
	 allenai
	 alpindale
	 amazon
	 anthracite-org
	 arcee-ai
	 arliai
	 bytedance-research
	 cognitivecomputations
	 cohere
	 deepseek-chat
	 distill
	 eleutherai
	 embedding
	 eva-unit-01
	 featherless
	 gemini/gemma
	 gryphe
	 huggingface
	 inception
	 infermatic
	 inflection
	 jondurbin
	 learnlm
	 liquid
	 llama
	 mai-ds-r1
	 mancer
	 minimax
	 mistral
	 moonshotai
	 neversleep
	 nousresearch
	 open-r1
	 openchat
	 opengvlab
	 openrouter/auto
	 openrouter/x-ai/grok-beta
	 openrouter/x-ai/grok-vision-beta
	 palm
	 phi
	 pygmalionai
	 quasar
	 qwen
	 raifle
	 rekaai
	 sao10k
	 sarvamai
	 sophosympatheia
	 steelskull
	 teknium
	 thedrummer
	 thudm
	 tngtech
	 undi95
	 wizard
	 xwin-lm
)

# # .llm-models-filter-interesting
# Filter the output of `llm models list` to show only interesting models (March 14, 2025)
function .llm-models-filter-interesting() {
	sed 's/ ([^)]*)//g' \
	| command grep -E -v -i "${UNINTERESTING_MODELS[@]/#/-e}" \
	| awk '{print $NF}' \
	| sort -u
}

# endregion [-------- Internal Functions --------]
# region [-------- OpenRouter --------]

# # openrouter USER_MESSAGE [-m, --model MODEL[:price,latency,throughput]] [-o,--option OPTION=VALUE...] [--md]
# Curls OpenRouter API to generate a response to the given user message.
# `openrouter 'Hello' -m openai/gpt-4o:latency -o temperature 0 -o online=true`
# curl https://openrouter.ai/api/v1/models/google/gemini-2.0-flash-001/endpoints
function openrouter(){
	local user_message model
	local -A options
	local markdown_viewer=false
	while [[ $# -gt 0 ]]; do
	  case "$1" in
		--model=*) model="${1#*=#openrouter/}" ;;
		-m|--model) model="${2#openrouter/}" ; shift ;;
		--md) markdown_viewer=true ;;
		-o|--option) 
			case "$2" in
				*=*) 
					local option_name="${2%=*}"
					local option_value="${2#*=}"
					options[$option_name]="$option_value"
					shift
				;;
				*)  local option_name="$2"
					local option_value="$3"
					options[$option_name]="$option_value"
					shift 2
				;;
			esac
			;;
		
		*) [[ "$user_message" ]] && { log.error "Only one user message allowed." ; return 1 ; }
			user_message="$1" ;;
	  esac
	  shift
	done
	[[ "$user_message" ]] || { log.error "No user message provided." ; return 1 ; }
	
	# Add default model suffix if none is provided
	if [[ "$model" && "$model" != *":latency"* && "$model" != *":throughput"* && "$model" != *":cost"* ]]; then
	  model+=":latency"
	  log.debug "Appended default suffix :latency to model. New model: $model"
	fi
	
	local escaped_user_message="${user_message//$'\n'/\n}"
	escaped_user_message="${escaped_user_message//\"/\\\"}"
	local escaped_user_message_w_jq="$(jq -R --slurp <<< "$user_message")"
	if [[ "$escaped_user_message_w_jq" == "$escaped_user_message" ]]; then
		log.notice "Manually escaped user message is the same as jq -Rs escaped user message."
	else
		log.notice "Manually escaped user message is different from jq -Rs escaped user message."
	fi
	local payload="$(print -r -- '{
	"stream": true,
	"model": "'$model'",
	"temperature": 0,
	"max_tokens": 16000,
	"messages": [
		{
			"role": "user",
			"content": "'"$escaped_user_message"'"
		}
	]')"
	
	local option
	for option in ${(k)options[@]}; do
		payload+=",\"$option\": \"${options[$option]}\""
	done
	payload+='}'

	log.debug "$(typeset payload)"

	local temp_file="$(mktemp)"

	curl -N 'https://openrouter.ai/api/v1/chat/completions' \
		-H "Authorization: Bearer $(<~/.openrouter-api-key)" \
		-H 'Content-Type: application/json' \
		-d "$payload" 2>/dev/null \
		| sed 's/^data: //g' \
		| sed 's/^: OPENROUTER PROCESSING//g' \
		| sed 's/^\[DONE\]//g' \
		| jq -r '.choices[0].delta.content' --join-output --unbuffered \
		| tee "$temp_file"
	
	if [[ "$markdown_viewer" = true ]]; then
		# Clear the screen
		echo -n $'\e[2J'
		print_hr
		richmd "$temp_file" -i python
	else
		cat "$temp_file"
	fi
}

function .openrouter-models(){
	curl -s 'https://openrouter.ai/api/v1/models' \
		| jq -r '.data[].id' --monochrome-output \
		| sort
}


# # .openrouter-model-params [OPT...]
# Prints the non-trivial parameters for the given models.
# By default, shows only very specific models.
# Options:
# - --all (show all models instead of just interesting ones)
# ```sh
# .openrouter-model-params --all
# ```
function .openrouter-model-params(){
	local model
	local trivial_params='["frequency_penalty", "logit_bias", "logprobs", "max_tokens", "presence_penalty", "repetition_penalty", "response_format", "seed", "stop", "temperature", "top_logprobs", "top_p", "min_p", "top_k"]'
	local show_all=false
	
	local arg
	for arg in "$@"; do
		if [[ "$arg" == '--all' ]]; then
			show_all=true
			break
		fi
	done
	
	local -a models
	if [[ $show_all = true ]]; then
		models=($(.openrouter-models))
	else
		models=($(.openrouter-models | .llm-models-filter-interesting))
	fi
	
	for model in ${models[@]}; do
		log title " $model " -x -L
		cached curl -s "https://openrouter.ai/api/v1/models/$model/endpoints" \
			| jq ".data.endpoints[0].supported_parameters | sort | . - $trivial_params"
	done
}

# endregion [-------- OpenRouter --------]

# region [-------- Ollama --------]

# # ollama-chat
# Wrapper for: 
# ```
# http --stream --print=b POST http://127.0.0.1:11434/api/chat model=<MODEL> \
# messages:='[{"role": "user", "content": "<USER MESSAGE>"}]' \
# | jq -r --join-output --unbuffered '.message.content // empty'
# ```
# Escapes the user message with `jq -Rs`.
function ollama-chat()
{
	setopt localoptions pipefail errreturn
	local model
	local user_message
	local base_url='http://127.0.0.1:11434/api/chat'
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--model=*) model="${1#*=}" ;;
			-m|--model) model="$2" ; shift ;;
			*) user_message="$1" ;;
		esac
		shift
	done
	[[ "$user_message" ]] || {
		log.error "No user message provided."
		return 1
	}
	local escaped_user_message="$(jq -R --slurp <<< "$user_message")"
	http --ignore-stdin --stream --print=b --check-status POST "$base_url" \
		model="$model" \
		messages:='[{"role": "user", "content": "'"$escaped_user_message"'"}]' \
		| jq -r --join-output --unbuffered '.message.content // empty'
}



# endregion [-------- Ollama --------]

# region [-------- General Utilities --------]

# # llm-code-block [-x,--lexer LEXER] [-c,--cid CONVERSATION_ID]
# If the last conversation has a code block, prints it and copies it to the clipboard.
function llm-code-block(){
	local lexer="python"
	local conversation_id
	local -a llm_logs_list_options
	while [[ $# -gt 0 ]]; do
		case "$1" in
			(-x|--lexer) lexer="$2" ; shift ;;
			(-x=* | --lexer=*) lexer="${1#*=}"  ;;
			(--cid|--conversation) conversation_id="$2" ; shift ;;
			(--cid=* | --conversation=*) conversation_id="${1#*=}"  ;;
			(*) llm_logs_list_options+=("$1") ;;
		esac
		shift
	done
	print_hr
	log.notice "Conversation_id:" -n
	if [[ -z "$conversation_id" ]]; then
		conversation_id="$(command llm logs list -c -s | yq '.[0] | .conversation')"
	fi
	log.prompt "${conversation_id}." -n
	local last_code_block="$(command llm logs list --count=1 --conversation "${conversation_id}" --extract-last "${llm_logs_list_options[@]}" )"
	if [[ "$last_code_block" = *${conversation_id}* ]]; then
		log.prompt "No code block found in last conversation."
		return 0
	fi
	log.prompt "Last code block:"
	print_hr
	richsyntax -x "$lexer" --wrap --width "$COLUMNS" <<< "$last_code_block"
	pbcopy <<< "$last_code_block"
	notif.info "Copied last code block to clipboard ($(printf "%'d" ${#last_code_block}) chars)"
}

# # llm-search CONDITION [-r,--raw] [-c,--column {prompt,response} (Default: "prompt,response")]
# CONDITION can be `LIKE '%STRING%'`, or a plaintext string.
function llm-search(){
	local raw=false
	local column='prompt, response'
	local condition
	while [[ $# -gt 0 ]]; do
		case "$1" in
			-r|--raw) raw=true ;;
			-c|--column) column="$2" ; shift ;;
			-c=*|--column=*) column="${1#*=}" ;;
			*) condition="$1" ;;
		esac
		shift
	done
	[[ -z "$condition" ]] && {
		log.error "No condition provided."
		return 1
	}
	if [[ "$condition" != LIKE* ]]; then
		[[ "$condition" = *"'"* ]] && {
			log.warn "Condition contains single quotes. Continuing anyway."
		}
		condition="LIKE '%$condition%'"
	fi
	local logs_path="$(cached command llm logs path)"
	local where
	case "$column" in
		prompt) where="prompt $condition" ;;
		response) where="response $condition" ;;
		"prompt, "*"response") where="prompt $condition or response $condition" ;;
		*) log.error "Invalid column: $column" ; return 1 ;;
	esac
	
	local output	
	output="$(sqlite-utils "$logs_path" \
		"select id,conversation_id,model,${column} from responses where $where")" || {
		log.error "Failed to search logs."
		return 1
	}
	local -i result_count="$(jq length <<< "$output")"
	terminal-notifier -message "Found $result_count matching results."
	jq <<< "$output"
	
	
	
}


# # llm-commit-msg [TREEISH...] [--append-prompt APPEND_STRING] [--1-pass / --2-pass (default 1 pass)] [--one-by-one[=true|false] (default false)]
# Generates a commit message for the given files against HEAD.
# If no files are provided, prompts the user to confirm which files to use.
function llm-commit-msg(){
	setopt localoptions pipefail errreturn
	local -a diff_targets=()
	local prompt='Generate a short commit message. If different changes serve a cohesive purpose, mention that purpose. Make sure the commit message clearly conveys what was changed and what it was before. Do not repeat yourself; be terse and concise. Condense (compress) descriptiveness and information LOSSLESSLY; in other words, pack as much "story" into as few words as possible. Readers should be able to answer the question "What was changed?" at a glance. If the changes span a single file, start the commit message with the file name. If the changes span multiple files, start with a very short phrase, then a bullet list where each item starts with a file name. Do not use Markdown formatting nor straight single quotes. Do not say "No other changes." in the end of the commit message.'
	local two_pass=false
	local one_by_one=false
	local append_prompt=''
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--append-prompt=*) append_prompt="${1#*=}" ;;
			--append-prompt) append_prompt="$2" ; shift ;;
			--1-pass) two_pass=false ;;
			--2-pass) two_pass=true ;;
			--one-by-one) one_by_one=true ;;
			--one-by-one=*) one_by_one="${1#*=}" ;;
			*) diff_targets+=("$1") ;;
		esac
		shift
	done
	[[ -n "$append_prompt" ]] && prompt="$(printf "%s\n%s" "$prompt" "$append_prompt")"
	if [[ "${#diff_targets[@]}" = 0 ]]; then
		local -a staged_files
		local -a modified_files
		local -a untracked_files
		local -a added_files
		local -a committed_files
		local -a deleted_files
		local has_staged_files=false
		local has_modified_files=false
		local has_untracked_files=false
		local has_added_files=false
		local has_committed_files=false
		local has_deleted_files=false
		if staged_files=($(git.staged)); then
			has_staged_files=true
		fi
		if modified_files=($(git.modified)); then
			has_modified_files=true
		fi
		if untracked_files=($(git.untracked)); then
			has_untracked_files=true
		fi
		if added_files=($(git.added)); then
			has_added_files=true
		fi
		if committed_files=($(git.committed)); then
			has_committed_files=true
		fi
		if deleted_files=($(git.deleted)); then
			has_deleted_files=true
		fi
		local user_choice
		if $has_staged_files || $has_modified_files || $has_untracked_files || $has_added_files || $has_committed_files || $has_deleted_files; then
			local -a message=("No files provided and at least one of the following files exists:")
			# Remove duplicates from all files arrays
			staged_files=( "${(@u)staged_files[@]}" )
			modified_files=( "${(@u)modified_files[@]}" )
			untracked_files=( "${(@u)untracked_files[@]}" )
			added_files=( "${(@u)added_files[@]}" )
			committed_files=( "${(@u)committed_files[@]}" )
			deleted_files=( "${(@u)deleted_files[@]}" )
			
			# Build message
			$has_staged_files && message+=("Staged:\n • ${(j.\n • .)staged_files}")
			$has_modified_files && message+=("Modified:\n • ${(j.\n • .)modified_files}")
			$has_untracked_files && message+=("Untracked:\n • ${(j.\n • .)untracked_files}")
			$has_added_files && message+=("Added:\n • ${(j.\n • .)added_files}")
			$has_committed_files && message+=("Committed:\n • ${(j.\n • .)committed_files}")
			$has_deleted_files && message+=("Deleted:\n • ${(j.\n • .)deleted_files}")
			message+=("Specify which files to use in [smuacd] format or 'A' to use all.")
			user_choice="$(input "${(F)message[@]}")"
			local user_choice_individual_letter
			for user_choice_individual_letter in $user_choice; do
				case "$user_choice_individual_letter" in
					*s*) diff_targets+=(${staged_files[@]}) ;;
					*m*) diff_targets+=(${modified_files[@]}) ;;
					*u*) diff_targets+=(${untracked_files[@]}) ;;
					*a*) diff_targets+=(${added_files[@]}) ;;
					*c*) diff_targets+=(${committed_files[@]}) ;;
					*d*) diff_targets+=(${deleted_files[@]}) ;;
					*A*) diff_targets+=(${staged_files[@]} ${modified_files[@]} ${untracked_files[@]} ${added_files[@]} ${committed_files[@]} ${deleted_files[@]}) ;;
				esac
			done
		fi
		# Check if diff_targets is empty and return 1 if so
		[[ -z ${diff_targets} ]] && {
			log.error "No files provided, and there are staged, modified, untracked, added, committed, or deleted files."
			return 1
		}
		
	fi
	# Remove duplicates from diff_targets
	diff_targets=( "${(@u)diff_targets[@]}" )
	log.debug "$(typeset diff_targets)"
	
	log.info "Generating commit message for ${#diff_targets[@]} files..." -L -x
	if $one_by_one; then
		local tmp_file="$(mktemp)"
		if $two_pass; then
			llm-what-changed --2-pass --one-by-one HEAD -- "${diff_targets[@]}" | tee "$tmp_file"
		else
			llm-what-changed --1-pass --one-by-one HEAD -- "${diff_targets[@]}" | tee "$tmp_file"
		fi
		confirm "Done collecting changes for each file. Shall I aggregate them into a single commit message?" || {
			cat "$tmp_file"
			return 0
		}
		notif.info "Aggregating into a single commit message..."
		llm "$prompt" --no-format-stdin --no-md --quiet --no-clear <<< "$(cat "$tmp_file")"
	else
		if $two_pass; then
			llm-what-changed --force-prompt "$prompt" --2-pass HEAD -- "${diff_targets[@]}"
		else
			llm-what-changed --force-prompt "$prompt" --1-pass HEAD -- "${diff_targets[@]}"
		fi
	fi
	
}

# # llm-what-changed [git diff OPT...] [--force-prompt PROMPT='What has changed? Clearly, ...'] [--append-prompt APPEND_STRING] [--1-pass / --2-pass (default 1 pass)] [--dry-run] [--one-by-one[=true|false] (default false)] [-- TREEISH...]
# Asks an LLM what has changed based on a git diff context.
# By default, performs a 1-pass over the git diff context, tagging changes in a unified diff.
# If --2-pass is provided, performs a 2-pass over the git diff context, concatenating the following:
# 1. "Before vs After" of each file
# 2. Tags changes in a unified diff.
# If --one-by-one is provided, applies itself recursively to each file in the git diff context.
# The processed git diff context is passed to the LLM.
# If --dry-run is provided, prints the git diff context instead of passing it to the LLM.
function llm-what-changed(){
	log.debug "llm-what-changed: $@"
	setopt localoptions
	unsetopt errreturn errexit  # --one-by-one is recursive, so we don't want to exit on error.
	local -a additional_git_diff_args
	local -a file_paths
	local -a original_args_without_file_paths=("${(@)@}")
	
	local prompt='What has changed? Clearly, directly and shortly describe what was before and what is now. Ignore whitespace and formatting changes unless that is the only kind of change throughout the entire diff.'
	local append_prompt=''
	local two_pass=false
	local dry_run=false
	local one_by_one=false
	local parse_file_paths=false
	local -a git_diff_opts=(
		# $(gdargs+)
		--src-prefix='[SOURCE] '
		--dst-prefix='[DESTINATION] '
		# --histogram
	)
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--force-prompt=*) prompt="${1#*=}" ;;
			--force-prompt) prompt="$2" ; shift ;;
			--append-prompt=*) append_prompt="${1#*=}" ;;
			--append-prompt) append_prompt="$2" ; shift ;;
			--1-pass) two_pass=false ;;
			--2-pass) log.warn "‘--2-pass’ is deprecated. Falling back to ‘--1-pass’." ; two_pass=false ;;
			--dry-run=*) dry_run="${1#*=}" ;;
			--dry-run) dry_run=true ;;
			--one-by-one) one_by_one=true ;;
			--one-by-one=*) one_by_one="${1#*=}" ;;
			--) parse_file_paths=true ;;
			*)
				[[ $parse_file_paths == false ]] && additional_git_diff_args+=("$1")
				[[ $parse_file_paths == true ]] && file_paths+=("$1")
			;;
		esac
		shift
	done
	[[ -n "$append_prompt" ]] && prompt="$(printf "%s\n%s" "$prompt" "$append_prompt")"
	
	if $one_by_one; then
		[[ "${#file_paths[@]}" == 0 ]] && {
			log.error "--one-by-one was provided, but no file paths were provided."
			return 1
		}
		
		# Prepare the original arguments for recursion: remove file paths and --one-by-one
		local -i dash_dash_index=${original_args_without_file_paths[(i)--]}
		(( dash_dash_index <= ${#original_args_without_file_paths} )) && \
			original_args_without_file_paths=("${(@)original_args_without_file_paths[1,$((dash_dash_index - 1))]}")
		original_args_without_file_paths=("${(@)original_args_without_file_paths:#--one-by-one*}")
		
		# This for loop is redundant given the '--.+' removal, but just making sure.
		for file_path in "${file_paths[@]}"; do
			original_args_without_file_paths=("${(@)original_args_without_file_paths:#$file_path}")
		done
		
		local -A what_changed_per_file
		local what_changed
		local file_path
		local -i fail_count=0
		notif.info "Processing ${#file_paths[@]} files..."
		for file_path in "${file_paths[@]}"; do
			what_changed="$(
				llm-what-changed \
				"${original_args_without_file_paths[@]}" \
				-- "${file_path}"
				)" 2>&1 || fail_count+=1
			what_changed_per_file["$file_path"]="${what_changed:-'No changes'}"
			print "${what_changed_per_file["$file_path"]}"
		done
		notif.info "Processed ${#file_paths[@]} files with $fail_count failures."
		return $fail_count
	fi
	
	# -- Not one by one
	# local git_diff_output
	# git_diff_output="$(git --no-pager diff "${git_diff_opts[@]}" "${additional_git_diff_args[@]}" -- "${file_paths[@]}")"
	# [[ -z "$git_diff_output" ]] && {
	# 	log.error "Git diff returned empty output."
	# 	return 1
	# }
	local context
	# local tagged_git_diff="$(git-structured-diff <<< "$git_diff_output")"
	local tagged_git_diff="$(git-structured-diff "${git_diff_opts[@]}" "${additional_git_diff_args[@]}" -- "${file_paths[@]}")"
	if $two_pass; then
		local before_and_after="$(.llm-xml-wrap -q "$(git.beforeafter 2>/dev/null)" --stdin-tag 'before and after two git commits')"
		context="$(printf "%s\n\n%s" "$before_and_after" "$tagged_git_diff")"
	else
		context="$tagged_git_diff"
	fi
	local full_prompt="$(printf "%s\n\n%s" "$context" "$(xt -q "$prompt" --tag 'user-instructions')")"
	if $dry_run; then
		print -- "$full_prompt"
	else
	    log.notice "Running llm with full prompt:"
		llm "$(print -r -- "$full_prompt")" --no-format-stdin --no-md --quiet --no-clear
	fi
}


# endregion [-------- General Utilities --------]

# # llm-setup
function llm-setup(){
	local llm_install_output
	local -i llm_install_exitcode
	local -a llm_plugins=( llm-{openai-plugin,gemini,anthropic,perplexity,jq,xai,cmd,python,cluster,fragments-github,fragments-reader,tools-quickjs,pdf-to-images,video-frames,fragments-symbex,whisper-api,fragments-youtube} )
	command llm install -U llm ${llm_plugins[@]}
}

