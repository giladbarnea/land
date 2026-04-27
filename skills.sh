#!/usr/bin/env zsh

# # skills sync SOURCE TARGET[,TARGET,...] [--install-githooks [HOOKNAME[,HOOKNAME,...]]]
#
# Syncs skills from SOURCE into each TARGET/skills/ as individual symlinks (ln -sfn).
# SOURCE may be a parent directory containing skills/, the skills/ directory itself, or a specific skills/<name> directory.
# TARGET may be a parent directory (e.g. .claude) or a skills/ directory directly.
#
# --install-githooks: writes the sync logic into .githooks/HOOKNAME (default: pre-commit,post-merge),
#   creates .githooks/setup.sh with the git config line, and runs `git config --local core.hooksPath`.
#
# Examples:
#   skills sync .agents .claude
#   skills sync ~/.agents ~/.claude,~/.pi/agent,~/.codex,~/.gemini
#   skills sync .agents .claude,.pi/agent --install-githooks
#   skills sync .agents/skills .claude,.pi --install-githooks pre-commit
#   skills sync .agents/skills/my-skill .claude
function skills() {
  case "${1-}" in
    sync) shift; _skills_sync "$@" ;;
    '')   echo "Usage: skills <sync> ..." >&2; return 1 ;;
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
    local rel_path="${path#$repo_root/}"
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

function _skills_sync() {
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

  # Normalize SOURCE into either:
  # - batch mode:   source_skills=/.../skills
  # - single mode:  source_skill=/.../skills/<skill>, source_skills=${source_skill:h}
  local source_skills="" source_skill="" source_sync_label=""
  if [[ -d "$source" && "${source:h:t}" == "skills" ]]; then
    source_skill="$(realpath "$source" 2>/dev/null)" || {
      echo "skills sync: cannot resolve SOURCE '$source'" >&2; return 1
    }
    source_skills="${source_skill:h}"
    source_sync_label="$source_skill"
  elif [[ -d "$source" && "${source:t}" == "skills" ]]; then
    source_skills="$(realpath "$source" 2>/dev/null)" || {
      echo "skills sync: cannot resolve SOURCE '$source'" >&2; return 1
    }
    source_sync_label="$source_skills"
  elif source_skills="$(realpath "$source/skills" 2>/dev/null)"; then
    source_sync_label="$source_skills"
  else
    echo "skills sync: SOURCE '$source' is neither a skills directory, nor a parent containing skills/, nor a specific skill inside skills/" >&2
    return 1
  fi

  local -a target_skills_dirs=()
  local t target_skills
  for t in "${(@s/,/)targets_csv}"; do
    if [[ "${t:t}" == "skills" ]]; then
      target_skills_dirs+=("$t")
    else
      target_skills_dirs+=("$t/skills")
    fi
  done

  # --- 1. Sync symlinks ---
  local skill
  if [[ -n "$source_skill" ]]; then
    _skill_sync "$source_skill" "${target_skills_dirs[@]}"
  else
    for skill in "$source_skills"/*(N/); do
      _skill_sync "$skill" "${target_skills_dirs[@]}"
    done
  fi

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
