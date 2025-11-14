#!/usr/bin/env zsh

# ------[ Aliases ]------
{
# * branch
aliases[gcb]='git_current_branch'


# * diff
unalias gd
aliases[gdt]='git difftool'

# * log
alias gpl='git pull'

unalias glola gloga

alias glg="git log --graph --pretty='%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --all"
aliases[gl]='git log --oneline --decorate --graph --all'

# * push
unalias gp

# Assumes `git config --global alias.psh '!git fetch --all && git push --force-with-lease --force-with-includes'`
alias gpsh='git psh'
alias gpsho='git push origin'

# * stash
unalias gstaa gstc gstd gstl gstp gsts gstu gstall

alias gs='git stash'
alias gsa='git stash apply'
alias gsc='git stash clear'
aliases[gsd]='git stash drop'
alias gsl='git stash list'
alias gsp='git stash pop'
alias gsst='git stash show --text'
alias gsiu='git stash --include-untracked'
alias gsall='git stash --all'

# * commit
aliases[gcm]='git commit -m'
alias gcae='git commit --allow-empty'

# * misc
unalias gignore gunignore
alias guiau='git update-index --assume-unchanged'
alias guinau='git update-index --no-assume-unchanged'
} 2> /dev/null 1> /dev/null

# ------[ Helpers ]------

function _is_in_repo(){
  git rev-parse --is-inside-work-tree &>/dev/null
}

function _git_dir_check_maybe_cd(){
	[[ -d .git ]] && return 0
  log.warn "No .git dir in $PWD" --offset 4
  local repo_root
  repo_root="$(git.rootpath)" || return $?
  confirm "cd to ${repo_root}?" || return 100
  builtin cd "$repo_root"
}

function _is_revlike() {
  [[ $1 =~ ^[a-f0-9]{4,40}$ ]]
}

# # git.rootpath
# Prints the root path of the git project.
# Basically a compat wrapper for `git rev-parse` with `--show-toplevel`, and if that fails then `--show-cdup`.
# Returns 0 if the command returned a non-empty string.
function git.rootpath(){
  local project_root
  project_root="$(git rev-parse --show-toplevel 2> /dev/null)"
  [[ -z "$project_root" ]] && {
    project_root="$(git rev-parse --show-cdup 2> /dev/null)"
  }
  printf "%s" "$project_root"
  [[ -n "$project_root" ]]
}

# ------[ Branches ]------

# # gdelete BRANCH
# Deletes local and remote branch. Confirms before each action.
function gdelete(){
  _is_in_repo || {
    log.fatal "Not in a git repo"
    return 1
  }
  local branch="$1"
  shift 1 || { log.error "$0: Not enough args (expected 1, got ${#$}). Usage:\n$(docstring -p "$0")"; return 2; }
  runcmds ---confirm-each \
    "git branch -D $branch" \
    "git push origin --delete $branch"

}

# # git.branches
# Prints all branches, sorted by last commit date.
function git.branches(){
  git for-each-ref --sort=-committerdate refs/heads refs/remotes --format='%(committerdate:iso8601) %(refname:short)' \
  | sort -r \
  | awk '{print $4}' \
  | command grep -Po '(.*/)?\K.*' \
  | awk '!seen[$0]++'
}

# # git.parentrev [OF_BRANCH=CURRENT]
# Prints the parent revision of the current branch.
function git.parentrev(){
  setopt localoptions errreturn
  local branch
  if [[ -z "$1" ]]; then
    branch="$(git_current_branch)"
  else
    branch="$1"
  fi

  # Find the upstream branch (parent branch)
  local upstream_branch=$(git for-each-ref --format='%(upstream:short)' "$(git symbolic-ref -q HEAD)")
  # This worked for me once too:
  # git merge-base HEAD $(git for-each-ref --format='%(upstream:short)' $(git symbolic-ref -q HEAD))

  # If no upstream branch is found, default to 'origin/main'
  [[ -z $upstream_branch ]] && upstream_branch="$(git_main_branch)"

  # Find the merge base (common ancestor) between the branch and the upstream branch
  local merge_base="$(git merge-base "$branch" "$upstream_branch")"

  printf "%s" "$merge_base"
}

# # git.parentbranch [OF_BRANCH=CURRENT / OF_REVISION]
# Prints the parent branch of the current branch.
function git.parentbranch(){
  local commit_hash
  if [[ -z "$1" ]]; then
    commit_hash="$(git.parentrev)"
  elif _is_revlike "$1"; then
    commit_hash="$1"
  else
    commit_hash="$(git.firstcommit "$1")"
  fi
  local branch_name=$(git branch --contains "$commit_hash" | grep -v 'remotes/' | head -n 1 | sed 's/^[* ]*//')
  printf "%s" "$branch_name"
}

# ------[ Commits ]------

# # git.commits
# Lists short commits in current branch.
function git.commits(){
  git log --pretty=oneline --abbrev-commit | awk '{print $1}'
}

