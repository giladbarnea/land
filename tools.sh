#!/usr/bin/env zsh

# Sourced after str.sh and before pretty.sh

if [[ "$PLATFORM" == WIN ]]; then
	source tools.win.sh
elif [[ "$OS" == Linux ]]; then
	source tools.linux.sh
else
	source tools.mac.sh
fi


#region ------------[ ruff ]------------

# # rufff <FILE> [OPTIONS] [FILES]...
function rufff(){
	local -a ruff_shared_args=()
	local -a ruff_format_args=()
	local -a ruff_check_args=()
	local print_result=false
	if is_interactive && is_piped; then
		local stdin="$(<&0)"
		if [[ -f "$stdin" ]]; then
			ruff_shared_args+=("$stdin")
		else
			# If stdin is not a file, create a temp file
			print_result=true
			local temp_file
			temp_file="$(mktemp)"
			print -- "$stdin" > "$temp_file"
			ruff_shared_args+=(--silent "$temp_file")
		fi
	fi
	# Parse arguments
	while [[ $# -gt 0 ]]; do
		case "$1" in
			# `format` and `check`: Boolean flags
			--diff|--preview|--no-preview|--respect-gitignore|--no-cache|--no-respect-gitignore|--no-force-exclude)
				ruff_shared_args+=("$1") ;;

			# `format` and `check`: Options with values
			--exclude*|--extension*|--force-exclude*|--target-version*|--line-length*|--cache-dir*|--stdin-filename)
				if [[ $1 == *=* ]]; then 
					ruff_shared_args+=("${1#*=}")
				else
					ruff_shared_args+=("$2"); shift; 
				fi ;;

			# `format`: Boolean flags
			--check)
				ruff_format_args+=("$1") ;;

			# `format`: Options with values
			--range=*)
				ruff_format_args+=("${1#*=}") ;;
			--range)
				ruff_format_args+=("$2") ; shift ;;

			# `check`: Anything else
			-*)
				ruff_check_args+=("$1") ;;
			*)
				ruff_shared_args+=("$1") ;;
		esac
		shift
	done
	local format_exitcode_is_true_problem=false format_exitcode
	log.notice "Running ruff format --preview ${ruff_shared_args[*]} ${ruff_format_args[*]}"
	uv run ruff format --preview "${ruff_shared_args[@]}" "${ruff_format_args[@]}"
	format_exitcode=$?
	[[ $format_exitcode = 2 ]] && format_exitcode_is_true_problem=true  # 2 is no such file (not sure if it's the only case)

	# `check` exitcode is useless. Check out --exit-non-zero-on-fix or --exit-non-zero-on-format
	log.notice "Running ruff check --unsafe-fixes --preview --fix ${ruff_shared_args[*]} ${ruff_check_args[*]}"
	uv run ruff check --unsafe-fixes --preview --fix "${ruff_shared_args[@]}" "${ruff_check_args[@]}"
	[[ "$print_result" = true ]] && cat "$temp_file"
	[[ "$format_exitcode_is_true_problem" = false ]]
}
#endregion ruff

#region ------------[ fd ]------------

# # fdrg [--verbose] [fd opt...] [-- rg opt...]
# Runs `rg` on each path that `fd` yielded.
# Default rg options are `--pretty --with-filename --text`.
# If `--no-filename` is passed to rg, it will replace `--with-filename`.
# `--verbose` warns about files with no matches.
function fdrg() {
	declare -a fd_args
	declare -a rg_args=(--pretty --with-filename --text)
	local parse_rg_args=false
	local verbose=false
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--verbose) verbose=true ;;
		--) parse_rg_args=true ;;
		*)
			if [[ "$parse_rg_args" = true ]]; then
				rg_args+=("$1")
				[[ "$1" == --no-filename ]] && rg_args[${rg_args[(I)--with-filename]}]=()
			else
				fd_args+=("$1")
			fi ;;
		esac
		shift
	done
	log.megatitle "[$PWD] fd_args: ${fd_args[*]} | rg_args: ${rg_args[*]}"
	local result
	local user_answer
	local file
	fd "${fd_args[@]}" | while read -r file; do
		result="$(rg "${rg_args[@]}" "$file")"
		if [[ -n "$result" && "$result" != "''" && "$result" != '""' ]]; then
			echo "$result"
		elif [[ "$verbose" = true ]]; then
			log.warn "$file │ No matches"
		fi
	done
}

