#! /usr/bin/env zsh
# End with \ but not 'do\':		.*(?<!do)\\$\n([^:].*\n)*

# Merge bash loops to 1 line:	(?<=do)\\$\n(:[^:].*\n)*

# Duplicate subsequent lines:
#   ^: \d{10}:\d+;([^\n]+)\n: \d{10}:\d+;\1$
#   rg --line-number -u --multiline --pcre2 '^: \d+:\d;(.+)$\n(: \d+:\d;\1(\n|$))' .zsh_history > /tmp/duplicates.txt
#   lines = Path('/tmp/duplicates.txt').open().readlines()
#   linenums = [int(linenum) for linenum, _, __ in map(lambda s:s.partition(':'), lines)]
#   from collections import defaultdict
#   dupes = defaultdict(list)
#   for i, linenum in enumerate(linenums):
#       offset = 1
#       if linenum not in dupes and all(x != linenum for x in dupes.values()):
#           while linenums[i+offset] == linenum+offset:
#               dupes[linenum].append(linenum+offset)
#               offset += 1

# Accidental backslash at the end:
#  ^:.*(\\?$\n[^:].*)+\n
{

  # http://zsh.sourceforge.net/Guide/zshguide02.html#l18
  # zsh-navigation-tools has n-history
  # hstr plugin

  alias h='history'
  # alias hpy="$SCRIPTS/history.py"
  
  function .smart-grep() {
    local results
    results="$(command grep -P "$@")"
    if [[ $? != 0 || -z "$results" ]]; then
      # Exit now if this is already case insensitive
      [[ "${@[(r)-i]}" ]] || {
        log.error "No results found for '$*'"
        return 1
      }
      log.warn "No results found for '$*', retrying case insensitively."
      results="$(command grep -Pi "$@")"
      [[ $? != 0 || -z "$results" ]] && {
        log.error "No results found for '$*'"
        return 1
      }
    fi
    echo "$results"
  }
  
  # # hs <EXTENDED_REGEX> [grep options...]
  # Basically does `history | command grep -P "$@"`
  # Any additional args are passed to `grep`.
  # If nothing is grepped, retries case insensitively.
  # ## See also
  # hsi, hsu
  function hs() {
    setopt localoptions errreturn pipefail
    history | .smart-grep "$@" | bat -pl zsh
  }

  # # hsc <EXTENDED_REGEX> [grep options...]
  # Greps and displays only the command part of the matches.
  function hsc() {
    local -a cut_field
    if [[ "${options[extendedhistory]}" == on ]]; then
      cut_field=(24-)
    else
      cut_field=(8-)
    fi
    history | cut -c "${cut_field[@]}" | .smart-grep "$@" | bat -pl zsh
  }
  
  # # hsu <EXTENDED_REGEX> [grep options...]
  # Greps and displays only the command part of the matches. Sorted and unique results.
  function hsu() {
    hsc "$@" | sort -u | bat -pl zsh
  }


  # # hsi <EXTENDED_REGEX> [grep options...]
  # Basically does `history | command grep -Pi "$@"`
  # Any additional args are passed to `grep -Pi`.
  # ## See also
  # hs, hpy, hspy, hsu, hsuu
  function hsi() {
    hs "$@" -i
  }


  # # hfzf [line start num: int] [line stop num: int] [query: any]
  function hfzf() {
    local res
    local start=0
    local stop
    local -a fzfargs=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
      *)
        if isnum "$1"; then
          # If it's a number: start >> stop >> fzf query
          if [[ -z "$start" ]]; then
            start="$1"
          elif [[ -z "$stop" ]]; then
            stop="$1"
          elif [[ -z "$fzfargs" ]]; then
            fzfargs+=(-q "$1")
          else
            log.fatal "Too many arguments"
            docstring -p "$0"
            return 1
          fi
        else
          # Not a number -> fzf query
          if [[ -n "$fzfargs" ]]; then
            log.fatal "Too many arguments"
            docstring -p "$0"
            return 1
          fi
          fzfargs+=(-q "$1")
        fi
        shift
        ;;
      esac
    done
    fzfargs+=(--preview-window=hidden)
    # -l: print commands │ -r: reverse order │ -i: timestamps in yyyy-mm-dd hh:mm
    if ! res="$(builtin fc -l -r -i "$start" "$stop" | fzf "${fzfargs[@]}")"; then
      log.error "No result running 'fc -l -r -i $start $stop | fzf \${fzfargs[@]}'. $(typeset fzfargs)"
      return 1
    fi
    log.debug "$(typeset res)"
    local -i hindex
    local hdate
    local htime
    local hcmd
    read hindex hdate htime hcmd <<<"$res"
    confirm "Selected:\n${Cd}${hindex} │ ${hdate} ${htime}${Cd0}\n${Cc}${hcmd}${Cc0}\nEdit before executing?" || return 1
    fc "$hindex"
    return $?
  }

  #complete -o default -F __hfzf__comp hfzf
  #complete -o default -C 'printf "%b\n" "LINENUM_START LINENUM_STOP QUERY" 1>&2' hfzf
  #function __hfzf__comp(){ completion.generate 'LINENUM_START' 'LINENUM_STOP' 'QUERY' ; }
  complete -o default -W "[LINENUM_START] [LINENUM_STOP] [QUERY]" hfzf
  #complete -o default -C 'printf "LINENUM_START LINENUM_STOP QUERY"' hfzf
  #complete -C 'printf "%s" "${COMP_WORDS[*]}"' hfzf
  
  function hdel(){
    setopt localoptions errreturn pipefail
    local pattern="${1?Pattern required}"
    local history_file="${HISTFILE:-$HOME/.zsh_history}"
    [[ "$HISTFILE" = /dev/null ]] && history_file="$HOME/.zsh_history"
    [[ -f $history_file && -s $history_file ]] || {
      log.error "History file does not exist or is empty: $history_file. Aborting."
      return 1
    }
    mkdir -p "$HOME/.zsh_history_backups"
    local backup_file="$HOME/.zsh_history_backups/${EPOCHSECONDS}"
    cp -a "$history_file" "$backup_file"
    log.prompt "Backed up to ${backup_file}."
    local -a python_program=(
      "import re"
      "import sys"
      "with open('${history_file}', 'r+', errors='ignore') as f:"
      "    content = f.read()"
      "    orig_line_count = len(content.splitlines())"
      "    filtered = re.sub(r'(?m)^.*${pattern}.*\\n', '', content)"
      "    new_line_count = len(filtered.splitlines())"
      "    deleted_count = orig_line_count - new_line_count"
      "    if deleted_count == 0:"
      "        print('No matching lines found for pattern: ${pattern}', file=sys.stderr)"
      "        sys.exit(1)"
      "    confirm = input('Proceed deleting ${deleted_count} lines? [y/N]: ')"
      "    if confirm.lower().strip() not in ['y', 'yes']:"
      "        print('Cancelled.', file=sys.stderr)"
      "        sys.exit(1)"
      "    f.seek(0)"
      "    f.write(filtered)"
      "    f.truncate()"
      "    print(f'Deleted {deleted_count} lines from ${history_file}')"
    )
    if ! python3.13 -OBIS -c "$(printf "%s\n" "${python_program[@]}")"; then
      log.error "Python program failed. Restoring from backup."
      mv "$backup_file" "$history_file"
      return 1
    fi
    log.success "Operation completed successfully."
}
  
  # # hsub <search_extended_regex> <replace_string>
  # Replaces matches with provided string in $HISTFILE (or ~/.zsh_history if $HISTFILE is unset or /dev/null).
  function hsub(){
    setopt localoptions errreturn pipefail
    local history_file
    history_file="${HISTFILE:-$HOME/.zsh_history}"
    [[ "$HISTFILE" = /dev/null ]] && history_file="$HOME/.zsh_history"
    [[ ! -f "$history_file" || ! -s "$history_file" ]] && {
      log.error "History file does not exist or is empty: $history_file. Aborting."
      return 1
    }
    mkdir -p "$HOME/.zsh_history_backups"
    local backup_file="$HOME/.zsh_history_backups/${EPOCHSECONDS}"
    cp -a "$history_file" "$backup_file"
    log.notice "Backed up to ${backup_file}."
    command diff -q "$history_file" "$backup_file" || {
      log.error "Backup file is different from history file before modifying: $history_file vs $backup_file. Aborting."
      return 1
    }
    local -a python_program=(
      "import re"
      "import os"
      "with open('$history_file', 'r+', errors='ignore') as f:"
      "  content = re.sub(r'${1:?}', '${2:?}', f.read())"
      "  f.seek(0)"
      "  f.write(content)"
      "  f.truncate()"
    )
    python3.13 -OBIS -c "$(printf "%s\n" "${python_program[@]}")"
    local -a changed_lines
    changed_lines=($(comm -3 "$history_file" "$backup_file"))
    if [[ "${#changed_lines[@]}" -gt 0 ]]; then
      log.success "${#changed_lines} lines were changed in $history_file."
      return 0
    else
      log.warn "History file was not changed."
      return 1
    fi
  }
  
  # # hoff
  # Sets HISTFILE to /dev/null.
  function hoff(){
    [[ "$HISTFILE" = /dev/null ]] && {
      log.success "HISTFILE is already set to /dev/null."
      return 0
    }
    local original_histfile="$HISTFILE"
    export HISTFILE=/dev/null
    log.success "HISTFILE=$HISTFILE (was $original_histfile)"
  }
  
  # # hon
  # Sets HISTFILE to ~/.zsh_history.
  function hon(){
    [[ "$HISTFILE" = "$HOME/.zsh_history" ]] && {
      log.success "HISTFILE is already set to $HISTFILE."
      return 0
    }
    local original_histfile="$HISTFILE"
    export HISTFILE="$HOME/.zsh_history"
    log.success "HISTFILE=$HISTFILE (was $original_histfile)"
  }

}