# # git.showcommit <BRANCH=CURRENT> <INDEX (1-based)> [--oneline]
# Shows the INDEX commit of a branch. 1 is the first commit. -1 is the last commit.
function git.showcommit(){
  local git_log_args=(-n 1)
  local target_branch
  local -i commit_index
  while (( $# )); do
    if [[ "$1" == --oneline ]]; then
      git_log_args+=(--pretty=oneline)
    elif isnum "$1"; then
      commit_index="$1"
    else
      target_branch="$1"
    fi
    shift
  done
  [[ "$commit_index" ]] || { log.error "$0: Missing commit index positional arg. Usage:\n$(docstring -p "$0")"; return 2; }
  [[ "$target_branch" ]] || target_branch="$(git_current_branch)"
  local commit
  if (( commit_index < 0 )); then
    commit=$(git rev-list --reverse "$target_branch" | tail -n "$((commit_index * -1))" | head -n 1)
  else
    commit=$(git rev-list --reverse "$target_branch" | head -n "$commit_index" | tail -n 1)
  fi
  printf "%s" "$commit"
}

# # git.firstcommit <BRANCH=CURRENT> [--oneline]
# Shows the first commit of a branch
function git.firstcommit(){
  git.showcommit "$@" 1
}

# # git.lastcommit <BRANCH=CURRENT> [--oneline]
# Shows the first commit of a branch
function git.lastcommit(){
  git.showcommit "$@" -1
}

# # gacp [COMMIT_MSG]
# git add . && git commit -am [COMMIT_MSG] && git push
# If COMMIT_MSG is not provided, it will be prompted for.
function gacp() {
  local commitmsg
  if [[ -n "$1" ]]; then
    commitmsg="$1"
    shift 1
    log.debug "commitmsg: $commitmsg"
  fi
  if ! vex git add .; then
    log.fatal "${Cc}git add${Cc0} failed, aborting"
    return 1
  fi
  if [[ -z "$commitmsg" ]]; then
    commitmsg="$(input "Commit message? (e.g. changed this to that)")"
  fi
  if [[ -z "$commitmsg" || "$commitmsg" = "" ]]; then
    commitmsg="$(date)"
  fi
  commitmsg="'$commitmsg'"  # Bash cleans up single quotes in middle of string
  if ! confirm "commit -am $* $commitmsg?"; then
    log.warn Aborting
    return 3
  fi
  if ! vex git commit -am "$@" "$commitmsg"; then
    log.fatal Failed
    return 1
  fi

  if ! confirm "Push?"; then
    log.warn Aborting
    return 3
  fi
  local exitcode
  vex git push
  exitcode=$?

  # If permission denied, probably tried to push to forked upstream, and a remote upstream is not set (e.g. new repo).
  if [[ "$exitcode" == 128 ]]; then
    local currbranch="$(git_current_branch)"
    local -a git_push_args=(origin "$currbranch")
    local has_set_upstream=false
    git rev-parse --abbrev-ref --symbolic-full-name @{upstream} 1>/dev/null 2>/dev/null && has_set_upstream=true
    [[ "$has_set_upstream" == true ]] || git_push_args=(--set-upstream "${git_push_args[@]}")
    confirm "Run ${Cc}git push ${git_push_args[@]}${Cc0}?" || return 3
    vex git push "${git_push_args[@]}"
    return $?
  fi
  return $exitcode

}

# ------[ Files ]------

# # git.stfiles [EXPRESSION]
# If `EXPRESSION` is not given, prints a list of files.
# eval's `EXPRESSION`, substituting literal '{}' with the file path.
# If '{}' is not found in `EXPRESSION`, the file path is appended to the end.
# Example: git.stfiles 'git restore {}'
function git.stfiles() {
	local status_files="$(command git status -s | awk '{print $2}')" || {
		command git status -s
		return $?
	}
	[[ ! "$status_files" ]] && return 1
	[[ ! "$1" ]] && {
		printf "%s\n" "$status_files"
		return 0
	}
  local status_file
  declare -i fail_count=0
  local expression="$*"
  if [[ ! "$expression" =~ {} ]]; then
    expression="${expression} '{}'"
  fi
  while read -r status_file; do
    eval "${expression//"'{}'"/$status_file}" || ((fail_count++))
  done <<< "$status_files"
  return "$fail_count"
}

# # git.modified [EXPRESSION]
# If no `EXPRESSION` is given, prints the modified files.
# eval's `EXPRESSION`, substituting literal '{}' with the file path.
# If '{}' is not found in `EXPRESSION`, the file path is appended to the end.
# Example: git.modified echo
# Example: git.modified 'git add {}; git commit -m "changed {}"'
function git.modified() {
  local modified_files
  if ! modified_files="$(git ls-files --modified)"; then
    return $?
  fi
  if [[ ! "$modified_files" ]]; then
    if ! modified_files="$(git status --porcelain | command grep -E '^ M' | awk '{print $2}')"; then
      return $?
    fi
    [[ ! "$modified_files" ]] && return 1
    log.info "Empty output for git ls-files --modified, but git status --porcelain | command grep -E '^ M' returned something"
  fi
	if [[ ! "$1" ]]; then
    print "$modified_files"
    return 0
	fi
  local modified_file
  declare -i fail_count=0
  local expression="$*"
  if [[ ! "$expression" =~ {} ]]; then
    expression="${expression} '{}'"
  fi
  while read -r modified_file; do
    eval "${expression//"{}"/${modified_file}}" || ((fail_count++))
  done <<< "$modified_files"
  return "$fail_count"
}

# # git.modifiedranges [GIT_DIFF_OPTS...]
# Prints the inclusive ranges of modified lines in the diff.
# ```bash
# ❯ git.modifiedranges path/to/file.py
# 15-16
# 32-49
# 51-54
#
# ❯ git.modifiedranges file.py | map ruff format file.py --range
# 1 file reformatted
# 1 file reformatted
# 1 file left unchanged
# ```
function git.modifiedranges(){
  git diff --unified=0 "$@" | grep -e "^@@" | awk -F'[^0-9]+' '{print $4"-"($4+$5-1)}'
}

# # git.untracked [EXPRESSION]
# If no `EXPRESSION` is given, prints untracked files.
# eval's `EXPRESSION`, substituting literal '{}' with the file path.
# If '{}' is not found in `EXPRESSION`, the file path is appended to the end.
# Example: git.untracked 'git restore'
# Example 2: git.untracked 'git update-index {} --assume-unchanged'
function git.untracked(){
  local untracked_files
	untracked_files="$(git ls-files --others --exclude-standard)" || return $?
  [[ ! "$untracked_files" ]] && return 1
	if [[ ! "$1" ]]; then
		printf "%s\n" "$untracked_files"
	  return 0
	fi
	local untracked_file
	declare -i fail_count=0
  local expression="$*"
  if [[ ! "$expression" =~ {} ]]; then
    expression="${expression} '{}'"
  fi
  while read -r untracked_file; do
    eval "${expression//"{}"/${untracked_file}}" || ((fail_count++))
  done <<< "$untracked_files"
  return "$fail_count"
}

# # git.staged [EXPRESSION]
# If no `EXPRESSION` is given, prints staged files.
# eval's `EXPRESSION` with literal `{}`.
# Example: git.staged 'echo {}'
function git.staged(){
	local staged_files="$(git diff --name-only --cached)" || {
		git diff --name-only --cached
		return $?
	}
	[[ ! "$staged_files" ]] && return 1
	if [[ ! "$1" ]]; then
	  printf "%s\n" "$staged_files"
	  return $?
	fi
	local staged_file
	declare -i fail_count=0
  local expression="$*"
  if [[ ! "$expression" =~ {} ]]; then
    expression="${expression} '{}'"
  fi
	while read -r staged_file; do
		eval "${expression//"{}"/${staged_file}}" || ((fail_count++))
	done <<< "$staged_files"
	return "$fail_count"
}

# # git.deleted [EXPRESSION]
# If no `EXPRESSION` is given, prints deleted files.
# eval's `EXPRESSION` with literal `{}`.
# Example: git.deleted 'echo {}'
function git.deleted(){
	# TODO: this worked after git revert -n HEAD, but this link suggests
	#  git ls-files --deleted: https://stackoverflow.com/questions/6017987/how-can-i-list-all-the-deleted-files-in-a-git-repository
	local deleted_files="$(git status --short | command grep -Po '(?<=^ D ).+')" || {
		git status --short
		return $?
	}
	[[ ! "$deleted_files" ]] && return 1
	if [[ ! "$1" ]]; then
	  printf "%s\n" "$deleted_files"
	  return $?
	fi
	local deleted_file
	declare -i fail_count=0
  local expression="$*"
  if [[ ! "$expression" =~ {} ]]; then
    expression="${expression} '{}'"
  fi
	while read -r deleted_file; do
		eval "${expression//"{}"/${deleted_file}}" || ((fail_count++))
	done <<< "$deleted_files"
	return "$fail_count"
}

# # git.added [EXPRESSION]
# If no `EXPRESSION` is given, prints new files.
# eval's `EXPRESSION` with literal `{}`.
# Example: git.added 'echo {}'
function git.added(){
	local new_files="$(git status --short | command grep -Po '(?<=^A ).+')" || {
		git status --short
		return $?
	}
	[[ ! "$new_files" ]] && return 1
	if [[ ! "$1" ]]; then
	  printf "%s\n" "$new_files"
	  return $?
	fi
	local new_file
	declare -i fail_count=0
  local expression="$*"
  if [[ ! "$expression" =~ {} ]]; then
    expression="${expression} '{}'"
  fi
	while read -r new_file; do
		eval "${expression//"{}"/${new_file}}" || ((fail_count++))
	done <<< "$new_files"
	return "$fail_count"
}

# # git.files-not-in [TARGET_BRANCH=origin/<MAIN_BRANCH>] [-r, --reverse]
# Shows files not in the target branch.
# If `-r` is provided, shows files only in the target branch.
function git.files-not-in(){
  # -1      Suppress printing of column 1, lines only in file1.
  # -2      Suppress printing of column 2, lines only in file2.
  # -3      Suppress printing of column 3, lines common to both.
  # -i      Case insensitive comparison of lines.
  local comm_args=(-23)
  local target_branch="origin/$(git_main_branch)"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -r|--reverse) comm_args=(-13) ;;
      *) [[ -n "$target_branch" ]] && log.error "Unexpected argument: $1" && return 2
         target_branch="$1" ;;
    esac
    shift
  done
  local files_in_head="$(git ls-tree -r --name-only HEAD | sort)"
  local files_in_target="$(git ls-tree -r --name-only "$target_branch" | sort)"
  comm "${comm_args[@]}" <(<<< "$files_in_head") <(<<< "$files_in_target")
}

