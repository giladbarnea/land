#!/usr/bin/env zsh

# # skills sync SOURCE TARGET[,TARGET,...] [--install-githooks [HOOKNAME[,HOOKNAME,...]]]
# # skills unsync SOURCE [TARGET[,TARGET,...]]
#
# skills sync:
#   Syncs skills from SOURCE into each TARGET/skills/ as individual symlinks (ln -sfn).
#   SOURCE may be a parent directory containing skills/, the skills/ directory itself, or a specific skills/<name> directory.
#   TARGET may be a parent directory (e.g. .claude) or a skills/ directory directly.
#
#   --install-githooks: writes the sync logic into .githooks/HOOKNAME (default: pre-commit,post-merge),
#     creates .githooks/setup.sh with the git config line, and runs `git config --local core.hooksPath`.
#
# skills unsync:
#   Removes symlinks that currently point at SOURCE skills.
#   With no TARGET, it auto-discovers .*/**/skills directories under the current directory.
#   With TARGET, each target must be a parent directory containing skills/ or the skills/ directory itself.
#
# Examples:
#   skills sync .agents .claude
#   skills sync ~/.agents ~/.claude,~/.pi/agent,~/.codex,~/.gemini
#   skills sync .agents .claude,.pi/agent --install-githooks
#   skills sync .agents/skills .claude,.pi --install-githooks pre-commit
#   skills sync .agents/skills/my-skill .claude
#   skills unsync .agents
#   skills unsync .agents/skills/my-skill .claude,.pi/agent
function skills() {
  case "${1-}" in
    sync) shift; _skills_sync "$@" ;;
    unsync) shift; _skills_unsync "$@" ;;
    '')   echo "Usage: skills <sync|unsync> ..." >&2; return 1 ;;
    *)    echo "skills: unknown subcommand '$1'" >&2; return 1 ;;
  esac
}

function _skills_escape_for_double_quotes() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//\$/\\\$}"
  value="${value//\`/\\\`}"
  printf '%s' "$value"
}

