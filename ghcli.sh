#!/usr/bin/env zsh
# gh completion -s zsh > ~/dev/land/completions/_gh

# https://docs.github.com/en/rest/reference/gists#get-a-gist

# ghg-ids
# mkdir /tmp/ghgists
# for id in $(ghg-ids); do mkdir -p /tmp/ghgists/$id; ghgv $id --files > /tmp/ghgists/$id/files.txt; done

if ! isdefined gh; then
  return 1
fi

# should not include aliases to custom gh_gist until a gist id can be passed instead of GIST_DESCRIPTION_GLOB everywhere
alias ghg='gh gist'
alias ghgl='ghg list -L 900'
alias ghglg='ghg list -L 900 | command grep -i'
alias ghgv='ghg view'
alias ghge='ghg edit'
alias ghgdel='ghg del'
alias ghgcr='command gh gist create'  # because -d 'foo bar' escaping
alias ghgcl='ghg clone'

export _GHG_IDS_PATH=/tmp/land/cache/ghg-ids.txt

function .is_gid() {
  [[ $1 =~ ^[a-f0-9]{32}$ ]]
}

function :has_gid() {
  [[ $1 =~ [a-f0-9]{32}/?$ ]]
}

function :has_uppercase() {
  [[ $1 =~ [[:upper:]] ]]
}

function gh() {
  log.title "$0 $*"
  local subcmd="$1"
  shift
  case "$subcmd" in
  gist)
    local gist_subcmd="$1"  # e.g. 'view', 'edit' etc
    local first_gist_subcommand_arg="$2"  # id, '--help', description regex etc
    shift  # Shift only one time because we want to pass the rest of the args further down.

    # If first `gh gist <subcmd> <first_gist_arg>` is a gist id, or a flag, use vanilla gh gist.
    if .is_gid "$first_gist_subcommand_arg" || [[ $first_gist_subcommand_arg =~ ^--?[a-zA-Z]+ ]]; then
      log.info 'Using vanilla `gh gist`'
      vex ---just-run command gh gist "$gist_subcmd" "$@"
      return $?
    fi

    # First arg is not an id or a flag. If a custom fn exists, call it, otherwise use vanilla.
    local custom_ghg_fn="ghg-${gist_subcmd}"
    if isdefined "$custom_ghg_fn"; then
      vex ---just-run "$custom_ghg_fn" "$@"
      return $?
    fi
    log.info "No custom function found for $custom_ghg_fn. Using vanilla gh gist"
    vex ---just-run command gh gist "$gist_subcmd" "$@"
    return $?
    ;;
  *)
    vex ---just-run command gh "$subcmd" "$@"
    ;;

  esac
}


# # ghg-cached-list
function ghg-cached-list() {
  vex ---log-only-errors cached command gh gist list -L 900
}

# # ghg-ids
# Whitespace-separated ids of all gists.
function ghg-ids() {
  if ! ghg-cached-list | awk '{print $1}' | xargs; then
    log.error "Failed getting ids"
    return 1
  fi
}

# # ghg-descriptions
# Outputs single-quote wrapped descriptions of all gists.
function ghg-descriptions(){
  ghg-cached-list | awk -F'\t' '{print "'"'"'" $2 "'"'"'"}'
}

