#!/usr/bin/env zsh

# https://github.com/mskar/setup/blob/5d9dddd447a05e8d866b9c09b06a085f02e41bd3/.zshrc    very advanced with fzf
# keep in mind:
# --bind 'ctrl-space:toggle-preview'
# --bind 'f1:execute(less -f {}),ctrl-y:execute-silent(echo {} | pbcopy)+abort'
# f1:refresh-preview

# export FZF_CTRL_P_OPTS="--preview 'tree -C {} | head -200'"
export FZF_BINDINGS=(

  # --bind "'down:down+execute(. fzf.sh; source $SCRIPTS/zenity.sh; notif.success \"export | grep FZF_PREVIEW_LINES\")'"

  # alt-e: edit with cursor
  --bind "'alt-e:execute-silent(. fzf.sh; .fzf-open-in-cursor {})'"

  # ?: preview
  --bind "'?:preview(. fzf.sh; .fzf-preview {})'"

  # alt-c: copy
  --bind "'alt-c:execute(. fzf.sh; .fzf-copy-to-clipboard {})'"

  # ctrl-alt-c: copy absolute path
  --bind "'ctrl-alt-c:execute(. fzf.sh; .fzf-copy-to-clipboard {} -a)'"

  # alt-backspace: mv to /tmp/.trash
  --bind "'alt-bspace:execute(. fzf.sh; .fzf-move-to-trash {})'"

  # alt-?: print these bindings
  # --bind "'alt-?:preview(. fzf.sh; .fzf-print-bindings > /tmp/fzf-bindings; .fzf-preview /tmp/fzf-bindings)'"
   --bind "'alt-?:preview(. fzf.sh; .fzf-preview <(.fzf-print-bindings))'"

  # alt-d: reload to search dirs
  --bind "'alt-d:reload(fd --hidden --no-ignore --type d)'"

  # alt-f: reload to search files
  --bind "'alt-f:reload(fd --hidden --no-ignore --type f)'"

  # alt-x: reload to search without dir/file filtering
  --bind "'alt-x:reload(fd --hidden --no-ignore)'"

   # +: reload with unlimited max-depth
   --bind "'+:reload(fd --hidden --no-ignore --max-depth=999)'"
   # --bind "'load:reload(fd --hidden --no-ignore --max-depth=6)'"
)

export FZF_PREVIEW_WINDOW_OPTS='down,75%:wrap'
export FZF_DEFAULT_COMMAND='fd --hidden --no-ignore --exclude .git'
export FZF_DEFAULT_OPTS="--preview-window=$FZF_PREVIEW_WINDOW_OPTS --tiebreak=length,end,begin,index --border=none --cycle --reverse --exit-0 --select-1 --inline-info --ansi --tabstop=2 --keep-right --scroll-off=1 --no-bold ${FZF_BINDINGS[*]}"

# alt-backspace
function .fzf-move-to-trash(){
  local target="$1"

  if trash -v --stopOnError "$target"; then
    notif.success "Moved to trash successfully: $target"
  else
    notif.error "Failed moving to trash: $target"
  fi
}

# alt-[ctrl-]c
# # .fzf-copy-to-clipboard <PATH> [-a]
# `-a` to copy absolute path
function .fzf-copy-to-clipboard(){
  if [[ "$2" == -a ]]; then
    local target="$(realpath "$1")"
  else
    local target="$1"
  fi
  # export ZENITY_DO_LOG=false
  # if [[ -z "$DISPLAY" ]]; then
  #  export DISPLAY=:0
  #  export DISPLAY=:1
  # fi
  if clipcopy "$target"; then
    notif.success "copied successfully: $target" --bg
  else
    notif.error "failed copying: $target" --bg
  fi
}

# alt-e
function .fzf-open-in-cursor(){
  local target="$1"
  if cursor -r "$target"; then
    notif.success "Opened in Cursor: $target"
  else
    notif.error "Failed opening in Cursor: $target"
  fi
}

