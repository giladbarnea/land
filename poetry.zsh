#!/usr/bin/env zsh
#region ------------[ Poetry ]------------

function p.publish() {
	if [[ -f ./pyproject.toml ]]; then
		log.success "Found ./pyproject.toml"
	else
		log.fatal "./pyproject.toml not found"
		return 1
	fi

	# ** Virtual env checks and maybe activation
	if [[ -z "$VIRTUAL_ENV" ]]; then
		if ! p.activate; then
			log.fatal "Failed activating virtual environment"
			return 2
		fi
		p.publish "$@"
		return $?
	fi
	local expected_venv="$(poetry env info -p)"
	if [[ "$VIRTUAL_ENV" == "$expected_venv" ]]; then
		log.success "Correct virtual env is activated ($VIRTUAL_ENV)"
	else
		log.fatal "Virtual env is activated ($VIRTUAL_ENV), but expected $expected_venv"
		return 1
	fi

	# ** Get project stats
	local projinfo="$(poetry version 2>/dev/null)"
	local projname="$(cut -d ' ' -f 1 <<< "$projinfo")"
	local projver="$(cut -d ' ' -f 2 <<< "$projinfo")"
	local published_info="$(poetry search "$projname" | cut -d $'\n' -f 2 | tr -d '()')"
	log.debug "$(typeset projinfo projname projver published_info)"
	if [[ "$published_info" == "$projinfo" ]]; then
		log.success "Local version is $projver, and $projinfo is already published. returning 0"
		return 0
	fi
	log.notice "Published version is '$published_info'; publishing '$projinfo'..."

	# ** Publish
	# * rm ./dist
	if [[ -d ./dist ]]; then
		if ! vex rm -rf ./dist; then
			log.fatal Failed
			return 1
		fi
	fi
	# * poetry build
	if ! vex poetry build; then
		log.fatal Failed
		return 1
	fi
	# * publish
	if [[ -f "$HOME/.pypirc" ]]; then
		vex poetry publish "$@"
	else
		log.warn "No ~/.pypirc found"
		local password
		if password="$(input "PyPi password?")"; then
			vex poetry publish -u giladbarnea -p "$password" "$@"
			return $?
		else
			log.prompt "Run 'p.publish -u giladbarnea -p <password>'"
			return 2
		fi
	fi
}

# # p.clearcache POETRY_EXEC [--remove-envs] [--remove-artifacts]
function p.clearcache(){
	local remove_envs=false
	local remove_artifacts=false
	local poetry_exec
	while (( $# )); do
		case "$1" in
			--remove-envs) remove_envs=true ;;
			--remove-artifacts) remove_artifacts=true ;;
			*) poetry_exec="$1" ;;
		esac
		shift
	done
	[[ "$poetry_exec" ]] || { log.error "Missing POETRY_EXEC arg. Usage:" ; docstring -p "$0" ; return 1 ; }
	if "$remove_envs"; then
		vex "${poetry_exec}" env remove --all || return $?
	fi
	vex "${poetry_exec}" cache clear --all . || return $?
	if "$remove_artifacts"; then
		vex rm -rf "$("${poetry_exec}" config cache-dir)"/artifacts || return $?
	fi
}

function p.setuppy() {
	# build
	if ! poetry build; then return $?; fi

	# find .tar.gz file
	local tar_gz
	if ! tar_gz="$(find ./dist/ -mindepth 1 -type f -name "*.tar.gz")"; then
		log.fatal "no .tar.gz file"
	fi

	# create tmp extraction dir
	if ! mkdir -v __tmp; then return $?; fi

	# extract
	if ! tar -xvf "$tar_gz" -C "__tmp"; then return $?; fi

	local setuppy
	if ! setuppy="$(find __tmp -type f -name "*setup.py")"; then
		log.fatal "no setup.py file"
		return 1
	fi

	if ! mv -v "$setuppy" .; then return $?; fi

	rm -rv __tmp

	if [[ -f "./setup.py" ]]; then
		log.success "Created ./setup.py"
		return 0
	else
		log.fatal "Failed creating ./setup.py"
		return 1
	fi
}

# # p.search [POETRY_EXEC] LIBRARY_NAME
function p.search(){
	local poetry_exec search_target
	[[ "$#" -eq 0 ]] && { log.error "Not enough args" ; docstring -p "$0" ; return 1 ; }
	[[ "$#" -eq 1 ]] && { poetry_exec=poetry; search_target="$1" ; }
	[[ "$#" -eq 2 ]] && { poetry_exec="$1"; search_target="$2" ; }
	vex "$poetry_exec" search --ansi "${search_target}" 2>/dev/null | less
}

# # p.install
# Installs poetry itself.
function p.install(){
	local poetry_home="${POETRY_HOME:-$(input 'POETRY HOME:')}"
	local python_exec="$(input 'Python exec:')"
	local poetry_version="${POETRY_VERSION:-$(input 'POETRY VERSION:')}"
	curl -sSL https://install.python-poetry.org | POETRY_HOME="$poetry_home" POETRY_VERSION="$poetry_version" "$python_exec" -
}

#endregion Poetry