# # ghg-get-line <GIST_DESCRIPTION_GLOB>
# Automatically greps case insensitively if no uppercase letters are present.
# Utilizes ghg-cached-list.
function ghg-get-line() {
  log.title "$0 $*"
  local gist_glob="$1"
  local grep_args=("$gist_glob")
  if ! :has_uppercase "$gist_glob"; then
    grep_args+=("-i")
  fi
  local list="$(ghg-cached-list)"
  local grepped_from_list
  if ! grepped_from_list="$(command grep "${grep_args[@]}" <<<"$list")"; then
    log.fatal "$0 failed grepping ${grep_args[*]} from cached list"
    return 1
  fi
  if str.has_newline "$grepped_from_list"; then
    # Multiple gists; interactively choose one
    log.prompt "$0 '$gist_glob' yielded several results, choose one"
    local -a grepped_gists_arr
    grepped_gists_arr=("${(f)grepped_from_list}")
    local chosen_index
    chosen_index="$(input "Enter number:" --choices "1..${#grepped_gists_arr[@]}")"
    local chosen_gist_line="${grepped_gists_arr[$chosen_index]}"
    printf "%s" "$chosen_gist_line"
  else
    # Only one gist
    printf "%s" "$grepped_from_list"
  fi
  return 0
}


# # ghg-get-description <GIST_DESCRIPTION_GLOB>
function ghg-get-description(){
  log.title "$0 $*"
  local gist_glob="$1"
  shift || {
    log.fatal "$0: not enough args (Usage: $(docstring -p "$0"))"
    return 2
  }
  ghg-get-line "$gist_glob" | awk '{for (i=2; i<=NF-4; i++) printf "%s ", $i; print""}' | strip
}



# # ghg-get-id <GIST_DESCRIPTION_GLOB>
function ghg-get-id() {
  log.title "$0 $*"
  if [[ ! $1 ]]; then
    log.fatal "$0: not enough args (got ${#$})"
    return 1
  fi

  local gist_glob="$1"
  local gist_id

  if .is_gid "$gist_glob"; then
    printf "%s" "$gist_glob"
    return 0
  fi

  if :has_gid "$gist_glob"; then  # Maybe URL
    # Strip possible trailing slash
    gist_id="${gist_glob%/}"

    # Get last part of URL
    gist_id="${gist_id##*/}"

    # Assert it's a valid gist id
    .is_gid "$gist_id" || {
      log.fatal "Failed extracting gist id from URL: $gist_glob"
      return 1
    }

    printf "%s" "$gist_id"
    return 0
  fi

  local gist_line

  if ! gist_line="$(ghg-get-line "$gist_glob")"; then
    log.fatal Failed
    return 1
  fi
  gist_id="$(awk '{print $1}' <<<"$gist_line")"

  printf "%s" "$gist_id"
}

# # .ghg-view-print-one-file <FILE_FULL_CONTENT>
# Prints the content of a file without the filename title.
function .ghg-view-print-one-file(){
  local file_full_content="$1"
  local -a file_full_content_lines=( "${(f)file_full_content}" )
  local without_filename_title="${(F)file_full_content_lines[2,-1]}"
  printf "%b" "$without_filename_title"
  return 0
}

# # .ghg-view-print-multiple-files <GIST_ID> <GIST_FILES> [-o, --output OUTPUT:{json,interactive}=interactive]
function .ghg-view-print-multiple-files(){
  local gist_id
  local -a gist_files
  local output_format
  while [[ $# -gt 0 ]]; do
    case "$1" in
    -o|--output) output_format="$2"; shift ;;
    --output=*) output_format="${1#*=}";;
    *)
      if .is_gid "$1"; then
        [[ -n $gist_id ]] && {
          log.fatal "Gist id already defined: $gist_id (got $1)"
          return 1
        }
        gist_id="$1"
      else
        gist_files+=("$1")
      fi
      ;;
    esac
    shift
  done
  [[ -z $gist_id || -z $gist_files ]] && {
    log.fatal "Gist id or files were not specified"
    docstring -p "$0"
    return 1
  }
  log.debug "$(typeset gist_id gist_files)"
  case "$output_format" in
  json)
    command gh api -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" /gists/"$gist_id" \
      | jq '.files | to_entries | map({(.key): .value.content}) | add' -r
    ;;
  interactive|*)
    local selected_file
    selected_file="$(printf '%s\n' "${gist_files[@]}" | fzf --prompt='Select file to view: ')"
    [[ -n "$selected_file" ]] && {
      cached command gh gist view "$gist_id" --filename="$selected_file"
      return $?
    }
    return 1
    ;;
  esac
}