# alt-?
function .fzf-preview(){
  # Available env vars:
  # $FZF_PREVIEW_LINES, $FZF_PREVIEW_COLUMNS, $FZF_PREVIEW_TOP, $FZF_PREVIEW_LEFT
  local target="$1"
  # If it's a dir, use `tree`
  if [[ -d "$target" ]]; then
    if [[ "$PLATFORM" == WIN ]]; then
      tree "$target"
    else
      if command -v tree &>/dev/null; then
      	tree -C "$target"
      elif command -v eza &>/dev/null; then
        local eza_args=(
          --classify  # file types (-F)
          --all       # .dot (-a)
          --header    # Permissions Size etc (-h)
          --long      # table (-l)
          --group-directories-first
          --icons
          --sort=modified
          --tree
        )
        [[ -d "${target}/.git" ]] && eza_args+=(--git)
      	eza "${eza_args[@]}" "$target"
      else
      	ls -Flath --group-directories-first --color=auto --icons "$target"
      fi
    fi
  else # If it's readable (a file, or a filedescriptor), use `bat`.
    if [[ ! -r "$target" ]]; then
      notif.error "No read perms for $target"
      return 1
    fi
		bat --paging=always --style=numbers --color=always "$target"
    return $?

  fi
}

# alt-?
function .fzf-print-bindings(){
	# shellcheck disable=SC2300
	echo "${$(command grep -Po "([[:lower:]]+-.|[^[:alpha:]]):[^']+" <<< "$FZF_BINDINGS")//. fzf.sh; }"
}

# # fzfx [OPTIONS...] [QUERY]
# # fzfx [-d,-f] [-i,+i] [-c,--copy-res=false] [-p,--preview=false] [--max-depth MAX_DEPTH] [--min-depth MIN_DEPTH] [--exact-depth EXACT_DEPTH] [--retry-deeper={'respect-user-esc', 'always', 'never'}] [[-q] QUERY]
# ## Options
# Without args is just `fzf` that echoes result (if exited ok).
# `-d` and `-f` are for `fd` to search dirs or files, respectively.
# `-p`, `--preview` turns on side-preview (`bat` if file, `tree` if dir).
# `-c`, `--copy-res` copies the result to clipboard.
# Case is "smart" by default, but can be forced to:
# `-i`    Case insensitive
# `+i`    Case sensitive
# ## Supported fd options (depth)
# `--max-depth` `--min-depth` `--exact-depth`
function fzfx() {
  log.title "fzfx($*)"
  local -a raw_args=("$@")  # For recursion later.
  local query
  local show_preview=false

  # This is ok even if no -p arg, because applies to preview key bind
  local fzf_flags=(--preview-window="$FZF_PREVIEW_WINDOW_OPTS")
  local copy_res=false
  local retry_deeper="respect-user-esc"
  local max_depth min_depth exact_depth
  local temp_fzf_command="$FZF_DEFAULT_COMMAND"
  while [[ $# -gt 0 ]]; do
    case "$1" in
    # * fd args
    -d) temp_fzf_command="$FZF_DEFAULT_COMMAND --type d" ;;
    -f) temp_fzf_command="$FZF_DEFAULT_COMMAND --type f" ;;
    --max-depth) max_depth="$2" ; shift ;;
    --max-depth=*) max_depth="${1#*=}" ;;
    --min-depth) min_depth="$2" ; shift ;;
    --min-depth=*) min_depth="${1#*=}" ;;
    --exact-depth) exact_depth="$2" ; shift ;;
    --exact-depth=*) exact_depth="${1#*=}" ;;
    --retry-deeper) retry_deeper="$2" ; shift ;;
    --retry-deeper=*) retry_deeper="${1#*=}" ;;
    # * case
    -i)
      # -i: case insensitive
      fzf_flags=(-i) ;;
    +i)
      # +i: case sensitive
      fzf_flags=(+i) ;;
    # * misc
    -p|--preview) show_preview=true ;;
    -c|--copy-res) copy_res=true ;;
	  -q) query="$2" ; shift ;;
    # * defaults
    -*)
      log.debug "added $1 to \$fzf_flags"
	    fzf_flags+=("$1") ;;
    *)
      # Convenience to also support `fzfd foo` instead of `fzfd -q foo`
      if [[ "$query" ]]; then
        log.warn "Query already set to '$query', but got '$1' as well. Ignoring."
      else
        query="$1"
      fi ;;
    esac
    shift
  done

  # ** Prepare fzf (fd) command
  [[ -n "$min_depth" ]] && temp_fzf_command+=" --min-depth=$min_depth"
  [[ -n "$exact_depth" ]] && temp_fzf_command+=" --exact-depth=$exact_depth"
  [[ -n "$max_depth" ]] && temp_fzf_command+=" --max-depth=$max_depth"
  log.debug "$(typeset query) | $(typeset fzf_flags) | $(typeset copy_res) | $(typeset show_preview) | $(typeset temp_fzf_command)"
  if [[ "$show_preview" = true ]]; then
    fzf_flags+=(--ansi --preview ". fzf.sh; .fzf-preview {}")
  fi

  local -i exitcode
  local res
  [[ -n "$query" ]] && fzf_flags+=(-q "$query")
  res="$(FZF_DEFAULT_COMMAND="$temp_fzf_command" fzf "${fzf_flags[@]}")"
  exitcode=$?
  log.debug "fzf output: $res (code $exitcode)"
  if [[ "$exitcode" == 0 && -n "$res" && "$copy_res" = true ]]; then
    # fzf ok, res is not empty, copy_res is true and cmd checks
    copy -r "$res"
  fi

  [[ "$exitcode" == 0 ]] && {
    echo "$res"
    return 0
  }

  if [[ ! "$max_depth" && ! "$exact_depth" ]] || [[ "$max_depth" -ge 12 || "$exact_depth" -ge 12 ]]; then
    # If no depth options were specified, and assumiing that FZF_DEFAULT_COMMAND doesn't have any depth options,
    #  then no results were found with infinite depth.
    return $exitcode
  fi
  case "$retry_deeper" in
    respect-user-esc) [[ "$exitcode" = 130 ]] && return 130 ;;
    always) : ;;
    never) return $exitcode ;;
    *)
      log.error "Invalid value for --retry-deeper: ${retry_deeper}. Usage:\n$(docstring "$0")"
      return 1 ;;
  esac

  local log_suffix
  local -a filtered_raw_args
  if [[ "$max_depth" ]]; then
    exact_depth=$((max_depth+1))
    [[ -n "$min_depth" ]] && log_suffix="min_depth=$min_depth and"
    log_suffix+="max_depth=$max_depth"

    # Filter max and min depth from raw_args
    local -i i=1
    while [[ $i -le ${#raw_args[@]} ]]; do
      if [[ "${raw_args[$i]}" == --max-depth || "${raw_args[$i]}" == --min-depth ]]; then
        ((i+=2))
      elif [[ "${raw_args[$i]}" == --max-depth=* || "${raw_args[$i]}" == --min-depth=* ]]; then
        ((i++))
      else
        filtered_raw_args+=("${raw_args[$i]}")
        ((i++))
      fi
    done

  else
    log_suffix="exact_depth=$exact_depth"

    # Filter exact depth from raw_args
    local -i i=1
    while [[ $i -le ${#raw_args[@]} ]]; do
      if [[ "${raw_args[$i]}" == --exact-depth ]]; then
        ((i+=2))
      elif [[ "${raw_args[$i]}" == --exact-depth=* ]]; then
        ((i++))
      else
        filtered_raw_args+=("${raw_args[$i]}")
        ((i++))
      fi
    done

    exact_depth=$((exact_depth+1))
  fi

  log.prompt "Retrying with exact_depth=$exact_depth since no results were found with $log_suffix"
  fzfx "${filtered_raw_args[@]}" --exact-depth="$exact_depth"
}

function fzff() {
  fzfx -f "$@"
}
function fzfd() {
  fzfx -d "$@"
}


# # fzftext <QUERY> [PATH=.]
# Fuzzy search text in current directory.
function fzftext() {
  rg --line-number --no-messages "${2:-.}" | \
    fzf \
      -q "$1" \
      --ansi \
      --preview '
        # Split the ripgrep output into components
        local file line content
        IFS=: read -r file line content <<< {}
        
        # Calculate offset
        local offset=$(((LINES-16)/2))
        
        # Calculate line range for context
        local start=$((line > offset ? line - offset : 1))
        
        local end=$(($(wc -l < "$file") - 1))
        end=$((end > line + offset ? line + offset : end))

        # Show file preview with context using bat
        bat \
          --color=always \
          --highlight-line $line \
          --line-range $start:$end \
          $file
      ' \
      --preview-window='down,wrap'
}

# # fzftext <QUERY> [PATH=.]
# Fuzzy search text in current directory.
function fzftext2() {
  rg --line-number --no-messages "${2:-.}" | \
    fzf \
    -q "$1" \
    --ansi \
    --delimiter : \
    --preview 'bat --style=full --color=always --highlight-line {2} {1}' \
    --preview-window '~3,+{2}+3/2,down,wrap'
}

function cdfzf() {
  local res
  res="$(fzfx "$@")" || return $?
  cd "$res"
}