# # git.committed [COMMIT_SHA]
# Lists the names of files that were changed in a specific commit (COMMIT_SHA or latest commit if unspecified).
function git.committed(){
  git diff-tree --no-commit-id --name-only -r "${1:-HEAD}"
}


# # git.searchfile FILE_PERL_REGEX
# Searches for files matching the regex in all branches.
# Prints $branch:$file_path for each match.
function git.searchfile(){
  local file_regex="$1"
  shift || { log.error "$0: Not enough args (expected 1, got ${#$}). Usage:\n$(docstring -p "$0")"; return 2; }
  local file_path
  for branch in $(git for-each-ref --format="%(refname)" refs/heads); do
    file_path="$(git ls-tree -r --name-only "$branch" | command grep -P "${file_regex}")" || continue
    echo "${Cd}${branch}:${C0}${file_path}"
  done
}

# # gexclude <ARG>
# Safely adds ARG to .git/info/exclude, unless it's already/partly there.
function gexclude(){
  _git_dir_check_maybe_cd || return 1
  local excluded
	command grep -vE '^\s*#' .git/info/exclude | command grep -vE '^$' | while read -r excluded; do
	  if [[ "$excluded" == "$1" ]]; then
	    log.success "$1 already excluded"
	    return 0
	  fi
	  if [[ "$1" == "$excluded"* ]]; then
      confirm "Already excluded ${Cc}${excluded}${Cc0}, which is a substring of ${Cc}${1}${Cc0}.\nContinue?" || {
        log.success "Returning 0"
        return 0
      }
    fi
	done
  printf "\n%s\n" "$1" >> .git/info/exclude
}

# # gexcluded
# Just cats .git/info/exclude.
function gexcluded(){
  _git_dir_check_maybe_cd || return 1
  cat .git/info/exclude
}


# ------[ Diff ]------

# # gdargs+ <arg> [shamrg]
# Prints args for deeper git diff with ignoring whitespace and added context.
function gdargs+(){
  print -- \
    --unified=10 \
    --inter-hunk-context=10 \
    --ignore-all-space \
    --ignore-blank-lines \
    --ignore-space-change \
    --ignore-space-at-eol \
    --ignore-cr-at-eol \
    --find-copies-harder \
    --minimal \
    --histogram \
    --ignore-submodules \
    --break-rewrites \
    --find-renames \
    --find-copies \
    --function-context
}

# # gd [-t] [git diff ARGS...]
# Unless diff is not empty, goes through:
# 1. ignoring space
# 2. not ignoring space
# 3. plain git diff
# 4. prompting git diff origin/$currbranch (if not empty)
# 5. prompting git diff upstream/$currbranch origin/$currbranch (if any upstream and if not empty)
# 7. giving up
# `-t` means envoking `git difftool` instead of `git diff`
# ## fyi:
# Assume local committed changes are 1.0.3, fetched origin is 1.0.4, and local uncommitted (newest) changes are 1.0.5:
# - git diff                      | 1.0.3 vs 1.0.5 (Changes in the working tree not yet staged for the next commit.)
# - git diff HEAD                 | 1.0.3 vs 1.0.5 (Changes in the working tree since your last commit; what you would be committing if you run "git commit -a")
# - git diff origin/master        | 1.0.4 vs 1.0.5 (fetched vs local uncommitted)
# - git diff origin/master HEAD   | 1.0.4 vs 1.0.3 (fetched vs local committed)
# - git diff origin/master upstream/master | fetched vs forked
# - git diff --cached             | Changes between the index and your last commit; what you would be committing if you run "git commit".
# ## todo (figure out):
# - git diff --word-diff
# - git diff-tree --no-commit-id --name-only -r
# - git diff origin/HEAD vs git diff origin/master
function gd() {
  log.title "gd($*)"
  local diffcmd=diff  # either `diff` or `difftool`
  local positional=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -t)
        diffcmd='difftool --no-symlinks --dir-diff'
        log.debug "diffcmd: ${diffcmd}" ;;
      *) positional+=("$1") ;;
    esac
    shift
  done
  set -- "${positional[@]}"

  local diffout
  # ** 1) With all ignore-* flags, and patience+harder
  local diff_basic_args=(
    --diff-algorithm=patience
    --find-copies-harder
  )
  local diff_ignore_args=(
    --ignore-cr-at-eol
    --ignore-space-at-eol
    --ignore-space-change
    --ignore-all-space
    --ignore-blank-lines
  )
  diffout="$(git --no-pager diff "${diff_basic_args[@]}" "${diff_ignore_args[@]}" "${@}")"
  if [[ -n "$diffout" ]]; then
    # all good
    notif.success "git $diffcmd <ignore-flags> ${*}"
    git "$diffcmd" "${diff_basic_args[@]}" "$@"
    return $?
  fi
  # failed with all ignore-* flags
  # ** 2) No ignore-* flags, but patience+harder
  log.warn "Diff empty when with all ${Cc}ignore-*${Cc0} flags, trying without them"
  diffout="$(git --no-pager diff "${diff_basic_args[@]}" "${@}")"
  if [[ -n "$diffout" ]]; then
    if confirm "Found some diff without ${Cc}ignore-*${Cc0} flags. Show diff?"; then
      notif.success "git $diffcmd ${diff_basic_args[*]} ${*}"
      git "$diffcmd" "${diff_basic_args[@]}" "$@"
      return $?
    fi
    return 1
  fi
  # no diff even when not ignoring whitespace

  log.warn "Diff empty even without ${Cc}ignore-*${Cc0} flags"

  # ** 3) Plain 'git diff'
  diffout="$(git --no-pager diff "${@}")"
  if [[ -n "$diffout" ]]; then
    # all good
    notif.success "git $diffcmd ${*}"
    git "$diffcmd" "$@"
    log.warn "WEIRD: ${Cc}git diff ${diff_basic_args[*]} $*${Cc0} failed but ${Cc}git diff $*${Cc0} succeeded"
  fi
  log.warn "Nothing: ${Cc}git diff ${*}"

  # ** 4) git diff origin/$currbranch
  local currbranch
  currbranch="$(git_current_branch)"
  if [[ -n "$(git --no-pager diff origin/"$currbranch" "$@")" ]]; then
    if confirm "${Cc}git diff origin/$currbranch $*${Cc0} is not empty. Display? (recursive)"; then
      gd origin/"$currbranch" "$@"
      return $?
    fi
  fi

  log.warn "Nothing: ${Cc}git diff origin/$currbranch ${*}"

  # ** 5) upstream/$currbranch vs origin/$currbranch
  # Check if upstream exists first
  if git --no-pager remote get-url upstream &>/dev/null; then
    if [[ -n "$(git --no-pager diff upstream/"$currbranch" origin/"$currbranch" "$@")" ]]; then
      if confirm "${Cc}git diff upstream/$currbranch origin/$currbranch $*${Cc0} is not empty. Display? (recursive)"; then
        gd upstream/"$currbranch" origin/"$currbranch" "$@"
        return $?
      fi
    else
      log.warn "Nothing: ${Cc}git diff upstream/$currbranch origin/$currbranch $*"
    fi
  else
    log.warn "No upstream to diff against"
  fi

  # ** 6) stash@{0}
  if [[ -n "$(git --no-pager diff stash@{0} "$@")" ]]; then
    if confirm "${Cc}git diff stash@{0} $*${Cc0} is not empty. Display? (recursive)"; then
      gd stash "$@"
      return $?
    fi
  fi


  return 1

}