# # ghg-view <GIST_DESCRIPTION_GLOB> [gh gist view OPTIONS]
# Vanilla `gh gist view` expects a gist id, this functions allows passing a glob of description instead
# ## gh gist view options
# -f, --filename STRING       display a single file of the gist
# -r, --raw                   do not try and render markdown
# -w, --web                   open gist in browser
# ## Examples
# ```bash
# ghg-view xfce4
# ghg-view xfce4 -f xfwm4.xml
# ```
function ghg-view() {
  log.title "$0 $*"
  local gist_glob="$1"
  shift || {
    log.fatal "$0 requires at least one positional arg"
    return 2
  }
  local gist_id
  if ! gist_id="$(ghg-get-id "$gist_glob")"; then
    log.fatal Failed to get gist id of "$(typeset -p gist_glob)"
    return 1
  fi
  local -a gh_gist_view_opts=()
  local specified_filename_opt=false
  local specified_files_opt=false
  local specified_web_opt=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
    -f=*|--filename=*) specified_filename_opt=true;;
    -f|--filename) specified_filename_opt=true;;
    --files) specified_files_opt=true;;
    -w|--web) specified_web_opt=true;;
    esac
    gh_gist_view_opts+=("$1")
    shift
  done
  if [[ "$specified_web_opt" = true || "$specified_files_opt" = true ]]; then
    # These options don't require processing the output, so  we can just call the command.
    log.debug "Returning early with vanilla gh gist view because of -w or --files"
    vex cached command gh gist view "$gist_id" "${gh_gist_view_opts[@]}"
    return $?
  fi

  # As of gh version 2.61.0 (2024-11-06), because of the condition above,
  #  `gh_gist_view_opts` at this point can be either combination of empty, `--raw` or `--filename`.
  log.debug "$(typeset gh_gist_view_opts)"
  local gist_view_output="$(vex cached command gh gist view "$gist_id" "${gh_gist_view_opts[@]}" ---log-before-running ---log-only-errors)"
  
  [[ "$specified_filename_opt" = true ]] && {
    .ghg-view-print-one-file "$gist_view_output"
    return $?
  }

  local -a gist_files
  gist_files=( "${(f)"$(vex cached command gh gist view "$gist_id" --files)"}" )
  log.debug "$(typeset gist_files)"
  
  [[ "${#gist_files}" = 1 ]] && {
    .ghg-view-print-one-file "$gist_view_output"
    return $?
  }
  
  # * Multiple files
  .ghg-view-print-multiple-files "$gist_id" "${gist_files[@]}"
  return $?
}

# # ghg-del <GIST_DESCRIPTION_GLOB> [gh gist delete OPTIONS]
function ghg-del() {
  trap clearcached EXIT
  log.title "$0 $*"
  local gist_glob="$1"
  shift || {
    log.fatal "$0 requires at least one positional arg"
    return 2
  }
  local gist_id
  if ! gist_id="$(ghg-get-id "$gist_glob")"; then
    log.fatal Failed
    return 1
  fi
  confirm "Delete gist ${gist_id}?" || return 3
  command gh gist delete "$gist_id" "$@"
}

# # ghg-edit <GIST_DESCRIPTION_GLOB> [gh gist edit OPTIONS]
# ## gh gist edit options
# -f, --filename STRING       display a single file of the gist
# ## Examples
# ```bash
# ghg-edit xfce4
# ghg-edit xfce4 -f xfwm4.xml
# ```
function ghg-edit() {
  trap clearcached EXIT
  log.title "$0 $*"
  local gist_glob="$1"
  shift
  local gist_id
  if ! gist_id="$(ghg-get-id "$gist_glob")"; then
    log.fatal Failed
    return 1
  fi
  command gh gist edit "$gist_id" "$@"
}

