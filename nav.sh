#!/usr/bin/env bash
# sourced after inspect, pyfns, arr, str, tools

[[ "$CD_PATCH" = true ]] && {

  # # cd <DIRNAME> [OPTIONS]
  # ## OPTIONS:
  #  - --ls[=true]
  #  - --show-git-status[=true]
  #  - --{fzf-on-fail[=false],shallow-search-on-fail[=true]}
  #        # Mutually exclusive; --fzf-on-fail overrides --shallow-search-on-fail.
  #  - -q,--quiet[=false]                  Equivalent to passing all params as false.
  # shellcheck disable=SC2154,SC2028
  function cd() {
    setopt localoptions nowarncreateglobal &>/dev/null || true
    local -i builtin_cd_exitcode
    local do_ls=true
    local show_git_status=true
    local fzf_on_fail=false
    local shallow_search_on_fail=true
    local targetdir
    declare -a implicit_path_prefixes=(
      "$HOME"/dev
      "$HOME"
    )

    # *** Argument Parsing
    while [[ $# -gt 0 ]]; do
      case "$1" in
      -q | --quiet)
        do_ls=false
        show_git_status=false
        fzf_on_fail=false
        shallow_search_on_fail=false
        ;;
      --quiet=*)
        do_ls=false
        show_git_status=false
        fzf_on_fail=false
        shallow_search_on_fail=false
        ;;

      --ls) do_ls=true ;;
      --ls=*) do_ls="${1#--ls=}" ;;

      --show-git-status)
        show_git_status=true
        ;;
      --show-git-status=*)
        show_git_status="${1#--show-git-status=}"
        ;;

      --fzf-on-fail) fzf_on_fail=true ;;
      --fzf-on-fail=*) fzf_on_fail="${1#--fzf-on-fail=}" ;;

      --shallow-search-on-fail) shallow_search_on_fail=true ;;
      --shallow-search-on-fail=*) shallow_search_on_fail="${1#--shallow-search-on-fail=}" ;;

      # Treat multiple positional args as a single target dir with spaces
      *) [[ "$targetdir" ]] && targetdir+=" $1" || targetdir="$1" ;;
      esac
      shift
    done

    # *** Argument Validation
    if [[ "$fzf_on_fail" = true && "$shallow_search_on_fail" = true ]]; then
      shallow_search_on_fail=false
    fi

    # Replace tilda with $HOME
    targetdir="${targetdir/'~'/$HOME}"

    if [[ ! "$targetdir" || "$targetdir" == . ]]; then
      targetdir="$PWD"
    elif [[ "$targetdir" != -* && ! -e "$targetdir" ]]; then
      # * If targetdir does not exist (and is not -*), try to find it in implicit_path_prefixes
      local implicit_path_prefix
      for implicit_path_prefix in "${implicit_path_prefixes[@]}"; do
        if [[ -e "$implicit_path_prefix/$targetdir" ]]; then
          targetdir="$implicit_path_prefix/$targetdir"
          break
        fi
      done
    fi

    # When targetdir is not explicitly absolute nor explicitly relative (excluding -* special cases),
    # builtin cd complains unless explicitly prepended with ./
    [[ "$targetdir" != /* && "$targetdir" != ./* && "$targetdir" != -* ]] && targetdir="./${targetdir}"

    # *** cd into dir
    builtin cd "${targetdir}" 2>/dev/null
    builtin_cd_exitcode=$?
    if [[ $builtin_cd_exitcode == 0 ]]; then
      # ** Builtin cd succeeded; show interesting information (no flow control)
      # * ls
      [[ "$do_ls" = true && "$PWD" != "$HOME" ]] && .do-ls

      # * git status / diff prompt, and branch / log print
      [[ "$show_git_status" = true && "$PWD" != "$HOME" && -d "$PWD/.git" ]] && .handle-git-repo

      return 0
    fi

    # ** Builtin cd failed; maybe file -> recurse.
    if [[ -f "$targetdir" ]]; then
      local -i handle_dest_is_a_file_exitcode user_declined_code=100
      .handle-dest-is-a-file "$targetdir"
      handle_dest_is_a_file_exitcode=$?
      [[ "$handle_dest_is_a_file_exitcode" != "$user_declined_code" ]] &&
        return $handle_dest_is_a_file_exitcode
    fi

    ## Reaching here means either:
    # 1. user declined .handle-dest-is-a-file, or
    # 2. 'builtin cd $targetdir' failed
    if [[ "$shallow_search_on_fail" = true ]]; then
      local -i shallow_search_exitcode
      local shallow_search_result
      if ! shallow_search_result="$(.exact-shallow-search-current-dir "${targetdir#./}")"; then
        log.warn "Failed ${Cc}builtin cd \"${targetdir}\"${Cc0} and subsequent shallow-searching for $targetdir; returning ${builtin_cd_exitcode}."
        return $builtin_cd_exitcode
      fi
      if [[ "$shallow_search_exitcode" == 0 && -n "$shallow_search_result" ]]; then
        builtin cd "$shallow_search_result"
        return $?
      fi
    fi

    if [[ "$fzf_on_fail" = false ]]; then
      return $builtin_cd_exitcode
    fi

    # ** fzf on fail -> recurse
    print_hr
    log.warn "Failed ${Cc}builtin cd \"$targetdir\"${Cc0}. Trying to fzfd it..."
    local fzfd_result fzfd_exitcode
    fzfd_result="$(fzfd "${targetdir##*/}")" # Search only the last part of the path.
    fzfd_exitcode=$?
    if [[ $fzfd_exitcode == 0 ]]; then
      log.success "fzfd_result: $fzfd_result"
      # Todo: pass specified args
      if ! cd "$fzfd_result"; then
        local exitcode=$?
        log.fatal "${Cc}cd $fzfd_result${Cc0} failed ($exitcode), returning $exitcode"
        return $exitcode
      fi
      return 0
    fi
    log.warn "No results from fzf ($fzfd_exitcode), returning $builtin_cd_exitcode"
    return $builtin_cd_exitcode

  }

  # # .handle-dest-is-a-file <TARGET>
  # Called by `cd` if `-f "$targetdir"`. Confirms whether to cd into containing directory.
  # Returns 100 if user declines, otherwise returns exitcode of `cd "$dir_name"`
  function .handle-dest-is-a-file() {
    # maybe passed a file path e.g. cd /etc/apt/sources.list
    local dir_name
    dir_name="$(dirname "$1")" || return 100
    if confirm "${Cc}${1}${Cc0} is a file, cd into ${Cc}${dir_name}${Cc0} instead?"; then
      cd "$dir_name"
      return $?
    fi
    return 100
  }

  # # .do-ls
  # Called by `cd` if `"$do_ls" && [[ "$PWD" != "$HOME" ]]`
  function .do-ls() {
    print_hr
    ls # Possibly alias to exa or just patched
  }

  declare -A GIT_STATE=(
    [GITSTATUS_INCLUDES_BRANCH]=""
    [DIFF_TOOL]=""
  )

  # # .handle-git-repo <prompt full git status:bool>
  # Called by `cd` if `"$show_git_status" && [[ "$PWD" != "$HOME" && -d "$PWD/.git" ]]`
  function .handle-git-repo() {
    local statusoutput raw_status_output
    if [[ ! ${GIT_STATE[GITSTATUS_INCLUDES_BRANCH]} ]]; then
      if git config status.branch &>/dev/null; then
        GIT_STATE[GITSTATUS_INCLUDES_BRANCH]=true
      else
        GIT_STATE[GITSTATUS_INCLUDES_BRANCH]=false
      fi
    fi
    raw_status_output="$(git status -s)"
    if [[ "${GIT_STATE[GITSTATUS_INCLUDES_BRANCH]}" = true ]]; then
      statusoutput="$(command grep -vE -e "^##" <<<"$raw_status_output")"
    else
      statusoutput="$raw_status_output"
    fi

    if [[ -n "$statusoutput" ]]; then
      printf "%b\n" "${h2}Git status:${C0}\n" 1>&2
      printf "%s" "$raw_status_output"

      if [[ ! ${GIT_STATE[DIFF_TOOL]} ]]; then
        local diff_tool="$(git config diff.tool)"
        if [[ ! "$diff_tool" ]]; then
          diff_tool="$(isdefined delta && printf delta || printf diff)"
        fi
        GIT_STATE[DIFF_TOOL]="${diff_tool}"
      fi
      print_hr
    fi

    # * git branch and log
    printf "%b" "branch: \033[38;2;78;154;6;1m$(git_current_branch)\033[0m\n\n" 1>&2
    command git --no-pager log --graph --pretty="%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset" --all -n 1 1>&2
  }

  # # .exact-shallow-search-current-dir <TARGET>
  # Non-fuzzy shallow search for a directory in the current directory with `fd`. Interactive selection with `fzf`.
  function .exact-shallow-search-current-dir() {
    local targetdir="$1"
    fd -t d --exact-depth=1 "$targetdir" | FZF_DEFAULT_COMMAND= fzf -0 -1
  }

}