# # git.beforeafter [COMMIT...] [GIT_DIFF_OPTS...] [--include-lock-files] [--wrap-blocks] [-- FILE_GLOB...]
# Extracts the context of changes made between two commits. Wraps files with headers.
# `--wrap-blocks` adds XML-like tags around blocks of changes for easier LLM processing.
# `git.beforeafter [--include-lock-files]`: Compares working tree vs HEAD
# `git.beforeafter <DIFF_SOURCE> [--include-lock-files]`: Compares <DIFF_SOURCE>..HEAD
# `git.beforeafter <DIFF_SOURCE> <DIFF_AGAINST> [--include-lock-files]`: Compares <DIFF_SOURCE>..<DIFF_AGAINST>
function git.beforeafter(){
  # --wrap-blocks implementation:
  # https://aistudio.google.com/app/prompts?state=%7B%22ids%22:%5B%2213e7zOw-gtgyT3Be4QXG3WeRPKDydxzlE%22%5D,%22action%22:%22open%22,%22userId%22:%22105503031810937427554%22,%22resourceKeys%22:%7B%7D%7D&usp=sharing
  local -a diff_targets
  local -a git_diff_args
  local include_lock_files=false
  local wrap_blocks=false
  local seen_double_dash=false
  local -a file_globs
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --include-lock-files) include_lock_files=true ;;
      --wrap-blocks) wrap_blocks=true ;;
      --) seen_double_dash=true ;;
      -*) [[ "$seen_double_dash" = true ]] && { log.error "Unexpected argument: $1"; return 2; }
          git_diff_args+=("$1") ;;
      *)  if [[ "$seen_double_dash" = true ]]; then
            file_globs+=("$1")
          else
            [[ "${#diff_targets[@]}" -eq 2 ]] && { log.error "Unexpected argument: $1"; return 2; }
            diff_targets+=("$1")
          fi ;;
    esac
    shift
  done
  
  [[ "${#diff_targets[@]}" -eq 0 ]] && diff_targets=('HEAD')
  
  git_diff_args+=(
    $(gdargs+)
  )
  
  log.debug "$(typeset git_diff_args diff_targets include_lock_files file_globs wrap_blocks)"
  
  # Get the diff for the commit
  local diff_output
  diff_output="$(git --no-pager diff "${git_diff_args[@]}" "${diff_targets[@]}" -- "${file_globs[@]}")"
  [[ -z "$diff_output" ]] && {
    log.error "Empty diff output. Aborting."
    return 1
  }
  echo "$diff_output" > /tmp/git-beforeafter.diff
  
  local -i columns=80
  printf "─%.0s" {1..$columns}
  printf "\n# Modified Files\n"
  printf "=%.0s" {1..$columns}
  
  local line file_path old_line new_line line_info
  local -i old_scope_end new_scope_end
  
  # Parse the diff output and extract the file changes and line numbers
  while IFS= read -r line; do
    # Start of a new file change
    if [[ "$line" =~ ^diff ]]; then
      file_path=$(sed -E 's/^diff --git a\/(.*) b\/.*/\1/' <<< "$line")
      [[ "$include_lock_files" = false && "$file_path" = *lock* ]] && {
        log.debug "Skipping lock file: $file_path"
        continue
      }

    # Extract line numbers from the diff hunk header
    elif [[ $line =~ ^@@ ]]; then
      [[ "$include_lock_files" = false && "$file_path" = *lock* ]] && {
        log.debug "Skipping lock file: $file_path"
        continue
      }
      # Only grab the numbers, ignore any following text
      line_info=$(grep -o '@@ -[0-9]\+,[0-9]\+ +[0-9]\+,[0-9]\+ @@' <<< "$line" | sed -E 's/^@@ -([0-9]+),([0-9]+) \+([0-9]+),([0-9]+) @@.*/\1 \2 \3 \4/')
      read -r old_line old_span new_line new_span <<< "$line_info"

      # Ensure we have numeric values
      if ! { [[ "$old_line" =~ ^[0-9]+$ ]] && [[ "$old_span" =~ ^[0-9]+$ ]] && 
             [[ "$new_line" =~ ^[0-9]+$ ]] && [[ "$new_span" =~ ^[0-9]+$ ]]; }; then
        log.debug "Invalid line numbers for $file_path: $old_line,$old_span $new_line,$new_span"
        continue
      fi

      # Check if file exists in the commit
      log.debug "$(typeset file_path)"
      if ! git --no-pager show "${git_diff_args[@]}" "${diff_targets[1]}:$file_path" > /dev/null 2>&1; then
        log.debug "${diff_targets[1]}:${file_path} not found."
        continue
      fi
      
      # # Find the scope lines
      # scope_start=$((old_line - 10))  # Look 10 lines before the change
      # [[ $scope_start -lt 1 ]] && scope_start=1
      # scope_end=$((new_line + 10))    # Look 10 lines after the change
      
      old_scope_end=$((old_line + old_span))
      new_scope_end=$((new_line + new_span))

      # Get the content before and after the change
      before_content=$(git --no-pager show "${git_diff_args[@]}" "${diff_targets[1]}:$file_path" 2>/dev/null | sed -n "${old_line},${old_scope_end}p" 2>/dev/null)
      if [[ "${#diff_targets[@]}" -eq 2 ]]; then
        after_content=$(git --no-pager show "${git_diff_args[@]}" "${diff_targets[2]}:$file_path" 2>/dev/null | sed -n "${new_line},${new_scope_end}p" 2>/dev/null)
      else
        after_content=$(sed -n "${new_line},${new_scope_end}p" "$file_path" 2>/dev/null)
      fi
      
      # Small state machine: both exist, either exists, none exists
      if [[ -n "$before_content" && -n "$after_content" ]]; then
        # both exist
        printf "\n---\n"
        printf "\n#\n"
        printf "# BEFORE: %s\n" "$file_path"
        printf "#\n\n"
        printf "%s\n" "$before_content"

        printf "\n---\n"
        printf "\n#\n"
        printf "# AFTER: %s\n" "$file_path"
        printf "#\n\n"
        printf "%s\n" "$after_content"
      elif [[ -n "$before_content" ]]; then
        # only before exists
        printf "\n---\n"
        printf "\n#\n"
        printf "# DELETED: %s\n" "$file_path"
        printf "#\n\n"
        printf "%s\n" "$before_content"
      elif [[ -n "$after_content" ]]; then
        # only after exists
        printf "\n---\n"
        printf "\n#\n"
        printf "# NEW: %s\n" "$file_path"
        printf "#\n\n"
        printf "%s\n" "$after_content"
      else
        log.warn "No content found in the before/after snapshots"
      fi
    fi
  done <<< "$diff_output"
  
  # Print any new (untracked) files
  local -a untracked_files
  untracked_files=($(git.untracked))
  if (( ${#untracked_files[@]} == 0 )); then
    return 0
  fi
  
  printf "\n\n"
  printf "─%.0s" {1..$columns}
  printf "\n# New Files\n"
  printf "=%.0s" {1..$columns}
  printf "\n"
  local file
  for file in "${untracked_files[@]}"; do
    if [[ "$include_lock_files" = false && "$file" = *lock* ]]; then
      log.debug "Skipping lock file: $file"
      continue
    fi
    printf "\n#\n"
    printf "# %s\n" "$file"
    printf "#\n\n"
    printf "%s\n" "$(<"$file")"
  done
  
}

# # git-diff-xml-wrap [STDIN DIFF]
# Wraps blocks of changes in appropriate XML-like tags.
# Example:
# git diff --unified=20 --inter-hunk-context=10
function git-diff-xml-wrap(){
  # Pretty diff wrapper with per-patch tags and file-level XML tags.
  # - Suppresses git metadata lines; prints '---' + <filepath> per file and closes with </filepath>.
  # - Context lines are printed raw (no leading space). Change blocks are wrapped as:
  #   <added|deleted|modified patch start: line N|lines N-M>
  #   ...changed lines without +/- prefixes...
  #   </added|deleted|modified patch end: line N|lines N-M>
  
  if ! is_piped && [[ -z "$1" ]]; then
    if is_piping || ! is_interactive; then
      log.info "No data provided and can’t ask user interactively. Defaulting to 'git --no-pager diff $(gdargs+) | $0'."
      command git --no-pager diff $(gdargs+) | $0
      return $?
    fi
    confirm "No data in stdin. Run 'git --no-pager diff $(gdargs+) | $0'?" || return 0
    command git --no-pager diff $(gdargs+) | $0
    return $?
  fi
  
  function .parse-diff(){
    awk '
    BEGIN {
      # Block accumulators (current patch)
      line_count = 0; add_count = 0; del_count = 0;
      delete change_lines;

      # File state
      file_open = 0; file_path = ""; file_status = "";
      file_binary = 0; file_dissim = "";
      file_lines = 0;

      # Hunk line counters
      old_line = 0; new_line = 0; block_after_start = 0; block_before_start = 0; in_block = 0;

      # File-level buffering and counters for summaries and patch numbering
      fl_n = 0; delete fl; delete fl_ln; delete fl_is_content;
      patches_total = 0; added_blocks = 0; deleted_blocks = 0; modified_blocks = 0;
      delete p_start_idx; delete p_end_idx; delete p_tag; delete p_label; delete p_type_idx;
      seq_added = 0; seq_deleted = 0; seq_modified = 0;
    }

    function out(s) { fl[++fl_n] = s; fl_ln[fl_n] = 0; fl_is_content[fl_n] = 0; }
    function out_line(s, ln, is_content) { fl[++fl_n] = s; fl_ln[fl_n] = ln; fl_is_content[fl_n] = is_content; }

    function flush_block() {
      if (line_count == 0) return;

      # Determine tag and line span based on additions/deletions
      tag = (add_count>0 && del_count>0) ? "modified" : (add_count>0 ? "added" : "deleted");
      start = block_after_start;
      end   = (add_count>0 ? start + add_count - 1 : start);
      label = (start==end) ? sprintf("line %d", start) : sprintf("lines %d-%d", start, end);
      # For pure deletions, keep new-side anchor but include count if multi-line
      if (tag == "deleted" && del_count > 1) {
        label = sprintf("line %d, removed %d lines", start, del_count);
      }

      # Detect whitespace-only patches (all changed lines empty/whitespace after stripping +/-)
      has_nonws = 0;
      for (i = 1; i <= line_count; i++) {
        s = substr(change_lines[i], 2);
        gsub(/[ \t\r\n]/, "", s);
        if (length(s) > 0) { has_nonws = 1; break; }
      }

      if (has_nonws == 0) {
        # Emit raw lines, no patch tags, do not count towards per-file patch stats
        for (i = 1; i <= line_count; i++) {
          c = substr(change_lines[i], 1, 1);
          if (c == "+" || c == "-") {
            out(substr(change_lines[i], 2));
          } else if (c == " ") {
            out(substr(change_lines[i], 2));
          } else {
            out(change_lines[i]);
          }
        }
        delete change_lines; line_count = 0; add_count = 0; del_count = 0; in_block = 0;
        return;
      }

      # Track per-file counts
      if (tag == "added") { added_blocks++; seq_added++; seq_idx = seq_added; }
      else if (tag == "deleted") { deleted_blocks++; seq_deleted++; seq_idx = seq_deleted; }
      else { modified_blocks++; seq_modified++; seq_idx = seq_modified; }

      # Buffer start tag (numbering will be injected on close_file)
      out(sprintf("<%s patch start of block: %s>", tag, label));
      patches_total++;
      p_start_idx[patches_total] = fl_n;
      p_tag[patches_total] = tag;
      p_label[patches_total] = label;
      p_type_idx[patches_total] = seq_idx;

      if (tag == "modified") {
        # Split into removed/new sub-sections with side-appropriate numbering
        rm_count = 0; add_count_local = 0;
        for (i = 1; i <= line_count; i++) {
          c = substr(change_lines[i], 1, 1);
          if (c == "-") rm_count++;
          else if (c == "+") add_count_local++;
        }
        rm_ln = block_before_start; add_ln = block_after_start;

        # Removed block (render with fixed gutter and no old-side numbering)
        out("<removed: start of block>");
        for (i = 1; i <= line_count; i++) {
          if (substr(change_lines[i], 1, 1) == "-") {
            s = substr(change_lines[i], 2);
            out(sprintf(" -  │%s", s));
          }
        }
        out("</removed: end of block>");

        # New block
        out("<new: start of block>");
        for (i = 1; i <= line_count; i++) {
          if (substr(change_lines[i], 1, 1) == "+") {
            s = substr(change_lines[i], 2);
            out(sprintf("%d │%s", add_ln, s));
            add_ln++;
          }
        }
        out("</new: end of block>");
      } else {
        if (tag == "added") {
          # Added-only block: number lines using new-side positions
          add_ln = block_after_start;
          for (i = 1; i <= line_count; i++) {
            if (substr(change_lines[i], 1, 1) == "+") {
              s = substr(change_lines[i], 2);
              out(sprintf("%d │%s", add_ln, s));
              add_ln++;
            } else if (substr(change_lines[i], 1, 1) == " ") {
              out(substr(change_lines[i], 2));
            } else {
              out(change_lines[i]);
            }
          }
        } else {
          # Deleted-only block: emit lines with a fixed gutter:  -  │  and no numbers
          for (i = 1; i <= line_count; i++) {
            c = substr(change_lines[i], 1, 1);
            s = (c == "+" || c == "-" || c == " ") ? substr(change_lines[i], 2) : change_lines[i];
            out(sprintf(" -  │%s", s));
          }
        }
      }
      out(sprintf("</%s patch end of block>", tag));
      p_end_idx[patches_total] = fl_n;

      # Reset block
      delete change_lines; line_count = 0; add_count = 0; del_count = 0; in_block = 0;
    }

    function open_file(path) {
      if (file_open) close_file();
      # Reset per-file state
      file_path = path; file_open = 1; file_binary = 0; file_dissim = "";
      file_lines = 0;
      fl_n = 0; delete fl; delete fl_ln; delete fl_is_content;
      patches_total = 0; added_blocks = 0; deleted_blocks = 0; modified_blocks = 0;
      delete p_start_idx; delete p_end_idx; delete p_tag; delete p_label; delete p_type_idx;
      seq_added = 0; seq_deleted = 0; seq_modified = 0;
    }

    function close_file() {
      if (!file_open) return;
      flush_block();
      # If binary, ignore buffered content and emit a single self-closing line
      if (file_binary) {
        fl_n = 0; delete fl;
        out("<binary difference/>");
        patches_total = 0; added_blocks = 0; deleted_blocks = 0; modified_blocks = 0;
      }

      # Inject patch numbering (and optional file path for large diffs) now that total is known
      file_is_large = (file_lines >= 100) ? 1 : 0;
      for (pi = 1; pi <= patches_total; pi++) {
        label_fmt = p_label[pi];
        if (file_is_large) label_fmt = sprintf("%s %s", file_path, p_label[pi]);
        # Determine denominator per patch type
        denom = (p_tag[pi] == "added") ? added_blocks : ((p_tag[pi] == "deleted") ? deleted_blocks : modified_blocks);
        num = p_type_idx[pi] + 0;
        fl[p_start_idx[pi]] = sprintf("<%s patch %d/%d start of block: %s>", p_tag[pi], num, denom, label_fmt);
        fl[p_end_idx[pi]]   = sprintf("</%s patch %d/%d end of block>", p_tag[pi], num, denom);
      }

      # Emit per-file header and opening tag with summary (and dissimilarity if present)
      print "---";
      if (file_dissim != "") {
        printf("<%s added=%d modified=%d deleted=%d dissimilarity=%s>\n", file_path, added_blocks, modified_blocks, deleted_blocks, file_dissim);
      } else {
        printf("<%s added=%d modified=%d deleted=%d>\n", file_path, added_blocks, modified_blocks, deleted_blocks);
      }
      # Wrap unchanged regions between patches
      fl_out_n = 0; delete fl_out;
      inside_patch = 0; uc_open = 0;
      i = 1;
      while (i <= fl_n) {
        line = fl[i];
        if (line ~ /^<(added|deleted|modified) patch [0-9]+\/[0-9]+ start of block:/ || line ~ /^<(added|deleted|modified) patch start of block:/) {
          if (uc_open == 1) { fl_out[++fl_out_n] = "</unchanged for context: end of unchanged block>"; uc_open = 0; }
          fl_out[++fl_out_n] = line; inside_patch = 1; i++; continue;
        }
        if (line ~ /^<\/(added|deleted|modified) patch [0-9]+\/[0-9]+ end of block>/ || line ~ /^<\/(added|deleted|modified) patch end of block>/) {
          fl_out[++fl_out_n] = line; inside_patch = 0; i++; continue;
        }
        if (inside_patch == 0 && fl_is_content[i] == 1) {
          # Start an unchanged run, always number each line using new-side numbers
          start_i = i; start_ln = fl_ln[i]; end_i = i; end_ln = start_ln;
          j = i + 1;
          while (j <= fl_n && fl_is_content[j] == 1) { end_i = j; end_ln = fl_ln[j]; j++; }
          if (start_ln == end_ln) label = sprintf("line %d", start_ln); else label = sprintf("lines %d-%d", start_ln, end_ln);
          if (file_is_large) fl_out[++fl_out_n] = sprintf("<unchanged for context: start of unchanged block %s %s>", file_path, label); else fl_out[++fl_out_n] = sprintf("<unchanged for context: start of unchanged block %s>", label);
          for (k = start_i; k <= end_i; k++) fl_out[++fl_out_n] = sprintf("%d │%s", fl_ln[k], fl[k]);
          fl_out[++fl_out_n] = "</unchanged: end of unchanged block>";
          i = end_i + 1; continue;
        }
        fl_out[++fl_out_n] = line; i++;
      }
      for (i = 1; i <= fl_out_n; i++) print fl_out[i];
      printf("</%s>\n", file_path);
      file_open = 0; file_path = "";
    }

    function start_block_if_needed() {
      if (!in_block) {
        in_block = 1;
        block_after_start = new_line; # position in the after file where additions appear
        block_before_start = old_line; # position in the before file where deletions originate
      }
    }

    {
      # diff start for a file
      if ($0 ~ /^diff --git /) {
        flush_block();
        close_file();
        # Extract a/ and b/ paths via fields to avoid regex portability issues
        n = split($0, f, " ");
        a_path = f[3]; b_path = f[4];
        sub(/^a\//, "", a_path);
        sub(/^b\//, "", b_path);
        path = (b_path != "" && b_path != "/dev/null") ? b_path : a_path;
        if (path != "") open_file(path);
        file_status = "M";
        next;
      }

      # Count per-file input lines for large-file breadcrumb threshold
      if (file_open) file_lines++;

      # New / deleted file markers influence coarse status but are not printed
      if ($0 ~ /^new file mode/) { file_status = "A"; next; }
      if ($0 ~ /^deleted file mode/) { file_status = "D"; next; }
      if ($0 ~ /^rename (from|to)/ || $0 ~ /^copy (from|to)/ || $0 ~ /^index /) { next; }

      # Similarity/dissimilarity: capture and keep in content
      if ($0 ~ /^dissimilarity index /) {
        n = split($0, parts, " "); file_dissim = parts[n];
        out($0); next;
      }
      if ($0 ~ /^similarity index /) { out($0); next; }

      # File headers (--- a/..., +++ b/...) suppressed
      if ($0 ~ /^--- / || $0 ~ /^\+\+\+ /) { next; }
      # Suppress git’s marker about missing newline at EOF (allow trailing spaces)
      if ($0 ~ /^\\ No newline at end of file( *$|$)/) { next; }
      # Mode changes and submodule summaries suppressed
      if ($0 ~ /^(old mode|new mode) [0-9]+/) { next; }
      if ($0 ~ /^Submodule /) { next; }
      # Binary markers: flag and suppress
      if ($0 ~ /^GIT binary patch$/) { file_binary = 1; next; }
      if ($0 ~ /^Binary files /) { file_binary = 1; next; }

      # Hunk header: set counters (portable, no submatch arrays)
      if ($0 ~ /^@@ /) {
        flush_block();
        # Parse old start after '-'
        old_line = 0; new_line = 0;
        s = $0;
        if (match(s, /-([0-9]+)/)) {
          old_line = substr(s, RSTART+1, RLENGTH-1) + 0;
        }
        # Parse new start after '+'
        if (match(s, /\+([0-9]+)/)) {
          new_line = substr(s, RSTART+1, RLENGTH-1) + 0;
        }
        next;
      }

      # Within hunk: context/add/del lines
      first = substr($0, 1, 1);
      if (first == " ") {
        # Context line ends any pending change block
        flush_block();
        out_line(substr($0, 2), new_line + 1, 1);
        old_line++; new_line++;
        next;
      }

      if (first == "+") {
        start_block_if_needed();
        line_count++; change_lines[line_count] = $0; add_count++; new_line++;
        next;
      }

      if (first == "-") {
        start_block_if_needed();
        line_count++; change_lines[line_count] = $0; del_count++; old_line++;
        next;
      }

      # Any other line: not part of diff body. Flush and buffer as-is.
      flush_block();
      out($0);
    }

    END {
      close_file();
    }
    '
  }
  
  local -a git_diff_args

  if [[ -n "$1" ]]; then
    is_piped && log.warn "Received data from both stdin and cli args. Ignoring stdin."
    command git --no-pager diff $(gdargs+) "$@" | .parse-diff
    return $?
  fi
  
  .parse-diff
}

# # git.detective --paths <PATH1,PATH2,...> --keywords <KEYWORD1,KEYWORD2,...> [--follow <PATH1,PATH2,...> (defaults to specified PATHS)] [--since <DATE> (default "1 day ago")]
# Prints each sub-result inside XML-like tags.
function git.detective(){
  local -a paths_patches
  local -a pickaxe_keywords
  local -a paths_follow
  local since="1 day ago"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --paths) paths_patches=("${2//,/ }"); shift ;;
      --paths=*) paths_patches=("${1#*=}");;
      --keywords) pickaxe_keywords=("${2//,/ }"); shift ;;
      --keywords=*) pickaxe_keywords=("${1#*=}");;
      --follow) paths_follow=("${2//,/ }"); shift ;;
      --follow=*) paths_follow=("${1#*=}");;
      --since) since="$2"; shift ;;
      --since=*) since="${1#*=}";;
    esac
    shift
  done 
  
  # Give `paths_follow` default values of `paths_patches` if not specified
  if (( ${#paths_follow[@]} == 0 )); then
    paths_follow=("${paths_patches[@]}")
  fi
  
  # Validate that all files_patches and files_follow are valid files
  local path_
  for path_ in "${paths_patches[@]}" "${paths_follow[@]}"; do
    if [[ ! -e "$path_" ]]; then
      log.error "Path not found: $path_"
      return 1
    fi
  done
  
  local path_patch_xml_tag_prefix="Log_Patch_"
  local keyword_xml_tag_prefix="Keyword_Log_Pickaxe_"
  local path_follow_xml_tag_prefix="Log_Follow_"
  
  for path_patch in "${paths_patches[@]}"; do
    printf "\n\n<%s%s>\n" "$path_patch_xml_tag_prefix" "$path_patch"
    git --no-pager log --since="$since" -p -- "$path_patch"
    printf "\n</%s%s>\n" "$path_patch_xml_tag_prefix" "$path_patch"
  done

  for keyword_pickaxe in "${pickaxe_keywords[@]}"; do
    printf "\n\n<%s%s>\n" "$keyword_xml_tag_prefix" "$keyword_pickaxe"
    git --no-pager log --since="$since" -S "$keyword_pickaxe" --pickaxe-regex
    printf "\n</%s%s>\n" "$keyword_xml_tag_prefix" "$keyword_pickaxe"
  done
  
  for path_follow in "${paths_follow[@]}"; do
    printf "\n\n<%s%s>\n" "$path_follow_xml_tag_prefix" "$path_follow"
    git --no-pager log --since="$since" --follow -- "$path_follow"
    printf "\n</%s%s>\n" "$path_follow_xml_tag_prefix" "$path_follow"
  done
  
}
# ------[ Log and History ]------

# # git.my-commits [DATE] [--pretty] [--branches=<pattern>]
# Filters current user's commits by current day and `--all` if `--branches=...` isn't provided
# `git.my-commits "April 4"`
function git.my-commits(){
  # ❯ git.my-commits | py.eval 'import re; [print(commit) for commit in re.findall(r"\* commit [^*]+", stdin, re.MULTILINE)]'
  local author
  if ! author="$(git config user.email)"; then
    log.fatal "failed getting user email"
    return 1
  fi
  local datestr
  if [[ "$1" && ! "$1" == -* ]]; then
    datestr="$1"
    shift
  else
    # Aug 05
    datestr="$(date "+%b %d")"
  fi
  local positional=()
  local pretty=false
  local all=true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --pretty) pretty=true ;;
      --branches=*) all=false; positional+=("$1") ;;
      *) positional+=("$1") ;;
    esac
    shift
  done
  set -- "${positional[@]}"
  local day="$(($(echo "$datestr" | cut -d ' ' -f2)))"
  local prevday=$((day - 1))
  #  local nextday=$((day + 1))
  local month=$(echo "$datestr" | cut -d ' ' -f1)

  # --source adds 'refs/heads/rsevents-demo-aug-21' to output
  # --decorate not sure
  # --graph shows connections
  # --first-parent?
  # --online?
  local gitlog_args=(
    --graph
    --author="$author"
    --since="$month $prevday"
    --until="$month $day"
  )
  $pretty && gitlog_args+=(--pretty='%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset')
  $all && gitlog_args+=(--all)
  git log "${gitlog_args[@]}" "$@"
  #git log --graph --all --decorate --source --author="$author" --since="$month $prevday" --until="$month $day" --name-only
}