# # fd.count [DEST=.]
function fd.count_files(){
	local dest
	if [ "$1" ]; then
		dest="$1"
		shift
	else
		dest=.
	fi
	local dir count spaces
	while read -r dir; do
		count=$(fd -t f -uuu . "$dir" | wc -l)
		count_len=${#count}
		spaces_num=$((8-count_len))
		spaces="$(str.repeat_char ' ' "$spaces_num")"
		printf "%s%s%s\n" "$count" "$spaces" "$dir"
	done < <(fd -t d --max-depth=1 -uu . "$dest") | sort -rh
}

# # fdbf <MIN_DEPTH> <MAX_DEPTH> [fd opt...]
# Minimum MIN_DEPTH and MAX_DEPTH is 1 (for only the specified directory).
# If -q or --quiet are specified, returns 0 on the first match.
function fdbf(){
	local -i min_depth="$1"
	local -i max_depth="$2"
	if [[ "$min_depth" -ge "$max_depth" ]]; then
		log.error "MIN_DEPTH is greater or equal to MAX_DEPTH; $(typeset min_depth) >= $(typeset max_depth)"
		docstring -p "$0"
		return 1
	fi
	if [[ "$min_depth" -lt 1 || "$max_depth" -lt 1 ]]; then
		log.error "MIN_DEPTH or MAX_DEPTH is less than 1; $(typeset min_depth max_depth)"
		docstring -p "$0"
		return 1
	fi
	shift 2 || { log.error "Not enough args"; docstring -p "$0"; return 1; }
	local -a fd_opts=("$@")
	local -i current_depth
	local quiet_specified=false
	[[ ${fd_opts[(r)--quiet]} || ${fd_opts[(r)-q]} ]] && quiet_specified=true
	local -i exitcode
	for current_depth in {$min_depth..$max_depth}; do
		fd "${fd_opts[@]}" --exact-depth="$((current_depth))"
		exitcode=$?
		if [[ "$quiet_specified" = true && "$exitcode" = 0 ]]; then
			return 0
		fi
	done
	return $exitcode
}

#endregion fd

#region ------------[ rg ]------------

if [[ -e "$HOME/.config/ripgrep.rc" ]]; then
	export RIPGREP_CONFIG_PATH="$HOME/.config/ripgrep.rc"
fi

# # rgsed <SEARCH_REGEX> [DESTINATION=.] [rg_opts...] -- <SED_REPLACE> [--no-backup] [sed_opts...]
# Confirm before sed. Backs up each file to file~ by default.
# Runs `sed -E -i s/REGEX_RG_QUERY/SED_REPLACE/g` on FILE(s) by default.
# If `FILE` is not provided, sed will be applied to all files that match `REGEX_RG_QUERY`. Program will exit immediately if a sed fails.
function rgsed(){
	local -a rg_positional_args
	local -a rg_options
	local -a sed_positional_args
	local -a sed_options=(-E -i)
	local sed_command_name
	if [[ ${commands[gsed]} ]]; then
		sed_command_name=gsed
	else
		# shellcheck disable=SC2209
		sed_command_name=sed
		sed_options+=('')
	fi
	
	# Both query and sed_replace will be populated after arg parsing, by inferring positional args
	local search_query
	local destination  # Either a file or a directory
	local sed_replace
	local backup=true
	local parse_rg_opts=true

	while (( $# )); do
		case "$1" in
			--) parse_rg_opts=false ;;
			--no-backup) backup=false ;;
			*)
				if [[ "$parse_rg_opts" = true ]]; then
					case "$1" in
						-*=*) rg_options+=("${1#*=}") ;;
						-*) rg_options+=("$1") ; shift ;;
						*) rg_positional_args+=("$1") ;;
					esac
				else  # Parse sed args.
					case "$1" in
						-*=*) sed_options+=("${1#*=}") ;;
						-*) sed_options+=("$1") ; shift ;;
						*) sed_positional_args+=("$1") ;;
					esac
				fi
			;;
		esac
		shift
	done
	
	case "${#rg_positional_args[@]}" in
		0) log.error "No search query provided"
			docstring -p "$0"
			return 1 ;;
		1) search_query="${rg_positional_args[1]}"; destination="${PWD}" ;;
		2) search_query="${rg_positional_args[1]}"; destination="${rg_positional_args[2]}" ;;
		*) log.error "Too many positional args"
			docstring -p "$0"
			return 1 ;;
	esac
	
	case "${#sed_positional_args[@]}" in
		0) log.error "No sed replace provided"
			docstring -p "$0"
			return 1 ;;
		1) sed_replace="${sed_positional_args[1]}"; ;;
		*) log.error "Too many positional args"
			docstring -p "$0"
			return 1 ;;
	esac
	
	[[ "$search_query" && "$sed_replace" ]] || { log.error "Not enough args"; docstring -p "$0"; return 1; }

	log.debug "$(typeset search_query) │ $(typeset destination) │ $(typeset rg_positional_args) │ $(typeset rg_options) │ $(typeset sed_positional_args) │ $(typeset sed_options) │ $(typeset sed_replace) │ $(typeset backup)"
	log.megatitle "Matches:" -x

	rg "${rg_positional_args[@]}" "${rg_options[@]}"
	# Normalize to array of files in both cases
	local -a target_files=( $(rg "${rg_positional_args[@]}" "${rg_options[@]}" --files-with-matches) )
	
	if [[ ${#target_files[@]} -eq 0 ]]; then
		log.success "No matches found."
		return 0
	fi
	log.debug "$(typeset target_files)"
	
	# Single prompt construction
	local prompt="Run ${Cc}${sed_command_name} ${sed_options[*]} 's/$search_query/$sed_replace/g'${Cc0} on"
	prompt+=" ${target_files[*]}?"
	[[ ! "$target_files" ]] && prompt+="\n  – ${(j:\n  · :)target_files}"

	confirm "$prompt" || return 3

	local f
	if [[ "$backup" = true ]]; then
		for f in "${target_files[@]}"; do
			if ! command cp -piv "$f" "${f}~"; then
				log.fatal "Failed backing up ${f} to ${f}~. Aborting"
				return 1
			fi
		done
	fi

	for f in "${target_files[@]}"; do
		"$sed_command_name" "${sed_options[@]}" "s/$search_query/$sed_replace/g" "$f"
	done

	local any_replacement_failed=false
	for f in "${target_files[@]}"; do
		if rg -q "$search_query" "${rg_options[@]}" "$f"; then
			log.error "Replacement failed in ${f}: pattern ${Cc}${search_query}${C0} still exists"
			any_replacement_failed=true
		fi
	done

	[[ "$any_replacement_failed" = true ]] && return 1

	if [[ "$backup" = true ]] && confirm "All replacements successful. Delete backups?"; then
		for f in "${target_files[@]}"; do
			rm -v "${f}~"
		done
	fi

	return 0
}


# # rgi [ripgrep options...]
# Interactive rg. Preview rg query with fzf.
function rgi() {
  # Check out https://github.com/phiresky/ripgrep-all/wiki/fzf-Integration
  rg --files-with-matches --no-messages "$@" | \
    fzf --ansi --preview ". fzf.sh; .fzf-preview {}" --preview-window="$FZF_PREVIEW_WINDOW_OPTS"
}

#endregion rg
#region ------------[ npm ]------------

alias npmld0='npm list --depth=0'
alias npmld1='npm list --depth=1'
alias npmld2='npm list --depth=2'

#endregion npm

#region ------------[ nvm ]------------

# # loadnvm [-y]
function loadnvm() {
	local always_yes=false
	[[ "$1" == -y ]] && always_yes=true
	if ! $always_yes && isdefined nvm && ! confirm "nvm already loaded; reload it anyway?"; then
		return 0
	fi
	if [[ ! -d "$HOME"/.nvm ]]; then
		log.error "$HOME/.nvm is not a dir"
		return 1
	fi
	export NVM_DIR="$HOME/.nvm"
	local -a base_nvm_dir_candidates=(
		/opt/homebrew/opt/nvm
		"$NVM_DIR"
	)
	local base_nvm_dir
	local loaded=false
	for base_nvm_dir in "${base_nvm_dir_candidates[@]}"; do
		if [[ -d "$base_nvm_dir" 
		&& -f "$base_nvm_dir/nvm.sh"
		]]; then
			source "$base_nvm_dir/nvm.sh"
			[[ -f "$base_nvm_dir/etc/bash_completion.d/nvm" ]] && source "$base_nvm_dir/etc/bash_completion.d/nvm"
			log.success "Loaded nvm from $base_nvm_dir"
			loaded=true
			break
		fi
	done
	if [[ "$loaded" = false ]]; then
		log.warn "nvm.sh was not found in any of the following directories: ${base_nvm_dir_candidates[*]}"
		return 1
	fi
	
	setopt localoptions nowarncreateglobal # doesn't do anything :(
	if [[ -f "./.nvmrc" ]]; then
		local nvmrc_version="$(<.nvmrc)"
		if $always_yes || confirm "Found ./.nvmrc with version ${Cc}${nvmrc_version}${Cc0}. Activate it?"; then
			nvm use "$nvmrc_version"
			return $?
		fi
	fi
	local node_versions_raw
	node_versions_raw="$(vex nvm ls --no-alias --no-colors ---log-only-errors)" || return 1
	local node_versions=( $(xargs -n1 <<< "$node_versions_raw" | command grep -Ev '^[^a-zA-Z0-9]+$') )
	log.debug "node_versions: ${node_versions[*]}"
	case "${#node_versions}" in
		0) return 0 ;;
		1)
			log.info "Activating the only node version (${node_versions})"
			nvm use "${node_versions}"
			return $? ;;
		*)
			local node_version
			node_version="$(input "Choose node version to activate:" \
														--choices "( ${node_versions[*]} )")"
			nvm use "${node_version}"
			return $? ;;
	esac
	log.warn "Did not load node version"
	return 1

}
#endregion nvm