# # ghg-diff <ARG> [OPTION...]
# ## Usage
# ```bash
# ghg-diff <GIST DESCRIPTION GLOB THAT IS ALSO FILE NAME>
# ghg-diff <GIST DESCRIPTION GLOB> <FILE NAME>
# ghg-diff <GIST DESCRIPTION GLOB> <-{f,l} FILE NAME> <-{f,l} FILE NAME>
# ```
# ## Options
# `-t, --difftool <DIFFTOOL>`
# `-c, --ignore-comments`
function ghg-diff() {
  log.title "$0 $*"
  local gist_glob="$1"
  shift || {
    log.fatal "$0 requires at least one arg (got $#)"
    return 2
  }
  local local_filepath gist_filename
  local difftool ignore_comments=false
  local difftool_args=() # pass -y in ghg-update when implemented
  local builtin_diff_args=(
    --ignore-all-space
    --ignore-space-change
    --ignore-blank-lines
    -u # unified
    --strip-trailing-cr
  )
  [[ $PLATFORM == LINUX ]] && builtin_diff_args+=(--ignore-trailing-space --suppress-blank-empty)



  while [[ $# -gt 0 ]]; do
    case "$1" in
     -t=*|--difftool=*) difftool=${1#*=};;
     -t|--difftool) difftool="$2"; shift ;;
     -c|--ignore-comments) ignore_comments=true;;
     -f=*|--gist-filename=*) gist_filename=$(basename "${1#*=}");;
     -f|--gist-filename) gist_filename=$(basename "$2"); shift ;;
     -l=*|--local-filepath=*) local_filepath=${1#*=};;
     -l|--local-filepath) local_filepath="$2"; shift ;;
    *)
      if [[ -z $local_filepath && -z $gist_filename ]]; then
        local_filepath="$1"
        gist_filename="$1"
        shift
      else
        log.fatal "local_filepath and/or gist_filename already defined. Too many positional arguments: $1"
        return 3
      fi
      ;;
    esac
    shift
  done

  if [[ -z $local_filepath && -z $gist_filename ]]; then
    local_filepath="$gist_glob"
    gist_filename="$gist_glob"
  elif [[ -z $local_filepath ]]; then
    local_filepath="$gist_filename"
  elif [[ -z $gist_filename ]]; then
    gist_filename="$(basename "$local_filepath")"
  fi

  # * difftool
  if [[ ! $difftool ]]; then
    if [[ "$SSH_CONNECTION" ]]; then
      if isdefined delta; then
        function do_diff() { diff "${builtin_diff_args[@]}" "$@" | delta; }
      else
        function do_diff() { diff "${builtin_diff_args[@]}" "$@"; }
      fi
    else # not in ssh, but $difftool has no value. pycharm > vscode > delta > builtin diff
      if isdefined pycharm; then
        function do_diff() { pycharm diff "$@"; }
      elif isdefined code; then
        function do_diff() { code --disable-extensions --diff "$@"; }
      elif isdefined delta; then
        function do_diff() { diff "${builtin_diff_args[@]}" "$@" | delta; }
      else
        function do_diff() { diff "${builtin_diff_args[@]}" "$@"; }
      fi
    fi
  else # not in ssh, and $difftool has value
    if [[ $difftool == pycharm ]]; then
      # todo: when difftool_args is implemented, this is unnecessary
      function do_diff() { pycharm diff "$@"; }
    elif [[ $difftool == code ]]; then
      # todo: when difftool_args is implemented, this is unnecessary
      function do_diff() { code -r --diff "$@"; }
    else
      function do_diff() { eval "$difftool" "$@"; }
    fi
  fi
  log.debug "$(typeset -p gist_glob local_filepath gist_filename difftool) | args: $* | do_diff: $(where do_diff | bat -l bash -pp --color=always)"

  # * Pre-checks
  if [[ ! -f $local_filepath ]]; then
    log.fatal "Not a file on local filesystem: $local_filepath"
    return 1
  fi

  # Make it absolute because we're cding later
  local_filepath="$(realpath "$local_filepath")"

  # * Get gist content and write to tmp file
  local gist_id
  if ! gist_id="$(ghg-get-id "$gist_glob")"; then
    log.fatal Failed
    return 1
  fi
  log.debug "gist_id: $gist_id"
  mkdir -p /tmp/"$gist_id" || return 1
  local tmp_gist_file=/tmp/"$gist_id/$gist_filename"
  if ! vex command gh gist view "$gist_id" -f "$(printf "%q" "$gist_filename")" >"$tmp_gist_file"; then
    log.fatal Failed
    return 1
  fi

  # * Show diff
  if diff "${builtin_diff_args[@]}" "$local_filepath" "$tmp_gist_file"; then
    log.success "Gist and local file are identical"
    return 0
  fi
  if $ignore_comments; then
    do_diff <(command grep -vE '^\s*#' "$local_filepath") <(command grep -vE '^\s*#' "$tmp_gist_file")
  else
    do_diff "$local_filepath" "$tmp_gist_file"
  fi
  return $?
}