# alias gl='git log --oneline --decorate --graph --all'
# alias glg="git log --graph --pretty='%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --all"

# # git.blame-who [-l, --long] <WHO> [WHERE=$PWD] [GIT_BLAME_OPTS...]
# Shows filenames blaming `WHO`.
# `--long` also prints the lines blaming `WHO`.
# Examples:
# ```bash
# git.blame-who Barnea -l --since="June 2021" | less
# ```
function git.blame-who(){
	if [[ -z "$1" ]]; then
		log.fatal "$0 expecting at least 1 arg (WHO)"
		return 2
	fi
	local long=false
	local who where
	local git_blame_args=(
    -w  # Ignore whitespace
    -M  # Detect renames
    -C  # Detect moves or copies in same commit modified files
    #-CC  # Plus detect moves or copies in files from commit that created the file
    #-CCC  # Plus detect moves or copies in files from all commits
    # -e  # Show email
	)
	while [ $# -gt 0 ]; do
    case "$1" in
      -l|--long)
        long=true ;;
      *)
        if [[ -z "$who" ]]; then
            who="$1"
        elif [[ -z "$where" ]]; then
            where="$1"
        else
            git_blame_args+=("$1")
        fi ;;
    esac
    shift
  done


  if [[ -z "$who" ]]; then
    log.fatal "$0: Missing <WHO> argument"
    return 2
  fi
	if [[ -z "$where" ]]; then
	    where="$PWD"
	fi
	log.debug "who: $who | where: $where | long: $long | git_blame_args: ${git_blame_args[*]}"
  if [[ ! -d "$where" ]]; then
    log.fatal "Does not exist or not a directory: $where"
    return 1
  fi
	local blame_output findexec
  local findargs=()
  if type fd &>/dev/null; then
    findexec=fd
    findargs+=(-H -t f . "$where")
  else
    # shellcheck disable=SC2209
    findexec=find
    findargs+=("$where" -type f)
  fi
  local file_path
  local longform_python_program="import sys
