#!/bin/env zsh

# ----------[ sgpt ] ---------------


# # sgpturl <URL> <QUESTION> [--follow-links]
# Wrapper for search_web.py.
function sgpturl(){
  local url
  local question
  local follow_links=False

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --follow-links) follow_links=True ;;
      *)
        if [[ -z "$url" ]]; then
          url="$1"
        elif [[ -z "$question" ]]; then
          question="$1"
        else
          log.error "Too many arguments"
          docstring -p "$0"
          return 1
        fi
        ;;
    esac
    shift
  done
  local prompt="Understand the contents of the given url, "
  local prompt_end
  if [[ "$follow_links" = True ]]; then
    prompt="Understand the contents of the given url, and follow the links it contains, then answer the question: ${question}. url: ${url}."
  else
    prompt="Understand the contents of the given url, and only it, then answer the question: ${question}. url: ${url}"
  fi
  sgpt --role GPT "${prompt}" --no-cache
}

# # sgptcommit [FILES...] [--one-by-one] [-v, --verbose]
# Wrapper for generate_commit_message.py.
# FILES can be:
# - file1.py
# - file1.py path/to/file2
# - "*.py"
# - "*.{py,txt}"
function sgptcommit(){
  local one_by_one=False
  local verbose=False
  local files=()
  while (( $# )); do
    case "$1" in
      --one-by-one) one_by_one=True;;
      --one-by-one=[Tt]rue) one_by_one=True;;
      --one-by-one=[Ff]alse) one_by_one=False;;
      -v|--verbose) verbose=True;;
      *) files+=("$1");;
    esac
    shift
  done
  local shellgpt_config_was_in_path=false
  pathfind "$HOME/.config/shell_gpt" || shellgpt_config_was_in_path=true
  (
    # Spawn a subshell to avoid polluting the current environment
    source "$HOME"/dev/shell_gpt/.venv/bin/activate
    pathappend "$HOME/.config/shell_gpt"
    {
      cat "$HOME/.config/shell_gpt/functions/generate_commit_message.py"
      echo "print(Function.execute('${files[*]}', one_by_one=${one_by_one}, verbose=${verbose}))"
    } > "$HOME/.config/shell_gpt/functions/generate_commit_message_.py"
    python "$HOME/.config/shell_gpt/functions/generate_commit_message_.py"
  )
  [[ $shellgpt_config_was_in_path = false ]] && pathdel "$HOME/.config/shell_gpt"
  vex ---just-run rm "$HOME/.config/shell_gpt/functions/generate_commit_message_.py"
}

# # sgptsearch <QUESTION> [-q, --query QUERY]
# Wrapper for search_web.py.
function sgptsearch(){
  local query=""
  local question=""

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      -q|--query) query="$2" ; shift ;;
      --query=*) query="${1#*=}" ;;
      *) question="$1" ;;
    esac
    shift
  done

  if [[ -n "$query" ]]; then
    sgpt --role GPT "Search the web with the query: '${query}'. Then, answer the question: ${question}" --no-cache
  else
    log.debug "$(typeset question)"
    sgpt --role GPT "Search the web for the answer to the question: ${question}" --no-cache
  fi
}

# # sgpteng <TEXT>
# Wrapper for improve_writing.py.
function sgpteng(){
  setopt MULTIBYTE
  set -x
  local text
  if [[ ! "$1" ]] && is_piped; then
    text="$(<&0)"
  else
    text="$1"
    shift || { log.error "$0: Not enough args (expected at least 1, got ${#$}). Usage:\n$(docstring "$0")"; return 2; }
  fi
  (
    source "$HOME"/dev/shell_gpt/.venv/bin/activate
    # python -u -O -B -c "$(cat $HOME/.config/shell_gpt/functions/improve_writing.py; echo "print(Function.execute(\"\"\"$text\"\"\"))")"
    builtin cd "$HOME"/.config/shell_gpt/functions || return 1
    python -u -O -B -c "import improve_writing; print(improve_writing.Function.execute(\"\"\"${text}\"\"\"))"
  )

}