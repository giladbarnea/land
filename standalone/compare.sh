#!/usr/bin/env zsh

diff_quiet(){
	local path1="$1"
	local path2="$2"
	shift 2 || return 2
	diff -q "$path1" "$path2" "$@" >/dev/null 2>&1
}

file_has_text(){
	local filepath="$1"
	shift 1 || return 2
	rg --quiet "\S" "$filepath"
}

dir_is_empty(){
	local dir="$1"
	shift 1 || return 2
	[[ -z "$(command ls -A "$dir")" ]]
}

dir_size_bytes(){
	local dir1="$1"
	shift 1 || return 2
  command du -sk "${dir1}" | cut -d $'\t' -f 1
}

# # duplicate_files_with_different_names <DIR_1> <DIR_2> [fd options... (not -u* or -t *)]
function duplicate_files_with_different_names(){
	function duplicate_files_with_different_names.setup_results_file(){
		if [[ -e ./.duplicate_files_with_different_names ]]; then
			local answer
			answer="$(input "$PWD/.duplicate_files_with_different_names exists." \
									--choices='[l]oad as cache, [o]verwrite or do [n]othing?')"
			local line
			case "$answer" in
				l)
					log.info "Loading $PWD/.duplicate_files_with_different_names" -x -L
					while read -r line; do
						if [[ -n "$line" ]] && ! str.is_whitespace "$line"; then
							seen_duplicates+=( "$line" )
						fi
					done <<< "$(tail +3 ./.duplicate_files_with_different_names)"
					write_seen_duplicates=true ;;
				o) cat > ./.duplicate_files_with_different_names <<-EOF
						$dir1 | $dir2
						───────────────────────────────────────────────────────────────────────────────────────────

						EOF
					write_seen_duplicates=true
					log.info "Writing to $PWD/.duplicate_files_with_different_names" -x -L ;;
				n) write_seen_duplicates=false ;;
			esac
		else
			cat > ./.duplicate_files_with_different_names <<-EOF
			$dir1 | $dir2
			───────────────────────────────────────────────────────────────────────────────────────────

			EOF
			write_seen_duplicates=true
			log.info "Writing to $PWD/.duplicate_files_with_different_names" -x -L
		fi
	}
	local dir1=$1
	local dir2=$2
	shift 2 || { log.error "$0: Not enough args (expected at least 2, got ${#$}. Usage:\n$(docstring "$0")"; return 2; }
	log.title "Finding duplicate files with different names in '$dir1' and '$dir2'" -x
	local f1 f1_bname f1_relpath f1_bytes f1_bytes_human f1_printed=false
	local f2 f2_bname f2_relpath f2_bytes
	local fd_args=(-uu -t f --absolute-path "$@" -E .git -E .idea -E .vscode -E .run -E .env -E .venv -E __pycache__ -E .ipynb_checkpoints)
	declare -A dir1_file_sizes=()
	declare -A dir2_file_sizes=()

	# * .duplicate_files_with_different_names
	local seen_duplicates=()
	local write_seen_duplicates=false
	duplicate_files_with_different_names.setup_results_file

	# * some info for user
	log.info -L -n -x "File count in '${dir1}':"
	fd "${fd_args[@]}" . "$dir1" | wc -l
	log.info -L -n -x "File count in '${dir2}':"
	fd "${fd_args[@]}" . "$dir2" | wc -l

	# * Populate file sizes dicts
	{
		while read -r f1; do
			f1_bytes="$(stat -f %z "$f1")" # maybe -c %s in linux?
			if [[ -n ${dir1_file_sizes["$f1_bytes"]} ]] && ! str.is_whitespace ${dir1_file_sizes["$f1_bytes"]} ; then
				log.debug "dir1_file_sizes[$f1_bytes]: $(printf '%q' "${dir1_file_sizes["$f1_bytes"]}")"
			fi
			dir1_file_sizes["$f1_bytes"]="${dir1_file_sizes["$f1_bytes"]} $f1"
		done <<< "$(fd "${fd_args[@]}" . "$dir1")"

		if [[ "$dir1" == "$dir2" ]]; then
			dir2_file_sizes=("${dir1_file_sizes[@]}")
		else
			while read -r f2; do
				f2_bytes="$(stat -f %z "$f2")"
				dir2_file_sizes["$f2_bytes"]="${dir2_file_sizes[$f2_bytes]} $f2"
			done <<< "$(fd "${fd_args[@]}" . "$dir2")"
		fi


		for f1_bytes in "${(k)dir1_file_sizes[@]}"; do
			log.debug "f1_bytes: ${f1_bytes}"
			for f1 in ${dir1_file_sizes[$f1_bytes]}; do
				f1="$(strip "$f1")"
				log.debug "f1: ${f1}"
				# when 2 different dirs, maybe should seen_duplicates+=(realpath --relative-base="$dir1" "$f1")
				# f1_relpath="$(realpath --relative-base="$dir1" "$f1")"
				# shellcheck disable=SC1073
				# shellcheck disable=SC1072
				(($seen_duplicates[(Ie)$f1])) && continue
				file_has_text "$f1" || {
					log.warn "'$f1' is empty (only whitespace); skipping" -x -L
					continue
				}
				f1_printed=false
				f1_bname="$(basename "$f1")"
				for f2 in ${dir2_file_sizes[$f1_bytes]}; do
					f2="$(strip "$f2")"
					log.debug "f2: ${f2} | : ${}"
					# f2_relpath="$(realpath --relative-base="$dir2" "$f2")"
					# shellcheck disable=SC1073
					(($seen_duplicates[(Ie)$f2])) && continue
					f2_bname="$(basename "$f2")"
					[[ "$f1_bname" == "$f2_bname" ]] && continue
					f2_bytes="$(stat -f %z "$f2")"
					[[ "$f1_bytes" != "$f2_bytes" ]] && continue
					if diff_quiet "$f1" "$f2"; then
						! $f1_printed && {
							f1_bytes_human="$(printf "$f1_bytes" | python3 -c 'from sys import stdin; print(f"{int(stdin.read()):,}")')"
							log.notice -L -x "\nDuplicates of '${f1}' (${f1_bytes_human} bytes, or $(cmmand du -h "${f1}" | cut -d $'\t' -f 1)):"
							f1_printed=true
						}
						seen_duplicates+=("$f2")
						$write_seen_duplicates && printf "%s\n" "$f2" >>./.duplicate_files_with_different_names
						log.info -x -L "\t$f2"
					fi
				done
				$f1_printed && {
					seen_duplicates+=("$f1")
					$write_seen_duplicates && printf "%s\n\n" "$f1" >>./.duplicate_files_with_different_names
				}
			done
		done
		return
	}

	# * diff files
	while read -r f1; do
		# when 2 different dirs, maybe should seen_duplicates+=(realpath --relative-base="$dir1" "$f1")
		# f1_relpath="$(realpath --relative-base="$dir1" "$f1")"
		# shellcheck disable=SC1073
		(($seen_duplicates[(Ie)$f1])) && continue
		rg --quiet "\S" "$f1" || {
			log.warn "'$f1' is empty (only whitespace); skipping" -x -L
			continue
		}
		f1_printed=false
		f1_bname="$(basename "$f1")"
		f1_bytes="$(stat -f %z "$f1")" # maybe -c %s in linux?
		while read -r f2; do
			# f2_relpath="$(realpath --relative-base="$dir2" "$f2")"
			# shellcheck disable=SC1073
			(($seen_duplicates[(Ie)$f2])) && continue
			f2_bname="$(basename "$f2")"
			[[ "$f1_bname" == "$f2_bname" ]] && continue
			f2_bytes="$(stat -f %z "$f2")"
			[[ "$f1_bytes" != "$f2_bytes" ]] && continue
			if diff_quiet "$f1" "$f2"; then
				! $f1_printed && {
					f1_bytes_human="$(printf "$f1_bytes" | python3 -c 'from sys import stdin; print(f"{int(stdin.read()):,}")')"
					log.notice -L -x "\nDuplicates of '${f1}' (${f1_bytes_human} bytes, or $(command du -h "${f1}" | cut -d $'\t' -f 1)):"
					f1_printed=true
				}
				seen_duplicates+=("$f2")
				$write_seen_duplicates && printf "%s\n" "$f2" >>./.duplicate_files_with_different_names
				log.info -x -L "\t$f2"
			fi
		done <<< "$(fd "${fd_args[@]}" . "$dir2")"
		$f1_printed && {
			seen_duplicates+=("$f1")
			printf "%s\n\n" "$f1" >>./.duplicate_files_with_different_names
		}
	done <<< "$(fd "${fd_args[@]}" . "$dir1")"
}