lines=sys.stdin.readlines()
for text in lines:
  a,b,c = text.partition('$who')
  a1,a2,a3 = a.partition('(')
  a=f'{a1.rstrip()} {a2}{a3}'
  c = c.lstrip()
  d,e,f = c.partition(')')
  print(f'${Cd}{a}{b} {d}{e}${C0}{f}', end='')
  "
	"$findexec" "${findargs[@]}" | while read -r file_path; do
		blame_output="$(git blame "${git_blame_args[@]}" -- "$file_path" 2>/dev/null)"
    if command grep -qi "$who" <<< "$blame_output"; then
			if $long; then
				printf "\n\033[1;96m%s\033[0m\n" "$file_path"
			  command grep --color=never -i "$who" <<< "$blame_output" | python3.12 -c "$longform_python_program"
			else
				printf "%s\n" "$file_path"
			fi
		fi

	done
}

# ------[ Remote Operations ]------

# # git.newpr
# Prompts whether to open a browser or copy the URL that creates a new merge request to the clipboard.
# Works with GitLab and (not yet) GitHub.
function git.newpr(){
  local origin_url repo_url new_pr_url user_action_choice
  origin_url="$(git remote get-url origin)" || return 1
  if [[ "$origin_url" = *gitlab* ]]; then
    # git@gitlabssh.aws.company.com:company/project/repo.git -> https://gitlab.aws.company.com/project/repo
    local without_protocol="${origin_url#*.}"              # aws.company.com:company/project/repo.git
    [[ "$without_protocol" = *.git ]] && {
      without_protocol="${without_protocol%.git}"          # aws.company.com:company/project/repo
    }
    # shellcheck disable=SC2298
    repo_url="https://gitlab.${${without_protocol}//://}"  # https://gitlab.aws.company.com/company/project/repo
    new_pr_url="${repo_url}/-/merge_requests/new?merge_request%5Bsource_branch%5D=$(git_current_branch)"
    user_action_choice="$(input "URL is $new_pr_url" --choices='[o]pen in browser [c]opy to clipboard [q]uit')"
    [[ "$user_action_choice" = q ]] && { log.prompt "Aborting."; return 0; }
    [[ "$user_action_choice" = o ]] && { open "$new_pr_url"; return $?; }
    [[ "$user_action_choice" = c ]] && {
      printf "%s" "$new_pr_url" | pbcopy
      log.success "Copied ${#new_pr_url} chars to clipboard." -L -x
      return 0;
    }
  elif [[ "$origin_url" = *github* ]]; then
    log.warn "Not implemented for service: $origin_url"
    log.prompt "Explore gh pr create --help for GitHub."
    return 1
  else
    log.error "Not implemented for service: $origin_url"
    return 1
  fi
}

