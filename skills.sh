#!/usr/bin/env zsh

# # skills sync SOURCE TARGET[,TARGET,...] [--install-githooks [HOOKNAME[,HOOKNAME,...]]]
#
# Syncs skill directories from SOURCE/skills/* into each TARGET/skills/ as individual symlinks (ln -sfn).
# SOURCE and TARGET are parent directories (e.g. .agents, .claude) — /skills is appended automatically.
#
# --install-githooks: writes the sync logic into .githooks/HOOKNAME (default: pre-commit,post-merge),
#   creates .githooks/setup.sh with the git config line, and runs `git config --local core.hooksPath`.
#
# Examples:
#   skills sync .agents .claude
#   skills sync ~/.agents ~/.claude,~/.pi/agent,~/.codex,~/.gemini
#   skills sync .agents claude,gemini,codex,pi
#   skills sync .agents .claude,.pi/agent --install-githooks
#   skills sync .agents .claude,.pi/agent --install-githooks pre-commit
function skills() {
  case "${1-}" in
    sync) shift; _skills_sync "$@" ;;
    '')   echo "Usage: skills <sync> ..." >&2; return 1 ;;
    *)    echo "skills: unknown subcommand '$1'" >&2; return 1 ;;
  esac
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

  local source_skills
  source_skills="$(realpath "$source/skills" 2>/dev/null)" || {
    echo "skills sync: $source/skills not found" >&2; return 1
  }

  local -A _aliases=(
    claude  .claude
    gemini  .gemini
    codex   .codex
    pi      .pi/agent
  )

  local -a targets=()
  for t in "${(@s/,/)targets_csv}"; do
    targets+=("${_aliases[$t]:-$t}")
  done

  # --- 1. Sync symlinks ---
  local skill name target_skills
  for target in "${targets[@]}"; do
    target_skills="$target/skills"
    mkdir -p "$target_skills"
    for skill in "$source_skills"/*(N/); do
      name="${skill:t}"
      ln -sfn "$skill" "$target_skills/$name"
    done
    echo "skills sync: $source_skills → $target_skills"
  done

  # --- 2. Install git hooks if requested ---
  $install_hooks || return 0

  local repo_root
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "skills sync: --install-githooks requires a git repo" >&2; return 1
  }

  local hooks_dir="$repo_root/.githooks"
  mkdir -p "$hooks_dir"

  # Source path relative to repo root, for embedding in hook scripts
  local rel_source="${source#$repo_root/}"

  # Build bash-syntax targets array for the hook: ("t1" "t2")
  local targets_literal="("
  for target in "${targets[@]}"; do
    targets_literal+="\"${target#$repo_root/}\" "
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

# --- skills-sync: $rel_source → ${targets_csv} ---
_repo_root="\$(git rev-parse --show-toplevel)"
_skills_source="\$_repo_root/$rel_source/skills"
_skills_targets=$targets_literal
if [ -d "\$_skills_source" ]; then
  for _t in "\${_skills_targets[@]}"; do
    _target_skills="\$_repo_root/\$_t/skills"
    mkdir -p "\$_target_skills"
    for _skill in "\$_skills_source"/*/; do
      [ -d "\$_skill" ] || continue
      ln -sfn "\$_skill" "\$_target_skills/\$(basename "\$_skill")"
    done$git_add
  done
fi
# --- end skills-sync ---
HOOK
    chmod +x "$hook_file"
    echo "skills sync: installed into $hook_file"
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
    echo "skills sync: added hooksPath to $setup_file"
  else
    echo "skills sync: $setup_file already configured, skipping"
  fi

  # Run the config now
  git config --local core.hooksPath "$hooks_dir"
  echo "skills sync: set core.hooksPath → $hooks_dir"
}