function ghg-get-url() {
  local gist_id
  gist_id="$(ghg-get-id "$1")"
  local exitcode=$?
  if [[ $exitcode == 0 ]]; then
    printf "%s" "https://gist.github.com/giladbarnea/${gist_id}/raw"
  fi
  return $exitcode
}

# # ghg-dl <ID OR GLOB> [-o, --outpath PATH/'-'] [-w, --overwrite]
# If `-o` is unspecified, writes to ./{GIST_ID}. Can be '-' for stdout.
# If `-w` is specified, and out path exists, overwrites it.
function ghg-dl() {
  log.title "$0 $*"

  local gist_glob gist_id outpath raw_content_untrimmed raw_content
  local -i file_count
  local -a gist_files
  local overwrite=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
    -o|--outpath)
      outpath="$2"
      log.debug "$(typeset outpath)"
      shift
      ;;
    -w|--overwrite)
      overwrite=true
      # Consider wget --unlink
      log.debug "$(typeset overwrite)"
      ;;
    *)
      if [[ -n $gist_glob ]]; then
        log.fatal "Too many positional arguments given. Usage:\n$(docstring -p "$0")"
        return 2
      fi
      gist_glob="$1"
      ;;
    esac
    shift
  done

  if [[ -z $gist_glob ]]; then
    log.fatal "Not enough arguments given, gist_glob is missing. Usage:\n$(docstring -p "$0")"
    return 2
  fi
  gist_files=("${(f)"$(ghg-view "$gist_glob" --files)"}")
  file_count="${#gist_files[@]}"
  raw_content="$(ghg-view "$gist_glob" -r)"

  log.debug "$(typeset gist_files file_count)"


  # * One file
  if [[ "$file_count" -le 1 ]]; then
    local filename="${gist_files[1]}"
    if [[ ! "$outpath" ]]; then
      outpath="$filename"
    elif [[ -d "$outpath" ]]; then
      outpath="$outpath/$filename"
    elif [[ "$outpath" == "-" ]]; then
      outpath=/dev/stdout
    fi

    log.debug "$(typeset outpath)"
    if [[ -f "$outpath" ]]; then  # False if stdout
      if [[ $overwrite = true ]]; then
        log.notice "Overwriting '${outpath}'"
        rm -v "$outpath" || return 1
      else
        confirm "'${outpath}' exists. Overwrite?" || return 3
        rm -v "$outpath" || return 1
      fi
    fi
    printf "%s" "$raw_content" >"$outpath"
    log.success "Wrote to '${outpath}'"
    return $?
  fi

  # * Multiple files
  log.warn "Multiple files in gist, code looks sketchy."

  # If passed a file, asks whether to use its dirname, otherwise prompts custom path
  function validate_or_confirm_mkdir_outpath() {
    local _outpath="$1"
    if [[ -d $_outpath ]]; then
      printf "%s" "$_outpath"
      return 0
    fi
    if [[ ! $_outpath ]]; then
      ## Bad arg
      return 2
    fi

    if [[ ! -e $_outpath ]]; then
      ## Does not exist; maybe create
      if ! confirm "$_outpath does not exist, mkdir -p '${_outpath}'?"; then
        return 3
      fi
      vex ---log-only-errors \
        "mkdir -p '${_outpath}'" || return 1
      printf "%s" "$_outpath"
      return 0
    fi

    ## Exists but not a dir
    log.warn "_outpath=$_outpath was specified, it exists but not a directory"
    local _tmp="$(realpath "$(dirname "$_outpath")")"
    local user_answer
    user_answer="$(input "Gist has multiple files, _outpath must be a dir. Use $_tmp?" --choices='[y]es, [q]uit, [c]ustom')"
    case "$user_answer" in
    q)
      return 3
      ;;
    y)
      _outpath="$_tmp"
      printf "%s" "$_tmp"
      return 0
      ;;
    c)
      _tmp="$(input "Insert dir path")"
      printf "%s" "$_tmp"
      return 0
      ;;
    esac

  }

  # * $outpath was specified, do checks, and if valid (a dir), cd into it
  if [[ "$outpath" ]]; then
    local exitcode
    # Twice because in case a new outpath was set and created, validate the new one
    outpath="$(validate_or_confirm_mkdir_outpath "$(validate_or_confirm_mkdir_outpath "$outpath")")"
    exitcode=$?
    if [[ $exitcode != 0 ]]; then return $exitcode; fi
    builtin cd "$outpath" || return 1
  fi

  declare -A linenum_to_filename=()
  local linenums=()
  local linenums_sorted=()
  local any_failed=false
  local filename linenum

  # * Get each file's line num in raw_content (populate linenum_to_filename)
  for filename in "${gist_files[@]}"; do
    linenum=$(cat -n <<<"$raw_content" | command grep -E "\s+$filename" | command grep -Po '\d+')
    ((linenum + 2)) # File name, empty line
    log.debug "filename: ${filename} | linenum: ${linenum}"
    linenums+=("$linenum")
    linenum_to_filename[$linenum]="$filename"
  done
  if [[ "$SHELL" = *zsh ]]; then
    linenums_sorted=($(print -o "${linenums}"))
  else
    linenums_sorted=($(tr ' ' $'\n' <<<"$linenums" | sort))
  fi

  local current_linenum_index next_linenum_index next_linenum file_content rel_linenum_end
  for linenum in ${linenums_sorted[@]}; do
    current_linenum_index="${linenums_sorted[(I)$linenum]}"
    next_linenum_index="$((current_linenum_index + 1))"
    log.debug "linenum: ${linenum} | current_linenum_index: ${current_linenum_index} | next_linenum_index: ${next_linenum_index}"
    next_linenum="${linenums_sorted[$next_linenum_index]}"
    if [[ $next_linenum ]]; then
      rel_linenum_end="$((next_linenum - linenum - 2))"
      file_content="$(echo -E "$raw_content" | tail -n +"$linenum" | head -"${rel_linenum_end}")"
      log.debug "next_linenum: ${next_linenum} | rel_linenum_end: ${rel_linenum_end}"
    else
      # shellcheck disable=SC2034
      file_content="$(echo -E "$raw_content" | tail -n +"$linenum")"
    fi
    filename="${linenum_to_filename[$linenum]}"
    log.debug "filename: ${filename}"
    if [[ -f $filename ]]; then
      if $overwrite || confirm "'$filename' exists, overwrite?"; then
        log.warn "overwriting $filename"
        rm "$filename"
      else
        continue
      fi
    fi
    if ! vex "echo -E \"\$file_content\" > $filename"; then
      any_failed=true
    fi
  done
  builtin cd -
  return $any_failed

}