#region ------------[ ls / eza ]------------

unalias ls 2>/dev/null
if command -v eza &>/dev/null; then
	# shellcheck disable=SC2032
	function ls() {
		local targetdir
		local -a eza_args=(
			--classify # file types (-F)
			--all      # .dot (-a)
			--header   # Permissions Size etc (-h)
			--long     # table (-l)
			--group-directories-first
			--icons
			--color-scale=all
			--color-scale-mode=gradient
		)
		local sort=name
		while [[ $# -gt 0 ]]; do
			case "$1" in
			-s | --sort*)
				if [[ "$1" == *=* ]]; then
					sort=${1#*=}
				else
					sort="$2"
					shift
				fi
				shift ;;
			-*) eza_args+=("$1"); shift ;;
			# Treat multiple positional args as a single target dir with spaces
			*) [[ "$targetdir" ]] && targetdir+=" $1" || targetdir="$1"; shift ;;
			esac
		done
		eza_args+=(--sort="$sort")
		targetdir="${targetdir:-"$PWD"}"
		if [[ -f "$targetdir" ]]; then
			local printer_cmd="$(input "File '$targetdir' is a file. Print it with" \
																--choices='[b]at [c]at [l]s its parent dir [q]uit')"
			case "$printer_cmd" in
				b) bat "$targetdir"; return $? ;;
				c) cat "$targetdir"; return $? ;;
				l) ls "$(dirname "$($(command -v grealpath || command -v realpath) "$targetdir")")"; return $? ;;
				q) return 0 ;;
			esac
		fi

		# When targetdir has space in it and is relative,
		# builtin cd complains unless explicitly prepended with ./
		[[ "$targetdir" != /* ]] && targetdir="./${targetdir}"
		if [[ -d "${targetdir}/.git" ]]; then
			eza_args+=(--git)
		fi
		local exitcode
		eza "${eza_args[@]}" "${targetdir}"
		exitcode=$?
		local targetdir_absolute="$(realpath "$targetdir")"
		local targetdir_absolute_tilda="${targetdir_absolute/#$HOME/~}"
		[[ "$exitcode" == 0 ]] && {
			# Print nice targetdir path
			print_hr 8 -n
			# If targetdir is a subdir of pwd, darken the pwd part
			if [[ "$targetdir_absolute" = "$PWD"/* ]]; then
				local targetdir_relative=$($(command -v grealpath || command -v realpath) --relative-to="$PWD" "$targetdir")
				# shellcheck disable=SC2154
				log " ${Ci}${CbrBlk}${PWD/#$HOME/~}/${Cfg0}${Cd}${targetdir_relative}${C0}" -x -n
			else
				log " ${Ci}${Cd}${targetdir_absolute_tilda}${C0}" -x -n
			fi
			print_hr $((COLUMNS - 12 - ${#targetdir_absolute_tilda}))
			return 0
		}
		return $exitcode
	}

	alias lst="ls --tree --ignore-glob='.git|.idea'"
	alias lst2='lst --level=2'
	alias lst3='lst --level=3'
else
	if [[ "$OS" == macos ]]; then
		alias ls="command ls -Flahv --color=auto"
	else
		alias ls='command ls -Flahv --group-directories-first --color=auto'
	fi
fi
#endregion ls / eza

#region ------------[ pyenv ]------------

# # loadpyenv
function loadpyenv(){
	if [[ "$PYENV_LOADED" ]]; then
		log.success "pyenv already loaded (PYENV_LOADED=$PYENV_LOADED)"
		return 0
	fi
	export PYENV_ROOT="${HOME}/.pyenv"
	if _pyenv_in_str "$PATH"; then
		log.warn "PATH already includes pyenv shims and/or pyenv bin.
		This is weird, because PYENV_LOADED is not set.
		Cleaning pyenv entries from PATH and reloading pyenv."
		export PATH="$(tr ':' $'\n' <<< "$PATH" | filter '[[ {} != *"${PYENV_ROOT}"* ]]' | tr $'\n' ':')"
	fi
	export PATH_BEFORE_PYENV="$PATH"
	export PATH="${PYENV_ROOT}/shims:${PYENV_ROOT}/bin:${PATH}"
	# PATH="$(bash --norc -ec 'IFS=:; paths=($PATH); for i in ${!paths[@]}; do if [[ ${paths[i]} == "'$HOME/.pyenv/shims'" ]]; then unset '\''paths[i]'\''; fi; done; echo "${paths[*]}"')"
	# export PATH="${PYENV_ROOT}/shims:${PATH}"
	command pyenv rehash 2>/dev/null
	export PYENV_LOADED=1
	omz plugin load pyenv 2>/dev/null
	log.success "Loaded pyenv (PYENV_ROOT=$PYENV_ROOT)"
}

# # unloadpyenv
function unloadpyenv(){
	if [[ ! "$PYENV_LOADED" ]]; then
		log.success "pyenv already unloaded (PYENV_LOADED=$PYENV_LOADED)"
		return 0
	fi
	if _pyenv_in_str "$PATH_BEFORE_PYENV" || [[ "$PATH_BEFORE_PYENV" != *:* ]]; then
		log.error "PATH_BEFORE_PYENV either has pyenv paths, or is invalid; aborting:\n${Cc}${PATH_BEFORE_PYENV}"
		return 1
	fi
	if _pyenv_in_str "$PATH"; then
		export PATH="$PATH_BEFORE_PYENV"
	else
		log.warn "PATH does NOT include pyenv shims and/or pyenv bin.
		This is weird, because PYENV_LOADED IS set.
		Skipping PATH manipulation, unsetting PYENV_LOADED and returning."
	fi
	unset PYENV_LOADED
	log.success "Unloaded pyenv"
}

# # _pyenv_in_str <colon-separated string>
function _pyenv_in_str(){
	local path_string="${1}"
	shift 1 || { log.error "$0: Not enough args (expected 1, got ${#$})"; return 2; }
	local pyenv_root="${PYENV_ROOT:-${HOME}/.pyenv}"
	[[ "$path_string" = *"${pyenv_root}/shims"* ]] && return 0
	[[ "$path_string" = *"${pyenv_root}/bin"* ]] && return 0
	return 1
}
#endregion pyenv

# region ------------[ conda ]------------
# # loadconda
function loadconda() {
  __conda_setup="$('$HOME/miniconda3/bin/conda' 'shell.zsh' 'hook' 2>/dev/null)"
  if [ $? -eq 0 ]; then
	log.prompt "evaling conda setup" -x
	eval "$__conda_setup"
	return $?
  else
	if [ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]; then
	  log.prompt "sourcing conda.sh" -x
	  # shellcheck source=/Users/gilad/miniconda3/etc/profile.d/conda.sh
	  . "$HOME/miniconda3/etc/profile.d/conda.sh"
	else
	  log.prompt "Appending $HOME/miniconda3/bin to PATH" -x
	  export PATH="$HOME/miniconda3/bin:$PATH"
	fi
  fi
  unset __conda_setup
}

#endregion conda
#region ------------[ cat ]------------

# # evalcat <FILE_PATH>
# evals the contents of `FILE_PATH`
function evalcat() {
	if [[ -z "$1" ]]; then
		log.fatal "evalcat requires 1 arg"
		docstring -p "$0"
		return 1
	fi
	if [[ ! -f "$1" ]]; then
		log.fatal "'$1' does not exist, or is not a file"
		return 1
	fi
	if [[ ! -s "$1" ]]; then
		log.fatal "'$1' exists but empty"
		return 1
	fi
	local filecontent
	filecontent="$(cat "$1")"
	local linecount
	linecount="$(echo -n \""$filecontent"\" | wc -l)"
	if ((linecount <= 40)); then

		log.debug "evaluating:"
		echo -n "$filecontent" | bat -p -l bash
	else
		log.debug "evaluating $linecount lines..."
	fi

	eval "$(echo -n "$filecontent")"
	return $?
}

# # catrange <FILE_OR_PIPE> [START] [STOP]
# `cat` a range of lines.
# Both START and STOP are inclusive, to allow printing one line e.g. `catrange <FILE> 42 42`
# ## Examples
# ```bash
# catrange init.sh 362 412
# cat init.sh | catrange 362
# catrange init.sh -500 -1
# ```
function catrange() {
	local piped filepath relstop
	local -i total_lines
	local -i start
	local -i stop
	local -i relstop

	# Check if input is piped or from a file
	if ! is_piped; then
		piped=false
		# Check if file argument is provided
		if [[ -z "$1" ]]; then
			log.fatal "catrange requires at least 1 arg (file descriptor) when not piped"
			return 1
		fi

		filepath="$1"
		start="$2"
		stop="$3"

		# Check if file exists and is readable
		if ! [[ -f "$filepath" && -r "$filepath" ]]; then
			log.fatal "'$filepath' either not a file or not readable"
			stat "$filepath" 1>&2
			return 1
		fi

		# Count total lines in the file
		total_lines=$(wc -l < "$filepath")
	else
		local value="$(<&0)"
		piped=true
		start="$1"
		stop="$2"

		# Count total lines from pipe
		total_lines=$(wc -l <<< "$value")
	fi

	# Convert negative indices to positive
	if [[ $start =~ ^-?[0-9]+$ ]]; then
		if ((start < 0)); then
			start=$((total_lines + start + 1))
		fi
	fi

	if [[ $stop =~ ^-?[0-9]+$ ]]; then
		if ((stop < 0)); then
			stop=$((total_lines + stop + 1))
		fi
	fi

	# If no start is provided, cat entire input and return
	if [[ -z $start ]]; then
		if "$piped"; then
			printf "%s" "$value"
		else
			cat "$filepath"
		fi
		return $?
	fi

	# If stop is provided, validate and calculate relstop
	if [[ $stop ]]; then
		if ((start > stop)); then
			log.fatal "start ($start) is greater than stop ($stop)"
			return 1
		fi
		relstop=$((stop - start + 1))
		if [[ $piped = true ]]; then
			tail +${start} <<< "$value" | head -${relstop}
		else
			tail +${start} "$filepath" | head -${relstop}
		fi
		return $?
	fi

	# If only start is provided, tail from that line to the end
	if [[ $piped = true ]]; then
		tail +${start} <&0
	else
		tail +${start} "$filepath"
	fi
}


# # catjumps <FILE_OR_PIPE> <CHUNK_SIZE> [-o OUT_PATH_PREFIX]
# Prints the file in chunks of CHUNK_SIZE lines.
# If OUT_PATH_PREFIX is provided, saves each chunk to $OUT_PATH_PREFIX.<chunk_number>.
function catjumps(){
	local file stdin output_path_prefix
	local -i chunk_size
	local specified_output_path=false
	if read -t 0 -u 0 stdin; then
		file="$(<&0)"
		chunk_size="$1"
		shift || { log.error "$0: Not enough args. Usage:\n$(docstring "$0")"; return 2; }
		[[ "$1" ]] && {
			output_path_prefix="$2"
			shift 2 || { log.error "$0: Wrong usage. Usage:\n$(docstring "$0")"; return 2; }
			specified_output_path=true
		}
	else
		file="$1"
		chunk_size="$2"
		shift 2 || { log.error "$0: Not enough args. Usage:\n$(docstring "$0")"; return 2; }
		[[ "$1" ]] && {
			output_path_prefix="$2"
			shift 2 || { log.error "$0: Wrong usage. Usage:\n$(docstring "$0")"; return 2; }
			specified_output_path=true
		}
	fi
	local -i total_lines=$(wc -l < "$file")
	local -i start=1
	local -i stop=$chunk_size
	local -i total_chunks=$((total_lines / chunk_size))
	local suffix_printf_template="%0${#total_chunks}d"
	local -i current_chunk=0
	local current_suffix
	while ((stop <= total_lines)); do
			if [[ "$specified_output_path" = true ]]; then
					current_suffix="$(printf "$suffix_printf_template" $current_chunk)"
					catrange "$file" $start $stop > "${output_path_prefix}.${current_suffix}"
			else
					catrange "$file" $start $stop
			fi

			start=$((stop + 1))
			stop=$((start + chunk_size - 1))
			current_chunk=$((current_chunk + 1))

	done
	# If the next stop would exceed the total lines, set it to -1 (last line)
	if ((stop > total_lines)); then
			stop=-1
	fi
	if [[ "$specified_output_path" = true ]]; then
			current_suffix="$(printf "$suffix_printf_template" $current_chunk)"
			catrange "$file" $start $stop > "${output_path_prefix}.${current_suffix}"
	else
			catrange "$file" $start $stop
	fi
}
#endregion cat
#region ------------[ sort ]------------

# # sort-by-length <STDIN> [..sort options]
function sort-by-length(){
	awk '{ print length, $0 }' | sort -n -s "$@" | cut -d" " -f2-
}
#endregion sort
#region ------------[ ssh ]------------

# ssh.pair <KEYNAME> <USER@IP> [ssh-keygen option...]
function ssh.pair(){
	local oldpwd="$PWD"
	mkdir -p "$HOME"/.ssh || { builtin cd "$oldpwd"; return 1; }
	local keyname="$(basename "${1%.*}")"
	local remote="$2"
	shift 2 || return 1
	log.debug "keyname: $keyname | remote: $remote"
	local cmds=(
		'ssh-keygen -f "$HOME"/.ssh/"${keyname}" "$@"'
		'ssh-copy-id -i "$HOME"/.ssh/"${keyname}".pub "$remote"'
	)
	runcmds "${cmds[@]}" ---confirm-once
	#	vex ssh-keygen -f "$HOME"/.ssh/"${keyname}" "$@" || return 1
	#	vex ssh-copy-id -i "$HOME"/.ssh/"${keyname}".pub "$remote" || return 1
	# return $?
}
#endregion ssh
#region ------------[ rsync ]------------
alias rsynk='rsync --progress --compress-level=9 --cvs-exclude --human-readable'
#endregion rsync
#region ------------[ shfmt ]------------
alias shfmt='command shfmt --keep-padding --simplify --language-dialect zsh --indent 2 --binary-next-line --case-indent'
#endregion shfmt

#region ------------[ bw ] -----------------

isdefined bw && {
	function bw.unlocked(){
		bw unlock --check 1>/dev/null 2>&1
	}
	# # bw.unlock
	# Unlocks the Bitwarden vault and exports a new BW_SESSION.
	# If the vault is already unlocked, it will ask for confirmation to unlock again.
	function bw.unlock(){
		bw.unlocked && {
			confirm "Vault is unlocked, unlock anyway?" || return 0
		}
		local bw_session="$(vex bw unlock --raw)" || {  # Don't redirect stderr to stdout because password prompt
			log.error "$bw_session"
			return 1;
		}
		export BW_SESSION="$bw_session"
		log.success "BW_SESSION: ${BW_SESSION:0:4}...${BW_SESSION:${#BW_SESSION}-4}"
	}

	# # bw.list-items [--folder-name <FOLDER_NAME>] [bw list item options...]
	# Passes all options to `bw list items`.
	# If --folder-name is passed, the first match of `bw list folders --search` is used as --folderid.
	# Example:
	#   bw.list-items --search openai --folder-name secrets | jq -r '.[0].fields[0].value'
	function bw.list-items(){
		bw.unlocked || bw.unlock || return 1
		local folder_name folder_id
		local list_items_args=()
		while [[ $# -gt 0 ]]; do
			case "$1" in
				--folder-name*) [[ "$1" = *=* ]] && folder_name="${1#*=}" || { folder_name="$2"; shift; } ;;
				*) list_items_args+=("$1");;
			esac
			shift
		done
		log.debug "folder_name: ${folder_name}"
		if [[ "$folder_name" ]]; then
			folder_id="$(vex bw list folders --search "$folder_name" | jq -r '.[0].id')" || return 1
			list_items_args+=("--folderid" "$folder_id")
		fi
		bw list items "${list_items_args[@]}" | jq
	}
}
#endregion bw
#region ------------[ jupyter ] ----------------

alias j=jupyter
alias jl='jupyter lab'

#endregion jupyter
#region ------------[ kubernetes ]------------

alias k=kubectl
alias kx=kubectx
alias kn=kubens

#endregion kubernetes
#region ------------[ kitty ] ---------------

alias kt-wtitle='kitty @set-window-title'
alias kt-ttitle='kitty @set-tab-title'

# # kt-launch <DIR> [@launch options...]
# kitty @launch --cwd "$(realpath "$dir")" --copy-env --title="$dir" "$@"
function kt-launch(){
	local dir="$1"
	shift 1 || { log.error "$0: Not enough args (expected 1, got ${#$}). Usage:\n$(docstring "$0")"; return 2; }
	kitty @launch --cwd "$(realpath "$dir")" --copy-env --title="$dir" "$@"
}

# # kt-launchtab <DIR> [@launch options...]
function kt-launchtab(){
	kt-launch "$@" --type=tab
}

# # kt-launchwin <DIR> [@launch options...]
function kt-launchwin(){
	kt-launch "$@" --type=window
}

function kt-ls(){
	if is_piping; then
		kitty @ls "${@}"
	else
		kitty @ls "${@}" | richjson --indent-guides --line-numbers -w "$COLUMNS"
	fi
}

function kt-ls-min(){
	# [ 
	#	App {[
	#		Tab {[
	#			Window {[ ]}
	#		]}
	#	]}
	# ]
	# ---
	# App:    id, title
	# Tab:    id, title
	# Window: env_PWD, id, is_self, last_reported_cmdline, pid, title
	local pager_command
	local kitty_apps_mapping='id, title'
	local tabs_mapping='tabs: [.tabs[] | {id, title}]'
	local windows_mapping='windows: [.tabs[].windows[] | {env_PWD: .env.PWD, id, is_self, last_reported_cmdline, pid, title}]'
	local jq_map_expression="map({$kitty_apps_mapping, $tabs_mapping, $windows_mapping})"
	is_piping && 
		kitty @ls "${@}" \
		| jq "$jq_map_expression"
	
	is_piping || 
		kitty @ls "${@}" \
		| jq "$jq_map_expression" \
		| richjson --indent-guides --line-numbers -w $COLUMNS
}

# # kt-windows-min
function kt-windows-min(){
	local windows
	windows="$(kitty @ls | jq '.[0].tabs | map(.windows[]) | map({id, title, cwd, pid, last_reported_cmdline})' --monochrome-output)"
	is_piping && echo "$windows"
	is_piping || richjson --indent-guides --line-numbers -w $COLUMNS <<< "$windows"
}

# # kt-last <kitty @ get-text options...>
# Can specify e.g. -m neighbor:top
function kt-last(){
	kitty @ get-text --extent=last_non_empty_output "$@"
}



#endregion kitty

# region ------------[ uv ] ---------------

# # uv.syncall [uv sync options...]
# Wrapper for `uv sync`.
function uv.syncall(){
	local all_groups
	all_groups="$(yq -r '.["dependency-groups"] | keys[]' pyproject.toml | xargs -I '{}' echo --group='{}' | xargs)" || return $?
	confirm "Run ${Cc}uv sync $all_groups $*${C0}?" || return 1
	# shellcheck disable=SC2086  # (Quote)
	vex uv sync $all_groups "$@" ---log-before-running
}

function uvr() { uv run "$@"; }
function uvpy() { uv run python "$@"; }
function uvpt() { uv run pytest "$@"; }

#endregion uv
# region ----------[ to.py ] ---------------

# function __to(){
# 	# If the first argument is either 'convert' or 'diff', invoke to.py with unmodified arguments:
# 	if [[ "$1" == convert || "$1" == diff ]]; then
# 		python3.10 "${SCRIPTS}"/to.py "$@"
# 		return $?
# 	fi
#
# 	# If there are not arguments at all, or any of the arguments (no matter its position) is '-h' or '--help', invoke to.py with unmodified arguments:
# 	if [[ ! "$1" || "$*" == *-h* || "$*" == *--help* ]]; then
# 		python3.10 "${SCRIPTS}"/to.py "$@"
# 		return $?
# 	fi
#
# 	# Arguments were specificied but not 'convert' or 'diff', so we implicitly call 'convert':
# 	python3.10 "${SCRIPTS}"/to.py convert "$@"
# 	return $?
# }

#endregion
# -----------------------------

# # wget.recursive
# wget.recursive <URL> [wget options...]
# Specifying --domains=DOMAIN is recommended.
function wget.recursive(){
	local url domain
	url="$1"
	shift 1 || { log.error "$0: Not enough args (expected 1, got ${#$}). Usage:\n$(docstring -p "$0")"; return 2; }
	# Remove all the optional prefixes: https?://, www., and remove everything after (and including) the first slash
	domain="${url#http://}"
	domain="${domain#https://}"
	domain="${domain#www.}"
	domain="${domain%%/*}"
	# assert that there is exactly a single period in the domain, and text to its left and to its right
	# split domain into an array by periods
	local domain_parts=(${(s/./)domain})
	if [[ ${#domain_parts[@]} -ne 2 ]]; then
		log.error "Domain is not a valid domain: $domain"
		return 1
	fi
	wget --recursive --page-requisites --html-extension --convert-links --span-hosts --ignore-tags=img --domains="$domain" "$url" "$@"
}

# -----------------------------

# region ------------[ Exa ] ---------------

# # exa <QUERY> [-t,--type auto|fast|neural=fast] [-c,--category company|'research paper'|'news article'|pdf|github|'personal site'|'linkedin profile'|'financial report'=none] [-n,--numResults 1-100=20]
function exa(){
	local query type=fast category numResults=20
	while [[ $# -gt 0 ]]; do
	  case "$1" in
		--type=*) type="${1#*=}" ;;
		-t|--type) type="$2" ; shift ;;
		--category=*) category="${1#*=}" ;;
		-c|--category) category="$2" ; shift ;;
		--num=*) numResults="${1#*=}" ;;
		-n|--num) numResults="$2" ; shift ;;
		*) [[ "$query" ]] && { log.error "$0: Too many args (expected 1, got ${#$}). Usage:\n$(docstring -p "$0")"; return 2; }; query="$1" ;;
	  esac
	  shift
	done
	[[ "$query" ]] || { log.error "$0: Not enough args (expected 1, got ${#$}). Usage:\n$(docstring -p "$0")"; return 2; }
	local data_string='{
		"query": "'"$query"'",
		"type": "'"$type"'",
		"numResults": '"$numResults"''
	[[ "$category" ]] && data_string+=',"category": "'"$category"'"'
	data_string+='}'
	log.debug "data_string: $(jq --compact-output <<< "$data_string")"
	curl -X POST --silent https://api.exa.ai/search \
	--header "content-type: application/json" \
	--header "x-api-key: $(<~/.exa-api-key)" \
	--data "$data_string" \
	| yq 'del(.requestId, .searchTime, .costDollars.search)' --prettyPrint
}