function _skills_hook_path_expr() {
  local path="$1" repo_root="$2"
  if [[ "$path" == "$repo_root"/* ]]; then
    local rel_path="${path#"${repo_root}"/}"
    printf '"$_repo_root/%s"' "$(_skills_escape_for_double_quotes "$rel_path")"
  else
    printf '%q' "$path"
  fi
}

function _skill_sync() {
  local skill="$1"
  shift

  local skill_name="${skill:t}" target_skills
  for target_skills in "$@"; do
    mkdir -p "$target_skills"
    ln -sfn "$skill" "$target_skills/$skill_name"
  done
}

function _skills_normalize_source() {
  local source="$1" action="$2" resolved=""
  reply=()

  if [[ -d "$source" && "${source:h:t}" == "skills" ]]; then
    resolved="$(realpath "$source" 2>/dev/null)" || {
      echo "$action: cannot resolve SOURCE '$source'" >&2; return 1
    }
    reply=(single "$resolved" "${resolved:h}" "$resolved")
    return 0
  fi

  if [[ -d "$source" && "${source:t}" == "skills" ]]; then
    resolved="$(realpath "$source" 2>/dev/null)" || {
      echo "$action: cannot resolve SOURCE '$source'" >&2; return 1
    }
    reply=(batch "" "$resolved" "$resolved")
    return 0
  fi

  resolved="$(realpath "$source/skills" 2>/dev/null)" || {
    echo "$action: SOURCE '$source' is neither a skills directory, nor a parent containing skills/, nor a specific skill inside skills/" >&2
    return 1
  }
  reply=(batch "" "$resolved" "$resolved")
}

function _skills_collect_source_skills() {
  local source_skill="$1" source_skills="$2" skill=""
  reply=()

  if [[ -n "$source_skill" ]]; then
    reply=("$source_skill")
    return 0
  fi

  for skill in "$source_skills"/*(N/); do
    reply+=("$skill")
  done
}

function _skills_normalize_target_skills_dir() {
  local target="$1" action="$2" reject_specific_skill="$3"

  if $reject_specific_skill && [[ "${target:h:t}" == "skills" ]]; then
    echo "$action: TARGET '$target' must be a directory containing skills/ or the skills/ directory itself" >&2
    return 1
  fi

  if [[ "${target:t}" == "skills" ]]; then
    REPLY="$target"
    return 0
  fi

  REPLY="$target/skills"
}

function _skills_normalize_targets() {
  local targets_csv="$1" action="$2" reject_specific_skill="${3:-false}" t=""
  reply=()

  for t in "${(@s/,/)targets_csv}"; do
    _skills_normalize_target_skills_dir "$t" "$action" "$reject_specific_skill" || return 1
    reply+=("$REPLY")
  done
}

function _skills_autodiscover_target_skills_dirs() {
  local target_skills=""
  reply=()

  for target_skills in ./.*/**/skills(N/); do
    reply+=("$target_skills")
  done
}

function _skills_remove_matching_symlink() {
  local source_skill="$1" target_skills="$2" resolved=""
  local link="$target_skills/${source_skill:t}"

  [[ -L "$link" ]] || return 1

  resolved="$(realpath "$link" 2>/dev/null)" || return 1
  [[ "$resolved" == "$source_skill" ]] || return 1

  rm "$link"
  echo "✓ skills unsync: removed $link"
}

function _skills_sync() {
  emulate -L zsh

  local source="" targets_csv="" install_hooks=false hooknames="pre-commit,post-merge"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --install-githooks)
        install_hooks=true
        if [[ -n "${2-}" && "$2" != --* ]]; then
          hooknames="$2"; shift
        fi
        ;;
      -*)
        echo "skills sync: unknown flag '$1'" >&2; return 1
        ;;
      *)
        if [[ -z "$source" ]]; then
          source="$1"
        elif [[ -z "$targets_csv" ]]; then
          targets_csv="$1"
        else
          echo "skills sync: unexpected argument '$1'" >&2; return 1
        fi
        ;;
    esac
    shift
  done

  if [[ -z "$source" || -z "$targets_csv" ]]; then
    echo "Usage: skills sync SOURCE TARGET[,TARGET,...] [--install-githooks [HOOKNAME,...]]" >&2
    return 1
  fi

  local -a source_info source_items target_skills_dirs
  _skills_normalize_source "$source" "skills sync" || return 1
  source_info=("${reply[@]}")

  local source_skill="${source_info[2]}" source_skills="${source_info[3]}" source_sync_label="${source_info[4]}"
  _skills_collect_source_skills "$source_skill" "$source_skills"
  source_items=("${reply[@]}")

  _skills_normalize_targets "$targets_csv" "skills sync"
  target_skills_dirs=("${reply[@]}")

  # --- 1. Sync symlinks ---
  local skill="" target_skills=""
  for skill in "${source_items[@]}"; do
    _skill_sync "$skill" "${target_skills_dirs[@]}"
  done

  for target_skills in "${target_skills_dirs[@]}"; do
    echo "✓ skills sync: $source_sync_label → $target_skills"
  done

  # --- 2. Install git hooks if requested ---
  $install_hooks || return 0

  local repo_root
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "skills sync: --install-githooks requires a git repo" >&2; return 1
  }

  local hooks_dir="$repo_root/.githooks"
  mkdir -p "$hooks_dir"

  local source_hook_expr
  if [[ -n "$source_skill" ]]; then
    source_hook_expr="$(_skills_hook_path_expr "$source_skill" "$repo_root")"
  else
    source_hook_expr="$(_skills_hook_path_expr "$source_skills" "$repo_root")"
  fi

  # Build bash-syntax targets array for the hook.
  local targets_literal="("
  for target_skills in "${target_skills_dirs[@]}"; do
    targets_literal+="$(_skills_hook_path_expr "$target_skills" "$repo_root") "
  done
  targets_literal="${targets_literal% })"

  local -a hooks=("${(@s/,/)hooknames}")
  for hook in "${hooks[@]}"; do
    local hook_file="$hooks_dir/$hook"

    # Heuristic: if file already contains ln -sfn, assume skills sync is present
    if [[ -f "$hook_file" ]] && grep -q 'ln -sfn' "$hook_file"; then
      echo "skills sync: $hook_file already has symlink logic, skipping" >&2
      continue
    fi

    # Create with shebang if new
    if [[ ! -f "$hook_file" ]]; then
      printf '#!/usr/bin/env bash\nset -euo pipefail\n' > "$hook_file"
    fi

    # git add only makes sense in pre-commit
    local git_add=""
    [[ "$hook" == "pre-commit" ]] && git_add=$'\n    git add "$_target_skills"'

    cat >> "$hook_file" <<HOOK