# # ghg-update <ARG> [OPTION...]
# ## Usage
# ```bash
# ghg-update <GIST DESCRIPTION GLOB THAT IS ALSO FILE PATH>
# ghg-update <GIST DESCRIPTION GLOB> <FILE PATH>
# ghg-update <GIST DESCRIPTION GLOB> <-f|l FILE NAME> <-f|l FILE NAME>
# ```
function ghg-update() {
  trap clearcached EXIT
  log.title "$0 $*"
  local oldpwd="$PWD"
  if [[ -z $1 ]]; then
    log.fatal "$0 requires at least one arg (got $#)"
    return 2
  fi
  local gist_glob="$1"
  shift || return 1
  [[ $gist_glob == */* ]] && {
    confirm "gist_glob '$gist_glob' contains slashes, use basename? ('$(basename "$gist_glob")')" &&
      gist_glob="$(basename "$gist_glob")"
  }
  local local_filepath
  local gist_filename
  if [[ -z $1 ]]; then
    # ghg-update <GIST DESCRIPTION GLOB THAT IS ALSO FILE NAME>
    local_filepath="$gist_glob"
    gist_filename="$(basename "$local_filepath")"
  elif [[ $1 != -* ]]; then
    # ghg-update <GIST DESCRIPTION GLOB> <FILE NAME>
    local_filepath="$1"
    gist_filename="$(basename "$1")"
    shift
  else
    if isdefined zparseopts; then
      zparseopts -D -E - f:=gist_filename l:=local_filepath || {
        builtin cd "$oldpwd"
        return 1
      }
      local_filepath="${local_filepath[2]}"
      gist_filename="${gist_filename[2]}"
      if [[ ! $local_filepath && ! $gist_filename ]]; then
        log.fatal "Must specify at least -l local_filepath or -f gist_filename"
        builtin cd "$oldpwd"
        return 1
      fi
      if [[ ! ${local_filepath} ]]; then
        local_filepath="$gist_filename"
      elif [[ ! ${gist_filename} ]]; then
        gist_filename="$(basename "$local_filepath")"
      fi
    else
      log.fatal "zparseopts not a command, not implemented parsing args"
      builtin cd "$oldpwd"
      return 1
    fi
  fi

  # * Pre-checks
  log.debug "gist_glob: $gist_glob | local_filepath: $local_filepath | gist_filename: $gist_filename"
  if [[ ! -f $local_filepath ]]; then
    log.fatal "Not a file on local filesystem: $local_filepath"
    builtin cd "$oldpwd"
    return 1
  fi

  # Make it absolute because we're cding later
  local_filepath="$(realpath "$local_filepath")"

  # * Get gist id
  local gist_line gist_id gist_description
  if ! gist_line="$(ghg-get-line "$gist_glob")"; then
    log.fatal Failed
    builtin cd "$oldpwd"
    return 1
  fi

  gist_id="$(ghg-get-id "$gist_glob")"
  gist_description="$(ghg-get-description "$gist_id")"

  if ghg-diff "$gist_id" -f "$gist_filename" -l "$local_filepath" -t diff; then
    log.info "No changes to update"
    builtin cd "$oldpwd"
    return 0
  fi

  log.megatitle "Local $local_filepath and gist $gist_filename are different. Review before update:" -x
  log.prompt "Gist filename: $gist_filename\nLocal filepath: $local_filepath\nDescription: $gist_description"

  confirm "Update gist?" || return 3

  local gh_gist_edit_exitcode
  command gh gist edit "$gist_id" -f "$gist_filename" "$local_filepath"
  gh_gist_edit_exitcode="$?"
  if [[ $gh_gist_edit_exitcode == 0 ]]; then
    log.success "Updated gist $gist_id"
  else
    log.fatal "Failed to update gist $gist_id (exit code $gh_gist_edit_exitcode)"
  fi
  builtin cd "$oldpwd"
  return $gh_gist_edit_exitcode

}

# # ghg-clone <GIST_DESCRIPTION_GLOB> [gh gist clone OPTIONS]
function ghg-clone(){
  log.title "$0 $*"
  local gist_glob="$1"
  shift || {
    log.error "$0 requires at least one positional arg"
    return 2
  }
  local gist_id
  if ! gist_id="$(ghg-get-id "$gist_glob")"; then
    log.error Failed
    return 1
  fi
  local -i clone_exitcode
  command gh gist clone "$gist_id" "$@"
  clone_exitcode=$?
  if [[ $clone_exitcode = 0 ]]; then
    confirm "cd into ${gist_id}?" || return 0
    cd "$gist_id"
    return $?
  fi
  return $clone_exitcode
}

# # ghg-run <GIST_DESCRIPTION_GLOB> [ghg-clone args...] [-- executable file args...]
# ghg-run convert_aistudio_chat -- file.json
function ghg-run(){
  log.title "$0 $*"
  local clone_destination="$(mktemp -d)"
  local -a ghg_clone_args
  local -a file_args
  
  
  local -a args
  local parse_executable_file_args=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --) parse_executable_file_args=true ;;
      *) 
        case "$parse_executable_file_args" in
          false) ghg_clone_args+=("$1") ;;
          true) file_args+=("$1") ;;
        esac ;;
    esac
    shift
  done
  
  ghg-clone "${ghg_clone_args[@]}" "$clone_destination" || return 1
  local -a cloned_files=(
    $clone_destination/**(.)
  )
  
  local file
  # Happy path: gist has one file. Run it.
  if [[ ${#cloned_files[@]} -eq 1 ]]; then
    file="${cloned_files[1]}"
    if is_interactive && ! is_piped; then
      confirm "Run ${Cc}${file} \"${file_args[*]}\"${Cc0}?" || return 1
    fi
    chmod +x "$file"
    $file "${file_args[@]}"
    return $?
  fi
  
  # Multiple files: interactively ask which to run.
  if ! is_interactive || is_piped; then
    log.error "Not interactive or stdin is unavailable, aborting"
    return 1
  fi
  
  file="$(input "Run which file?" --choices "${cloned_files[@]}")"
    
}

# # gh-pr-merge-soon <PR_NUMBER> [TIME_IN_FUTURE]
# ## Usage
# ```sh
# gh-pr-merge-soon 87 [2h][30m][10s]
# gh-pr-merge-soon 87 19:00
# ```
function gh-pr-merge-soon(){
  setopt localoptions errreturn
  local pr_number="$1"
  local -i unixtime_in_future
  if [[ "$2" = *:* ]]; then
    local human_absolute_time_in_future="$2"
    unixtime_in_future="$(gdate -d "$human_absolute_time_in_future" +%s)"
  else
    local relative_time_in_future="$2"  # E.g. '30m'
    local relative_time_seconds relative_time_minutes relative_time_hours
    if [[ "$relative_time_in_future" =~ ^([0-9]+)h$ ]]; then
      relative_time_hours="${match[1]}"
    elif [[ "$relative_time_in_future" =~ ^([0-9]+)m$ ]]; then
      relative_time_minutes="${match[1]}"
    elif [[ "$relative_time_in_future" =~ ^([0-9]+)s$ ]]; then
      relative_time_seconds="${match[1]}"
    fi
    local relative_time_in_future_gdate_compatible="now + "
    if [[ "$relative_time_hours" ]]; then
      relative_time_in_future_gdate_compatible+="${relative_time_hours} hours"
    fi
    if [[ "$relative_time_minutes" ]]; then
      relative_time_in_future_gdate_compatible+="${relative_time_minutes} minutes"
    fi
    if [[ "$relative_time_seconds" ]]; then
      relative_time_in_future_gdate_compatible+="${relative_time_seconds} seconds"
    fi
    unixtime_in_future="$(gdate -d "$relative_time_in_future_gdate_compatible" +%s)"
  fi
  while true; do
    if [[ "$(gdate +%s)" -ge "$unixtime_in_future" ]]; then
      notif.info "⏲️ PR #$pr_number time is up! Awaiting approval in terminal"
      confirm 'Merge?' || return 1
      command gh pr merge "$pr_number"
      return $?
    fi
    echo -n '\x1b[2J'
    log.prompt "PR #$pr_number will be merged at $(gdate -d "@$unixtime_in_future") ($((unixtime_in_future - $(gdate +%s))) seconds left)"
    command gh pr view "$pr_number"
    sleep 10 
  done

}