# # git.browse
# Opens the repo in the browser.
function git.browse(){
  local origin_url repo_url user_action_choice
  origin_url="$(git remote get-url origin)" || return 1
  log.debug "origin_url: ${origin_url}"
  if [[ "$origin_url" = *github* ]]; then
    open "${origin_url%.git}"
    return $?
  elif [[ "$origin_url" = *gitlab* ]]; then
    # git@gitlabssh.aws...:company/project.git -> https://gitlab.aws.../company/project
    # shellcheck disable=SC2299  # Parmeter expansions can't be nested (in zsh this is fine)
    repo_url="https://gitlab.${${origin_url#*.}//://}"
    open "$repo_url"
    return $?
  else
    log.error "Not implemented for service: $origin_url"
    return 1
  fi
}

# # git.user_repos <USERNAME>
function git.user_repos() {
  # https://stackoverflow.com/questions/8713596/how-to-retrieve-the-list-of-all-github-repositories-of-a-person#:~:text=Hitting%20https%3A%2F%2Fapi.github,repositories%20for%20the%20user%20USERNAME.&text=to%20find%20all%20the%20user's%20repos.
  if [[ -z "$1" ]]; then
    log.fatal "specify username"
    return 1
  fi
  local ghuser="$1"
  curl --silent "https://api.github.com/users/$ghuser/repos?per_page=100" | jq 'map({url, html_url})' | yq --prettyPrint
  return $?
}