# # uncd
# ## Usage
# ```bash
# uncd						         # cd up once
# uncd <N-BACK>				     # cd up N times (returns if hits '/')
# uncd <DIRNAME>			     # cd up once, then cd into DIRNAME
# uncd <N-BACK> <DIRNAME>	 # cd up N times, then cd into DIRNAME
# ```
function uncd() {
  # $dirstack array has this info
  # Also (filename expansion):
  # 1 Basic Tilde Expansion:
  # • ~ alone expands to $HOME
  # • ~+ expands to current directory ($PWD)
  # • ~- expands to previous directory ($OLDPWD)
  # 2 Directory Stack Navigation:
  # • ~<number> goes to position in dir stack (0-based)
  # • ~+<number> same as above
  # • ~-<number> counts from bottom of stack
  # • ~0 or ~+0 is current directory
  # • ~1 or ~+1 is top of stack
  if [[ -z "$1" ]]; then
    # * just 'uncd'
    cd .. --quiet --ls --show-git-status
    return $?
  fi

  # At this point: at least first arg is not empty (uncd 3, uncd bin, uncd 3 bin)
  local oldpwd="$PWD"
  if isnum "$1"; then
    # * e.g. 'uncd 3 [bin]'
    # climb up (..) 1 time short on purpose: leave the last cd to custom cd
    local -i builtin_cd_times=$((1 - 2))
    shift
    local -i i=0
    # log.debug "$builtin_cd_times times 'cd ..'"
    while [ "$i" -le "$builtin_cd_times" ]; do

      if [[ "$(dirname "$PWD")" == / ]]; then
        # break one level before '/' (e.g. '/tmp')
        log.warn "reached child of '/', not uncding any further"
        break
      fi

      if builtin cd ..; then
        ((i++))
      else
        log.fatal "${Cc}builtin cd ..${Cc0} failed (PWD: '$PWD'), returning 1"
        return 1
      fi

    done
  fi

  # * last climb up (..)
  local custom_cd_dest
  if [[ -z "$1" ]]; then
    # * no 2nd arg, just 'uncd 3'; go up (..) last time with custom cd (iter is minus 1)
    custom_cd_dest=".."
  else
    # * 2nd arg specified, i.e. 'uncd 3 bin';
    # go up (..) last time with builtin cd (iter is minus 1) then custom cd to $2 ('bin')
    if ! builtin cd ..; then
      log.fatal "${Cc}builtin cd ..${Cc0}' failed (PWD: '$PWD'), returning 1"
      return 1
    fi
    custom_cd_dest="$1"
  fi

  local custom_cd_exitcode
  cd "$custom_cd_dest" --quiet --ls --show-git-status
  custom_cd_exitcode=$?
  export OLDPWD="$oldpwd"
  return "$custom_cd_exitcode"

}

