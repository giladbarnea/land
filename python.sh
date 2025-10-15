#!/usr/bin/env zsh
# sourced after inspect.sh

# *** py.* Functions (spawn a python interpreter)

declare -a __py_namespace_variables=(
	sys
	newline
	stdin
	lines
)

__py_base_namespace="
import sys
newline = '\\\n'
"

# sys.stdin.isatty() is False when piped
# without --readlines:
__py_namespace="
$__py_base_namespace
stdin = sys.stdin.read()
lines = stdin.split()   # splits spaces and newlines alike
words = list(map(str.strip, stdin.split(' ')))
"

# with --readlines:
__py_namespace_readlines="
$__py_base_namespace
stdin = sys.stdin
lines = list(map(str.strip, stdin.readlines()))
"

# # py.eval <PYTHON_STATEMENT/STDIN...> [--readlines] [+S, --user-site-packages=true | --user-site-packages=false]
# Namespace includes:
# - `sys`
# - `stdin`      # sys.stdin.read() by default; sys.stdin with --readlines'
# - `lines`      # stdin.read().split() by default; stripped stdin.readlines() with --readlines'
# - `line`       # for line in lines...
# - `words`      # stdin.read().split(" ") (unavailble with --readlines)'
# - `newline`
#
# If PYTHON_STATEMENT raises a NameError about `'line' is not defined`, executes
# PYTHON_STATEMENT inside a `for line in lines` loop.
# ## Examples
# ```bash
# py.eval 'print($*)'
# echo "hello world" | py.eval 'if line == "world": sys.exit(1)'
# ```
function py.eval() {
	local readlines=false
	local user_site_packages=false
	local py_statements=()
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--readlines*)
				if [[ "$1" == *=* ]]; then
					readlines=${1/*=/}
				else
					readlines=true
				fi ;;
			+S|--user-site-packages=true) user_site_packages=true ;;
			--user-site-packages=false) user_site_packages=false ;;
			*) py_statements+=("$1") ;;
		esac
		shift
	done
	if [[ ! "${py_statements}" ]]; then
		log.fatal "$0 expects at least 1 positional/piped python statement to evaluate"
		docstring -p "$0"
		return 1
	fi
	local py_program=""
	if is_piped; then
		if "$readlines"; then
			py_program+="$__py_namespace_readlines"
		else
			py_program+="$__py_namespace"
		fi
	else
		py_program+="$__py_base_namespace"
	fi

	py_program+="
try:
    %b
except NameError as ne:
    if ne.args[0] != \"name 'line' is not defined\":
        raise
    for line in lines:
        print(line)
"
	#log.debug "py_program: ${py_program}"
	# todo: idea: to allow multi-line statements, catch SyntaxError and run $py_statement without indentation.
	#  or if has newline, indent all lines.

	# flags:
	#  -O  Remove assert and __debug__ clauses. Sometimes minor performance boost, sometimes minor slowdown (3.13)
	#  -OO Like -O, but also discard docstrings. Slows down startup!
	#  -B  Don't write .pyc files on import. Sometimes minor performance boost, sometimes minor slowdown (3.13)
	#  -X  importtime
	#  -I  implies -E (ignore PYTHON* env) and -s (Don't add user site directory to sys.path)
	#  -S  don't imply 'import site' on initialization
	# cmd='/opt/homebrew/bin/python3.12 -B -O -IS -X no_debug_ranges -c ""'; hyperfine --warmup 3 "$cmd" --prepare="$cmd"
	local statement
	local func_exitcode=0
	local python_exitcode
	local formatted_py_program
	local python_process_args=(-O -B)
	if ! $user_site_packages; then
		# -S gives the biggest performance boost. With 3.12 it's 12ms vs 17ms
		python_process_args+=(-IS)
	fi
	python_process_args+=(-c)
	# shellcheck disable=SC2068
	for statement in ${py_statements[@]}; do
		# shellcheck disable=SC2059
		formatted_py_program="$(printf "$py_program" "$statement")"
		PYTHONHASHSEED=0 python3.12 "${python_process_args[@]}" "$formatted_py_program"
		python_exitcode=$?
		if [[ "$python_exitcode" != 0 ]]; then
			func_exitcode=$python_exitcode
		fi
	done
	return $func_exitcode
}

# # py.print <VALUE/STDIN...> [options]
# Options:
# --readlines
# --file FILE=sys.stdout
# --end STR=''
# -s SETUP_SMT...
# +S, --user-site-packages=true | --user-site-packages=false (default false)
# Namespace includes:
# - `sys`
# - `stdin`      # sys.stdin.read() by default; sys.stdin with --readlines'
# - `lines`      # stdin.read().split() by default; stripped stdin.readlines() with --readlines'
# - `line`       # for line in lines...
# - `words`      # stdin.read().split(" ") (unavailble with --readlines)'
# - `newline`
# ## Examples
# ```zsh
# $ echo "hello world" | py.print
# hello world
# $ echo "hello world" | py.print stdin
# hello world
# $ echo "hello world" | py.print lines
# ['hello', 'world']
# $ echo "hello world" | py.print line
# hello
# world
# ```
function py.print() {
	local end
	local file=sys.stdout
	local readlines=false
	local user_site_packages=false
	local print_values=()
	local setup_statements=()
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--end*)
				if [[ "$1" == *=* ]]; then
					end=${1/*=/};
				else
					end="$2"; shift
				fi ;;
			--file*)
				if [[ "$1" == *=* ]]; then
					file=${1/*=/};
				else
					file="$2"; shift
				fi ;;
			--readlines*)
				if [[ "$1" == *=* ]]; then
					readlines=${1/*=/}
				else
					readlines=true
				fi ;;
			-s) setup_statements+=("$2"); shift ;;
			+S|--user-site-packages=true) user_site_packages=true ;;
			--user-site-packages=false) user_site_packages=false ;;
			*) print_values+=("$1") ;;
		esac
		shift
	done
	if [[ ! "${print_values}" ]]; then
		if is_piped; then
			# echo hi | py.print -> Prepend stdin
			print_values=(stdin)
		else
			log.fatal "$0 expects at least 1 positional/piped value to print"
			return 1
		fi
	fi

	# todo (bug): this is modyfing the global namespace!
	! $readlines && __py_namespace_variables+=(words)

	local value
	local exitcode=0
	local joined_setup_statements
	if [[ "${setup_statements}" ]]; then
		joined_setup_statements="$(printf "%s; " "${setup_statements[@]}")"
	fi

	for value in "${print_values[@]}"; do
		py.eval "${joined_setup_statements} print(${value}, end='$end', file=$file)" --readlines=$readlines --user-site-packages=$user_site_packages
		exitcode=$?
		if [[ "$exitcode" != 0 ]]; then
			return $exitcode
		fi
	done
	return 0
}


# complete -o default -C 'completion.generate <PYTHON_TO_EVALUATE> [--readlines]' py.bool py.eval





#region ---[ Virtual Environments

# # venv <PY_EXEC> [ENV_NAME=.venv]
# Creates then activates a virtual env.
# If it already exists, prompts to activate it.
# ### Example
# ```bash
# venv py38 env
# ```
# ## Convenience Methods
# ```bash
# venv38 [ENV_NAME]   # all default to ".venv"
# venv37 [ENV_NAME]
# venv39 [ENV_NAME]
# ```
function venv() {
	setopt localoptions nowarncreateglobal
	log.title "venv($*)"
	if [[ -z "$1" ]]; then
		log.fatal "$0: Not enough args (expected at least 1, got ${#$}). Usage:\n$(docstring "$0" -p)"
		return 2
	fi
	# * Pre-checks
	local pyexec="$1"
	local envdir="${2:-.venv}"
	log.debug "pyexec: $pyexec | envdir: $envdir"
	if ! isdefined "$pyexec"; then
		log.fatal "'$pyexec' is not defined"
		docstring "$0" -p
		return 1
	fi
	if [[ -e "$envdir" ]]; then
		input "$envdir already exists, try to activate?" || return 3
		vactivate "$envdir"
		return $?
	fi
	local pyversion
	if ! pyversion="$(vex "$pyexec" --version)"; then
		docstring "$0" -p
		return 1
	fi

	# * Create virtual env
	local exitcode
	local virtualenv_output
	virtualenv_output="$("$pyexec" -m virtualenv "$envdir" 2>&1)"
	exitcode=$?
	if [[ $exitcode != 0 ]]; then
		if [[ "$virtualenv_output" = *"No module named virtualenv" ]]; then
			confirm "'virtualenv' is not installed for $pyversion, install virtualenv?" || return "$exitcode"
			vex "$pyexec" -m pip install virtualenv --break-system-packages || return "$?"
			vex "$pyexec" -m virtualenv "$envdir" || return "$?"
		else
			log.fatal "Failed creating '$envdir' with $pyversion, output:\n$virtualenv_output"
			return $exitcode
		fi
	fi
	log.success "Created '$envdir' with $pyversion"
	confirm "Activate?" && {
		vex source "$envdir"/bin/activate || return "$?"
	}
	pyinstallgoodies
	return $?
}

function pyinstallgoodies(){
	setopt localoptions errreturn
	typeset -A choices=(
	 q     "quit"
	 r     "rich"
	 r2    "rich ruff"
	 ru    "ruff"
	 i     "ipython IPythonClipboard ipython_autoimport"
	 ir    "ipython IPythonClipboard ipython_autoimport rich"
	 iru   "ipython IPythonClipboard ipython_autoimport ruff"
	 ir2   "ipython IPythonClipboard ipython_autoimport rich ruff"
	 i++   "ipython IPythonClipboard ipython_autoimport rich ruff jupyter-ai-magics langchain_anthropic langchain-openai"  # %load_ext jupyter_ai_magics; %ai register gpt openai-chat:gpt-4
	 j     "jupyter ipython IPythonClipboard ipython_autoimport"
	 jr    "jupyter ipython IPythonClipboard ipython_autoimport rich"
	 jru   "jupyter ipython IPythonClipboard ipython_autoimport ruff"
	 jr2   "jupyter ipython IPythonClipboard ipython_autoimport rich ruff"
	 j++   "jupyter ipython IPythonClipboard ipython_autoimport rich ruff jupyter-ai langchain_anthropic langchain-openai"  # %load_ext jupyter_ai; %ai register gpt openai-chat:gpt-4
	 c     "custom"
	)
	# E.g. choices_str='[q]uit [r]ich [r+] rich ruff [i]python rich
	# shellcheck disable=SC2301
	local choices_str=${"$(typeset choices)"#*=}
	local what_to_install="$(input 'What libs to install?' --choices "${choices_str}")"
	log.debug "$(typeset what_to_install)"
	local install_these
	case "$what_to_install" in
		quit) return 0 ;;
		custom) install_these="$(input 'packages')"
			 log.debug "$(typeset install_these)"
			 vex ---just-run pip install $install_these ;;
		 *) vex ---just-run pip install "$what_to_install" ;;
	esac
	unsetopt localoptions errreturn
	[[ "$what_to_install" = *"jupyter "* && -n "$VIRTUAL_ENV" ]] && {
	  local venv_basename="$(basename "$VIRTUAL_ENV")"
	  if confirm "Install kernel for ${venv_basename} venv?"; then
      vex ---just-run python -m ipykernel install --user --name="${venv_basename}"
	  fi
	}
	[[ "$what_to_install" = *jupyter-ai* ]] && {
		log.info "To use jupyter-ai, run these first:" \
						 "\nOPENAI_API_KEY=Path('/Users/gilad/.openai-api-key-pecan').read_text(); ANTHROPIC_API_KEY=Path('/Users/gilad/.anthropic-api-key').read_text()" \
						 '\n%env OPENAI_API_KEY=$OPENAI_API_KEY' \
						 '\n%env ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY' \
						 '\n%load_ext jupyter_ai  # Or jupyter_ai_magics' \
						 '\n%ai register chat anthropic-chat:claude-3-sonnet-20240229' \
						 '\n# Jupyter:' \
						 '\n%%ai chat  # Or get_ipython().run_cell_magic("ai", "chat", """...""")' \
						 '\n...: Hi' \
						 '\noutput=_.data  # for no -f, which defaults to IPython.display.Markdown. for -f text, use _.text' \
						 "\noutput[output.index('<answer>') + len('<answer>'):output.index('</answer>')]" \
						 "\n# IPython:" \
						 '\n%automagic off' \
						 '\nai = lambda _u: get_ipython().run_cell_magic("ai", "chat", _u).data' \
						 -L -x
	}
}

# # vactivate [PATH]
# If no PATH is given, looks to activate virtualenv in env, venv, .env, or .venv.
# Confirms before activating, deactivates existing if any etc.
function vactivate(){
	local venv_dir venv_dir_tilda venv_dir_relative
	local exitcode confirmed=false
	local given_path="${1:-$PWD}"
	local potential_venv_dirs=()
	if [[ -f "$given_path/bin/activate" ]]; then
		# Quick optimization.
		potential_venv_dirs=("${given_path}")
	else
		potential_venv_dirs=( "${given_path}/"{.venv,.env,env,venv} )
	fi
	for venv_dir in "${potential_venv_dirs[@]}"; do
		[[ -f "$venv_dir/bin/activate" ]] || continue
		venv_dir_tilda="${venv_dir/#${HOME}/~}"
		[[ "$VIRTUAL_ENV" ]] && {
			[[ "$VIRTUAL_ENV" = "$(realpath "$venv_dir")" ]] && log.success "Already activated: ${Ci}${venv_dir_tilda}${Ci0}" && return 0
			venv_dir_relative="./$($(command -v grealpath || command -v realpath) --relative-to="$PWD" "$venv_dir")"
			confirm "Already activated: ${Ci}${VIRTUAL_ENV/#${HOME}/~}${Ci0}, switch to ${Ci}${venv_dir_relative}${Ci0}?" || return 1
			confirmed=true
			deactivate || return 1
		}
		venv_dir_relative="${venv_dir_relative:-"./$($(command -v grealpath || command -v realpath) --relative-to="$PWD" "$venv_dir")"}"
		$confirmed || confirm "Activate ${Ci}${venv_dir_relative}${Ci0}?" || return 0
		vex source "$venv_dir"/bin/activate
		exitcode=$?
		[[ "$exitcode" = 0 ]] && log.success "Activated ${Ci}${venv_dir_relative}${Ci0}"
		return $exitcode
	done
	log.error "No virtualenv found in ${Ci}${PWD}"
	return 1
}

# # randompymodule [MODULE]
# Pretty-prints (a random standard-lib) python module's docstring
function randompymodule() {
	local modulename="${1}"
	"$(alias_value syspy)" <<-EOF | { if isdefined bat; then bat -l help --style=rule,snip --color=always; else less; fi ; }
	import sys
	from random import choice
	from glob import glob1
	lib=f'{sys.prefix}/{getattr(sys, "platlibdir", "lib")}/python3.{sys.version_info[1]}'
	modulename = "$modulename" or choice(glob1(lib, '*'))
	if modulename.endswith('.py'):
		modulename = modulename[:-3]
	module = __import__(modulename)
	if module.__doc__:
		print(f'\x1b[1;97m{module.__name__}\x1b[0m\n\n', module.__doc__)
	else:
		from contextlib import redirect_stdout
		from io import StringIO
		f = StringIO()
		# by default 'help' uses a pager, this bypasses it
		with redirect_stdout(f):
			help(module)
		print(f.getvalue())
	EOF
}

# # pytest.parallel [-k] MATCHER [PYTEST_ARGS...]
# Runs in min(nproc, number of tests) processes.
function pytest.parallel(){
		if [ $# -eq 0 ]; then
				log.error "Please provide a matcher argument."
				return 1
		fi

		local -a pytest_args=( "$@" )
		local -a test_specifying_args
		local -a pytest_other_args
		if [[ "$1" == -k ]]; then
				pytest_other_args=( "${pytest_args[@]:2}" )
				test_specifying_args=( -k "$2" )
		else
				pytest_other_args=( "${pytest_args[@]:1}" )
				test_specifying_args=( "$1" )
		fi
		typeset -p pytest_args pytest_other_args
	  # --collect-only -q does this!

		local -a full_test_names=( "$(pytest "${test_specifying_args[@]}" --collect-only -q 2>/dev/null | catrange 0 -4 | uniq)" )
		full_test_names=( "${(f)full_test_names}" )
		if [[ ! "$full_test_names" ]]; then
				log.error "No tests found matching the given $(typeset test_specifying_args)"
				return 1
		fi

		typeset -p full_test_names
		local -i process_count
		local -i machine_process_count="$(nproc)"
		# The minimum out of $(nproc) and ${#full_test_names}
		process_count=$((machine_process_count < ${#full_test_names} ? machine_process_count : ${#full_test_names}))
		typeset -p process_count

		log.info "Running ${#full_test_names} tests in parallel over ${process_count} processes..."
		print -l "${full_test_names[@]}" | xargs -P ${process_count} -I {} env VIRTUAL_ENV="$VIRTUAL_ENV" PATH="$PATH" PWD="$PWD" PYTHONPATH="$PYTHONPATH" PYTHONHOME="$PYTHONHOME" pytest {} "${pytest_other_args[@]}"
}

# # pytest.nowarn [PYTEST_ARGS...]
# Convenience for `pytest -W ignore --disable-warnings -p no:warnings "$@"`.
function pytest.nowarn(){
  pytest -W ignore --disable-warnings -p no:warnings "$@"
}
