#!/usr/bin/env zsh

##############################################
# *** Functions that don't fit anywhere else
##############################################

if [[ "$OS" = Linux ]]; then
  source misc.linux.sh
fi

# # editfile <EDITOR> <-f FILEPATH> [[-q ]FILE_CONTENT_QUERY] [EDITOR_ARGS...]
function editfile() {
  log.title "$0 ${*}"
  if [[ ! "$2" ]]; then
    log.fatal "$0: Not enough args (expected at least 2, got ${#$}. Usage: $(docstring -p "$0"))"
    return 1
  fi

  local file_path query editor
  local -a editorflags=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
    -f)
      file_path="$2"
      shift
      ;;
    -q)
      query="$2"
      shift
      ;;
    -*) editorflags+=("$1") ;;
    *)
      if [[ "$editor" ]]; then
        if [[ "$query" ]]; then
          log.debug "query already set: $query; adding to ${Cc}editorflags"
          editorflags+=("$1")
        else
          query="$1"
        fi
      else
        editor="$1"
      fi
      ;;
    esac
    shift
  done

  [[ ! "$file_path" ]] && {
    log.fatal "Not enough args (expected at least 2, got ${#$}. Usage: $(docstring -p "$0")"
    return 1
  }
  if ! isdefined "$editor"; then
    log.fatal "editor is not defined: ${Cc}$editor"
    return 1
  fi

  if [[ "$editor" = code ]] && ! [[ ${editorflags[(r) - g]} ]]; then
    editorflags+=(-g)
  fi
  log.debug "$(typeset query editorflags)"

  [[ "$query" ]] && {
    # ** get line number where "$query" is
    line_num="$(linenumof "$query" "$file_path")"
    if [[ "$?" = 0 ]] && isnum "$line_num"; then
      log.success "Opening $file_path at $line_num"
      if [[ "$editor" = *vi* ]]; then
        "$editor" "${editorflags[@]}" "+${line_num}" "$file_path"
        return $?
      else
        "$editor" "${editorflags[@]}" "$file_path":"$line_num"
        return $?
      fi
    fi
    log.warn "Failed ${Cc}linenumof '$query' '$file_path'"

    # * Failed with linenumof, try interactively with fzf
    # Now use fzf to get some line (query) that exists in $file_path

    local new_query
    new_query="$(fzf -q "$query" <"$file_path")"
    if [[ "$?" = 0 && "$new_query" ]]; then
      new_query="$(strip "$new_query")"
      log.success "Found: $(typeset new_query). Calling recursively with ${Cc}$editor '$new_query'"
      editfile "$editor" -q "$new_query" -f "$file_path" "${editorflags[@]}"
      return $?
    fi

    # fzf couldn't find $query exactly in $file_path,
    log.warn "Failed ${Cc}fzf -q '$query'"
  } # end '[[ "$query" ]] &&' block

  # ** Either no $query, or both linenumof and fzf failed getting $query, so just open file_path
  log.info "Calling ${Cc}$editor ${editorflags[*]}${Cc0} to simply edit $(typeset file_path)"
  "$editor" "${editorflags[@]}" "$file_path"
  return $?
}

# # copy <FILE or TEXT or STDIN> [-v,--verbose {0,1,2}] [-r,--raw]
# -v,--verbose {0,1,2}   Set verbosity level (0-2). Default: ${COPY_VERBOSITY:-0}.
#													Verbosity>=1 will log the copied content if it's not piped.
#													Verbosity==2 will log the copied content even if it's piped.
# -r,--raw               If input is a file path, copy the literal path instead of its content. Default: ${COPY_RAW:-false}
function copy() {
  local verbosity=${COPY_VERBOSITY:-0} raw=${COPY_RAW:-false} value

  while (($#)); do
    case "$1" in
    -v=* | --verbose=*) verbosity="${1#*=}" ;;
    -v | --verbose) verbosity="$2"; shift ;;
    -r | --raw) raw=true ;;
    -*)
      log.error "Unknown option: $1"
      return 1 ;;
    *)
      [[ "$value" ]] && {
        log.error "Too many arguments: $1"
        return 1
      }
      value="$1" ;;
    esac
    shift
  done

  local content
  if [[ ! $value ]]; then
    if ! is_piped; then
      log.error "$0: Not enough arguments"
      docstring -p "$0"
      return 1
    fi
    content="$(<&0)"
    [[ $verbosity -ge 2 ]] && log.info "Copying stdin:\n${Cc}${content}"
    printf "%s" "$content" | pbcopy
    return $?
  fi
  [[ "$verbosity" -gt 0 ]] && log.info "Copying ${Cc}${value}"
  # if [[ -e "$value" && "$raw" != true ]]; then
  #   if [[ -d "$value" ]]; then
  #     local -a fzf_args=(
  #       --header="$value is a directory. Select a file to copy"
  #       --preview="if [[ -f {1} ]]; then bat --color=always {1}; else command ls -ap {1}; fi"
  #       --preview-window=right:wrap
  #     )
  #     local dir_entries="$(command ls -ap "$value" | grep -vE '^\.{1,2}/$')"
  #     local files="$(grep -v ".*/" <<<"$dir_entries" | sort -V)"
  #     local dirs="$(grep ".*/" <<<"$dir_entries" | sort -V)"
  #     content="$(fzf "${fzf_args[@]}" < <(echo "$files\n$dirs"))"
  #     [[ -z "$content" ]] && return 1
  #     content="$value/$content"
  #   fi
  #   content="$(<"$value")"
  # else
  #   content="$value"
  # fi
  if [[ -d "$value" ]]; then
    printf "%s" "$value" | pbcopy
    return $?
  fi
  if [[ $raw == true || ! -f "$value" ]]; then
    printf "%s" "$value" | pbcopy
    return $?
  fi
  pbcopy <"$value"
  return $?
}

# # copee
# Print stdin to stderr before copying it to clipboard.
function copee(){
  eee | copy "$@"
}

# # paste
# Paste from clipboard.
function paste() {
  clippaste "$@"
}

# # pastee
# Print clipboard to stderr before pasting it.
function pastee(){
  clippaste | eee
}

# ** External Shells
# --------------------

function bashh() {
  /bin/bash -c \
    "has_manpage=false; has_help=false;
    man $1 >/dev/null 2>&1 && has_manpage=true;
    help $1 >/dev/null 2>&1 && has_help=true;
    if [[ \$has_manpage == true ]]; then
      man $1
    elif [[ \$has_help == true ]]; then
      help $1
      echo man page did not exist, used help instead
    else
      echo No manpage or help found for $1
    fi
    "
}
function zshh() {
  run-help "$@"
}