function recd() {
  cd "$PWD" "$@"
}

# # cdwhere <THING>
# cd to the directory of `THING`. `THING` should be a file in path, e.g. 'cdwhere npm'
function cdwhere() {
  if [[ -z "$1" ]]; then
    log.fatal "expecting 1 arg"
    docstring -p "$0"
    return 1
  fi
  local where_res
  if ! where_res="$(where "$1")"; then
    log.fatal "failed ${Cc}where $1"
    return 1
  fi
  if [[ -z "$where_res" ]]; then
    log.fatal "${Cc}where $1${Cc0} result is empty"
    return 1
  fi
  log.debug "where_res:\n${Cc}$where_res"
  local dest
  if ! dest="$(fzff "$where_res")"; then
    log.warn "nothing chosen"
    return $?
  fi
  local dir_name
  if ! dir_name="$(dirname "$dest")"; then
    log.fatal "failed ${Cc}dirname $dest"
    return 1
  fi
  if [[ ! -d "$dir_name" ]]; then
    log.fatal "not a directory: '$dir_name'"
    return 1
  fi
  cd "$dir_name"
  return $?
}

# # cdroot
# cd to the root of the current git repo
function cdroot(){
  local root_dir
  root_dir="$(vex git.rootpath)" || return $?
  cd "$root_dir"
  return $?
}