# # duplicate_dirs <DIR_1> [DIR_2] [fd options... (not -u* or -t *)]
function duplicate_dirs(){
	function duplicate_dirs.2_different_dirs_usecase_validation(){
		local _dir1="$1"
		local _dir2="$2"
		shift 2 || return 1
		if [[ "${_dir1%/}/" = "${_dir2%/}/" ]]; then
			log.error "Got the same absolute path twice: ${_dir1}"
			return 1
		fi
		if [[ "${_dir1%/}/" = "${_dir2%/}/"* || "${_dir2%/}/" = "${_dir1%/}/"* ]]; then
			log.error "${_dir1} or ${_dir2} is a subdir of the other"
			return 1
		fi
		return 0
	}
	function duplicate_dirs.single_dir_usecase_validation(){
		local _dir="$1"
		shift 1 || return 1
		if [[ ! -d "${_dir}" ]]; then
			log.error "Not a directory or doesn't exist: ${_dir}"
			return 1
		fi
		return 0
	}
	# Argument parsing
	{
	local dir1="$(realpath "$1")"
	shift 1 || { log.error "$0: Not enough args (expected at least 1, got ${#$}. Usage:\n$(docstring "$0")"; return 2; }
	local dir2
	local dir1_and_dir2_are_same
	if [[ -n "$1" && "$1" != -* ]]; then
		dir2="$(realpath "$1")"
		shift
		duplicate_dirs.2_different_dirs_usecase_validation "$dir1" "$dir2" || return 1
		if diff_quiet "$dir1" "$dir2" -r; then
			log.title "'$dir1' and '$dir2' are duplicates of each other" -x
			return 0
		fi
		dir1_and_dir2_are_same=false
	else
		dir2="$dir1"
		dir1_and_dir2_are_same=true
		duplicate_dirs.single_dir_usecase_validation "$dir1" || return 1
	fi
	local fd1_args=(-uu -t d "$@" --absolute-path -E .git -E .idea -E .vscode -E .run -E __pycache__ -E .ipynb_checkpoints)
	local fd2_args=(${fd1_args[@]})
	}

	# Stats and progress
	{
	declare -i dir1_subdir_count=0
	declare -i dir2_subdir_count=0
	dir1_subdir_count=$(fd "${fd1_args[@]}" . "$dir1" | wc -l | xargs)
	declare -i pow="$((${#dir1_subdir_count}-2))"
	pow=$((pow < 1 ? 1 : pow))
	declare -i show_progress_every="$(bc <<< "$dir1_subdir_count / 10 ^ ${pow}")"
	log.info -L -x "Dir count in '${dir1}': $dir1_subdir_count"
	}

	log.title "Finding duplicate subdirs of '$dir1' and '$dir2'..." -x
	typeset -A comparisons
	local dir1_subdir dir1_subdir_printed=false
	local dir2_subdir
	typeset -A dir_sizes_cache
	declare -i dir1_iterated_subdirs_count=0

	local progress
	while read -r dir1_subdir; do
		dir1_subdir_printed=false
		# Print progress
		{
		((dir1_iterated_subdirs_count++))
		if [[ "$(bc <<< "${dir1_iterated_subdirs_count} % ${show_progress_every}")" = 0 ]]; then
			progress="$(bc <<< "scale=1; (${dir1_iterated_subdirs_count}/${dir1_subdir_count})*100")"
			log.debug -L -x "${progress}% done (${dir1_iterated_subdirs_count}/${dir1_subdir_count})"
		fi
		}
		[[ ! $dir_sizes_cache[(Ie)"$dir1_subdir"] ]] \
		 && dir_sizes_cache["$dir1_subdir"]="$(dir_size_bytes "$dir1_subdir")"
		dir_is_empty "$dir1_subdir" && continue
		while read -r dir2_subdir; do
			# Populate $dir_sizes_cache and $comparisons on-the-fly and bail-early checks
			{
			[[ "$dir1_subdir" == "$dir2_subdir" ]] && continue
			if [[ $comparisons[(Ie)"${dir1_subdir},${dir2_subdir}"] \
				 || $comparisons[(Ie)"${dir2_subdir},${dir1_subdir}"] ]]
			then
				continue
			else
				comparisons["${dir1_subdir},${dir2_subdir}"]=""
				comparisons["${dir2_subdir},${dir1_subdir}"]=""
			fi
			dir_is_empty "$dir2_subdir" && continue
			[[ ! $dir_sizes_cache[(Ie)"$dir2_subdir"] ]] \
			 && dir_sizes_cache["$dir2_subdir"]="$(dir_size_bytes "$dir2_subdir")"
			[[ ${dir_sizes_cache["$dir1_subdir"]} == ${dir_sizes_cache["$dir2_subdir"]} ]] || continue
			}
			if diff_quiet "$dir1_subdir" "$dir2_subdir" -r; then
				$dir1_subdir_printed || {
					log.notice -L -x "\nDuplicates of '${dir1_subdir}' ($(command du -sh "${dir1_subdir}" | cut -d $'\t' -f 1 | xargs)):"
					dir1_subdir_printed=true
				}
				# seen_duplicates+=("$dir2_subdir")
				# $write_seen_duplicates && printf "%s\n" "$dir2_subdir" >>./.duplicate_dirs
				log.info -x -L "\t$dir2_subdir"
			fi
		done <<< "$(fd "${fd2_args[@]}" . "$dir2")"

	done <<< "$(fd "${fd1_args[@]}" . "$dir1")"
}



log.notice -x -L "Avaialble functions:"
declare this_file="$0"
declare function_definition
while read -r function_definition; do
	printf " - ${function_definition}\n"
	compdef "$function_definition"=fd
done <<< $(command grep --color=no -Po '(?<=^function ).+(?=\(\))' "$this_file")
unset function_definition