# --- skills-sync: $source_sync_label → ${targets_csv} ---
_repo_root="\$(git rev-parse --show-toplevel)"
_skills_source=$source_hook_expr
_skills_targets=$targets_literal
if [ -d "\$_skills_source" ]; then
  for _t in "\${_skills_targets[@]}"; do
    _target_skills="\$_t"
    mkdir -p "\$_target_skills"
HOOK
    if [[ -n "$source_skill" ]]; then
      cat >> "$hook_file" <<HOOK
    ln -sfn "\$_skills_source" "\$_target_skills/\$(basename "\$_skills_source")"$git_add
HOOK
    else
      cat >> "$hook_file" <<HOOK
    for _skill in "\$_skills_source"/*/; do
      [ -d "\$_skill" ] || continue
      ln -sfn "\$_skill" "\$_target_skills/\$(basename "\$_skill")"
    done$git_add
HOOK
    fi

    cat >> "$hook_file" <<HOOK
  done
fi
# --- end skills-sync ---
HOOK
    chmod +x "$hook_file"
    echo "✓ skills sync: installed into $hook_file"
  done

  # --- 3. setup.sh ---
  local setup_file="$repo_root/setup.sh"
  local config_line='git config --local core.hooksPath "$(git rev-parse --show-toplevel)/.githooks"'

  if [[ ! -f "$setup_file" ]]; then
    printf '#!/usr/bin/env bash\nset -euo pipefail\n' > "$setup_file"
    chmod +x "$setup_file"
  fi
  if ! grep -qF 'core.hooksPath' "$setup_file"; then
    echo "$config_line" >> "$setup_file"
    echo "✓ skills sync: added hooksPath to $setup_file"
  else
    echo "✓ skills sync: $setup_file already configured, skipping"
  fi

  # Run the config now
  git config --local core.hooksPath "$hooks_dir"
  echo "✓ skills sync: set core.hooksPath → $hooks_dir"
}

function _skills_unsync() {
  emulate -L zsh

  local source="" targets_csv=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -*)
        echo "skills unsync: unknown flag '$1'" >&2; return 1
        ;;
      *)
        if [[ -z "$source" ]]; then
          source="$1"
        elif [[ -z "$targets_csv" ]]; then
          targets_csv="$1"
        else
          echo "skills unsync: unexpected argument '$1'" >&2; return 1
        fi
        ;;
    esac
    shift
  done

  if [[ -z "$source" ]]; then
    echo "Usage: skills unsync SOURCE [TARGET[,TARGET,...]]" >&2
    return 1
  fi

  local -a source_info source_items target_skills_dirs
  _skills_normalize_source "$source" "skills unsync" || return 1
  source_info=("${reply[@]}")

  local source_skill="${source_info[2]}" source_skills="${source_info[3]}"
  _skills_collect_source_skills "$source_skill" "$source_skills"
  source_items=("${reply[@]}")

  if [[ -n "$targets_csv" ]]; then
    _skills_normalize_targets "$targets_csv" "skills unsync" true || return 1
    target_skills_dirs=("${reply[@]}")
  else
    _skills_autodiscover_target_skills_dirs
    target_skills_dirs=("${reply[@]}")
  fi

  local source_item="" target_skills=""
  local -i removed=0

  for source_item in "${source_items[@]}"; do
    for target_skills in "${target_skills_dirs[@]}"; do
      if _skills_remove_matching_symlink "$source_item" "$target_skills"; then
        ((removed += 1))
      fi
    done
  done

  if (( removed == 0 )); then
    echo "skills unsync: no matching symlinks found" >&2
  fi
}