# # git.download-repo-dir <OWNER/REPO> [-d|--dir <SUBDIR> (default root)] [-r|--recursive (default false)] [-e|--extension <EXT> (default all)] [-b|--branch <BRANCH> (default fetched main)] [-o|--output <DIR> (default $PWD)]
# Downloads files from a GitHub repo using the GitHub API and raw URLs, preserving directory structure.
function git.download-repo-dir(){
  setopt localoptions errreturn pipefail
  local owner_repo subdir="" branch="" recursive=false extension_filter="" output_dir="$PWD"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -d|--dir) subdir="$2"; shift ;;
      --dir=*) subdir="${1#*=}" ;;
      -r|--recursive) recursive=true ;;
      -e|--extension) extension_filter="$2"; shift ;;
      --extension=*) extension_filter="${1#*=}" ;;
      -b|--branch) branch="$2"; shift ;;
      --branch=*) branch="${1#*=}" ;;
      -o|--output) output_dir="$2"; shift ;;
      --output=*) output_dir="${1#*=}" ;;
      *) [[ -n "$owner_repo" ]] && {
          log.error "Unexpected argument: $1"
          docstring "$0" -p
          return 2
        }
        owner_repo="$1" ;;
    esac
    shift
  done

  [[ -n "$owner_repo" ]] || { log.error "$0: Missing <OWNER/REPO> argument"; docstring "$0" -p; return 2; }

  # Normalize subdir
  if [[ -n "$subdir" ]]; then
    subdir="${subdir#/}"
    subdir="${subdir%/}"
  fi

  local api_key
  api_key="$(<~/.github-token 2>/dev/null)"
  local -a api_headers=(Accept:application/vnd.github.v3+json)
  [[ -n "$api_key" ]] && api_headers+=(Authorization:"Bearer $api_key")

  local repo_api_base="https://api.github.com/repos/${owner_repo}"

  # Resolve branch if not provided
  if [[ -z "$branch" ]]; then
    branch="$(http GET "$repo_api_base" "${api_headers[@]}" | jq -r '.default_branch')"
    [[ -n "$branch" && "$branch" != null ]] || { log.error "Failed to detect default branch for $owner_repo"; return 1; }
  fi

  # Common derived values
  local prefix=""
  [[ -n "$subdir" ]] && prefix="${subdir}/"
  local ext_nodot extregex
  ext_nodot="${extension_filter#.}"
  [[ -n "$ext_nodot" ]] && extregex="\\.${ext_nodot}$"

  local tree_url="${repo_api_base}/git/trees/${branch}?recursive=1"
  local contents_path
  contents_path="${subdir:+contents/${subdir}}"
  local contents_url="${repo_api_base}/${contents_path:-contents}?ref=${branch}"

  local -a jq_args=()
  [[ -n "$prefix" ]] && jq_args+=(--arg prefix "$prefix")
  [[ -n "$extregex" ]] && jq_args+=(--arg ext "$extregex")

  local jq_prefix_filter jq_ext_filter
  jq_prefix_filter=""
  jq_ext_filter=""
  [[ -n "$prefix" ]] && jq_prefix_filter='| select(.path | startswith($prefix))'
  [[ -n "$extregex" ]] && jq_ext_filter='| select(.path | test($ext; "i"))'

  local -a files
  if $recursive; then
    files=("${(@f)$(http GET "$tree_url" "${api_headers[@]}" \
      | jq -r ${jq_args[@]} ".tree[] | select(.type==\"blob\") ${jq_prefix_filter} ${jq_ext_filter} | .path")}")
  else
    files=("${(@f)$(http GET "$contents_url" "${api_headers[@]}" \
      | jq -r ${jq_args[@]} ".[] | select(.type==\"file\") ${jq_prefix_filter} ${jq_ext_filter} | .path")}")
  fi

  local -a download_headers=()
  [[ -n "$api_key" ]] && download_headers+=(Authorization:"Bearer $api_key")
  local raw_base="https://raw.githubusercontent.com/${owner_repo}/${branch}"

  local file
  for file in "${files[@]}"; do
    mkdir -p "$output_dir/$(dirname "$file")"
    http GET "${raw_base}/${file}" "${download_headers[@]}" -o "$output_dir/$file"
  done
}

# # git.clean
# Aggressively cleans up the .git directory.
# Confirms once before starting, and again before pushing.
# https://stackoverflow.com/a/27745221/11842164
function git.clean(){
  _git_dir_check_maybe_cd || return 1
  local git_dir_size_before="$(du -sh .git)"
  local cmds=(
    'rm -rf .git/refs/original/  # Deletes backup references created by operations like git filter-branch.'
    'git reflog expire --expire=now --all  # Removes change references. This will make it impossible to undo a hard reset, recovering from a botched rebase, and finding lost commits after a forced push.'
    'git gc --prune=now  # Cleans up unnecessary files and optimizes the local repository.'
    'git gc --aggressive --prune=now  # Aggressive means possibly better compression.'
  )
  runcmds ---confirm-once "${cmds[@]}"
  local git_dir_size_after="$(du -sh .git)"
	runcmds ---confirm-once \
  	'git push origin --force --all' \
  	'git push origin --force --tags'
  log.success "Before: ${git_dir_size_before} | After: ${git_dir_size_after}"
}

# ------[ "Tools" ]------

# # git.tmr
# Recursively finds all git repositories and checks their status.
# Outputs results to both stdout and /tmp/repostatuses.txt.
function git.tmr(){
  echo "" > /tmp/repostatuses.txt;
  fd --type d --hidden '^\.git$' --max-depth=15 --exec zsh -ic '
    repo="$(dirname "{}")"
    
    # Skip certain directories
    case "$repo" in
      *.cache/uv*)
        return
        ;;
      *.local/share/nvim*)
        return
        ;;
      *.local/share/nvim*)
        return
        ;;
    esac
    if ! builtin cd "$repo"; then
      echo "❌ $repo N/A" | tee -a /tmp/repostatuses.txt
      return 1
    fi
    git fetch --all
    git_status_output="$(git status 2>&1)"
    
    # Outgoing:
    local has_uncommitted_changes=false
    if grep -q -E "Changes not staged for commit:|Untracked files:|use \"git add\" and/or \"git commit -a\"" <<< "$git_status_output"; then
      has_uncommitted_changes=true
    elif grep -q "nothing to commit, working tree clean" <<< "$git_status_output"; then
      :
    else
      {
        echo "❔ $repo N/A"
        for line in "${(f)git_status_output}"; do
            mdquote "$line"
        done
      } | tee -a /tmp/repostatuses.txt
    fi
    
    # Incoming:
    local is_behind=false
    local is_ahead=false
    if grep -q -E "Your branch is behind" <<< "$git_status_output"; then
      is_behind=true
    elif grep -q -E "Your branch is ahead" <<< "$git_status_output"; then
      is_ahead=true
    fi
    
    local message
    if $has_uncommitted_changes; then
      message+="CHANGES ⬆ "
    fi
    
    if $is_behind; then
      message+="BEHIND ⬇ "
    elif $is_ahead; then
      message+="AHEAD ⬆ "
    fi
    
    if [[ -n "$message" ]]; then
      message="*️⃣ $repo $message"
    else
      message="✅ $repo OK"
    fi
    echo "$message" | tee -a /tmp/repostatuses.txt
  ' \;
}
