#!/usr/bin/env zsh
#
# Bare skills live in .agents/skills (user-scoped: ~/.agents/skills; project-scoped: .agents/skills).
# Each provider can also contain plugins/*/skills in either scope.
# Skills are symlinked into each CLI agent's skills directory for reuse:
#
#   User-level                Project-level
#   ~/.pi/agent/skills        .pi/skills
#   ~/.claude/skills          .claude/skills
#   ~/.codex/skills           .codex/skills
#   ~/.gemini/skills          .gemini/skills
#   ~/.antigravity/skills     .antigravity/skills
#
# Pi quirk: user-level uses ~/.pi/agent/skills (not ~/.pi/skills). Project-level is .pi/skills.
# This script manages the symlink plumbing from a canonical SOURCE into one or more TARGETs.

# # skills sync SOURCE TARGET[,TARGET,...] [--install-githooks [HOOKNAME[,HOOKNAME,...]]]
# # skills unsync SOURCE [TARGET[,TARGET,...]]
#
# skills sync:
#   Syncs skills from SOURCE into each TARGET/skills/ as individual symlinks (ln -sfn).
#   Asks whether to remove each target symlink whose skill is absent from SOURCE.
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
#   skills sync ~/.agents ~/.claude,~/.pi/agent,~/.codex,~/.gemini,~/.antigravity
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

typeset -ga _skills_cli_providers=(pi claude codex gemini antigravity)
typeset -gA _skills_provider_parent_dirs=(
  [agents]=.agents
  [pi]=.pi
  [claude]=.claude
  [codex]=.codex
  [gemini]=.gemini
  [antigravity]=.antigravity
)

function _skills_known_provider_message() {
  printf 'agents, pi, claude, codex, gemini, antigravity'
}

function _skills_is_cli_provider() {
  emulate -L zsh
  local provider="$1"
  [[ -n "$provider" && "${_skills_cli_providers[(r)$provider]}" == "$provider" ]]
}

function _skills_validate_provider() {
  emulate -L zsh
  local provider="${1-}"

  [[ -z "$provider" || "$provider" == agents ]] && return 0
  _skills_is_cli_provider "$provider" && return 0

  echo "skills: unknown provider '$provider'. Expected: $(_skills_known_provider_message)" >&2
  return 1
}

function _skills_provider_parent_dir() {
  emulate -L zsh
  local provider="$1"

  _skills_validate_provider "$provider" || return 1
  REPLY="${_skills_provider_parent_dirs[$provider]}"
}

typeset -ga _skills_normalized_target_modes=()

function _skill_sync_to_target() {
  local skill="$1" target="$2" target_mode="$3"
  local skill_name="${skill:t}"

  if [[ "$target_mode" == "skill" ]]; then
    mkdir -p "${target:h}"
    ln -sfn "$skill" "$target"
    return 0
  fi

  mkdir -p "$target"
  ln -sfn "$skill" "$target/$skill_name"
}

function _skill_sync() {
  local skill="$1"
  shift

  local target_skills=""
  for target_skills in "$@"; do
    _skill_sync_to_target "$skill" "$target_skills" base
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

function _skills_canonicalize_pi_home_skills_dir() {
  # Pi quirk: the home-level .pi skills dir is ~/.pi/agent/skills, never ~/.pi/skills.
  # Whatever angle resolved a target to the home .pi skills dir, force the agent/ path.
  emulate -L zsh
  local skills_dir="$1" absolute="$1" home_absolute="${HOME:A}"
  [[ "$absolute" == /* ]] || absolute="$PWD/$absolute"

  if [[ "${absolute:A}" == "$home_absolute/.pi/skills" ]]; then
    REPLY="$HOME/.pi/agent/skills"
  else
    REPLY="$skills_dir"
  fi
}

function _skills_warn_if_legacy_home_pi_target() {
  emulate -L zsh
  local action="$1" target="$2" absolute="$2" home_absolute="${HOME:A}"
  [[ "$absolute" == /* ]] || absolute="$PWD/$absolute"

  if [[ "${absolute:A}" == "$home_absolute/.pi/skills" || "${absolute:A}" == "$home_absolute/.pi/skills/"* ]]; then
    echo "$action: Note: TARGET '$target' is under ~/.pi/skills. Pi user-level skills normally live at ~/.pi/agent/skills." >&2
  fi
}

function _skills_normalize_target_skills_dir() {
  local target="$1" action="$2" reject_specific_skill="$3"
  _skills_normalized_target_mode=base

  case "$target" in
    pi|claude|codex|gemini|antigravity)
      _skills_provider_base_relative_path "$target" "$PWD" || return 1
      return 0
      ;;
  esac

  if [[ "${target:h:t}" == "skills" ]]; then
    _skills_warn_if_legacy_home_pi_target "$action" "$target"
    REPLY="$target"
    _skills_normalized_target_mode=skill
    return 0
  fi

  if [[ "${target:t}" == "skills" ]]; then
    _skills_warn_if_legacy_home_pi_target "$action" "$target"
    REPLY="$target"
    return 0
  fi

  _skills_canonicalize_pi_home_skills_dir "$target/skills"
}

function _skills_normalize_targets() {
  local targets_csv="$1" action="$2" reject_specific_skill="${3:-false}" t=""
  reply=()
  _skills_normalized_target_modes=()

  for t in "${(@s/,/)targets_csv}"; do
    _skills_normalize_target_skills_dir "$t" "$action" "$reject_specific_skill" || return 1
    reply+=("$REPLY")
    _skills_normalized_target_modes+=("$_skills_normalized_target_mode")
  done
}

function _skills_autodiscover_target_skills_dirs() {
  local target_skills=""
  reply=()

  for target_skills in ./.*/**/skills(N/); do
    reply+=("$target_skills")
  done
}

function _skills_confirm_orphaned_link_removal() {
  emulate -L zsh
  local orphaned_link="$1" reply=""

  [[ -t 1 ]] || {
    echo "skills sync: no TTY; keeping orphaned link $orphaned_link" >&2
    return 1
  }

  printf "Remove orphaned link '%s'? [y/N] " "$orphaned_link" >/dev/tty
  read -r reply </dev/tty || return 1
  [[ "$reply" == [Yy] ]]
}

function _skills_clean_orphaned_links_in_target() {
  emulate -L zsh
  local target_skills="$1" target_mode="$2" source_item="" source_skill_name=""
  local target_skill="" target_skill_name=""
  local -A source_skill_names
  shift 2

  [[ "$target_mode" == "base" ]] || return 0

  for source_item in "$@"; do
    source_skill_name="${source_item:t}"
    source_skill_names[$source_skill_name]=1
  done

  for target_skill in "$target_skills"/*(ND@); do
    target_skill_name="${target_skill:t}"
    [[ -n "${source_skill_names[$target_skill_name]-}" ]] && continue

    echo "skills sync: found orphaned link $target_skill" >&2
    _skills_confirm_orphaned_link_removal "$target_skill" || {
      echo "skills sync: kept $target_skill" >&2
      continue
    }
    rm -- "$target_skill" || return 1
    echo "✓ skills sync: removed $target_skill"
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

function _skills_remove_matching_exact_symlink() {
  local source_skill="$1" target_skill="$2" resolved=""

  [[ -L "$target_skill" ]] || return 1

  resolved="$(realpath "$target_skill" 2>/dev/null)" || return 1
  [[ "$resolved" == "$source_skill" ]] || return 1

  rm "$target_skill"
  echo "✓ skills unsync: removed $target_skill"
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

  local -a source_info source_items target_skills_dirs target_modes
  _skills_normalize_source "$source" "skills sync" || return 1
  source_info=("${reply[@]}")

  local source_skill="${source_info[2]}" source_skills="${source_info[3]}" source_sync_label="${source_info[4]}"
  _skills_collect_source_skills "$source_skill" "$source_skills"
  source_items=("${reply[@]}")

  _skills_normalize_targets "$targets_csv" "skills sync" || return 1
  target_skills_dirs=("${reply[@]}")
  target_modes=("${_skills_normalized_target_modes[@]}")

  local -i target_index=0
  for (( target_index = 1; target_index <= ${#target_skills_dirs}; target_index += 1 )); do
    if [[ "${target_modes[target_index]}" == "skill" && ${#source_items} -ne 1 ]]; then
      echo "skills sync: TARGET '${target_skills_dirs[target_index]}' is a specific skill path and requires exactly one source skill" >&2
      return 1
    fi
  done

  # --- 1. Sync symlinks ---
  local skill="" target_skills=""
  for skill in "${source_items[@]}"; do
    for (( target_index = 1; target_index <= ${#target_skills_dirs}; target_index += 1 )); do
      _skill_sync_to_target "$skill" "${target_skills_dirs[target_index]}" "${target_modes[target_index]}"
    done
  done

  for target_skills in "${target_skills_dirs[@]}"; do
    echo "✓ skills sync: $source_sync_label → $target_skills"
  done

  for (( target_index = 1; target_index <= ${#target_skills_dirs}; target_index += 1 )); do
    _skills_clean_orphaned_links_in_target \
      "${target_skills_dirs[target_index]}" \
      "${target_modes[target_index]}" \
      "${source_items[@]}" || return 1
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

  local -a source_info source_items target_skills_dirs target_modes
  _skills_normalize_source "$source" "skills unsync" || return 1
  source_info=("${reply[@]}")

  local source_skill="${source_info[2]}" source_skills="${source_info[3]}"
  _skills_collect_source_skills "$source_skill" "$source_skills"
  source_items=("${reply[@]}")

  local source_item="" target_skills=""

  if [[ -n "$targets_csv" ]]; then
    _skills_normalize_targets "$targets_csv" "skills unsync" || return 1
    target_skills_dirs=("${reply[@]}")
    target_modes=("${_skills_normalized_target_modes[@]}")
  else
    _skills_autodiscover_target_skills_dirs
    target_skills_dirs=("${reply[@]}")
    target_modes=()
    for target_skills in "${target_skills_dirs[@]}"; do
      target_modes+=(base)
    done
  fi

  local -i target_index=0
  for (( target_index = 1; target_index <= ${#target_skills_dirs}; target_index += 1 )); do
    if [[ "${target_modes[target_index]}" == "skill" && ${#source_items} -ne 1 ]]; then
      echo "skills unsync: TARGET '${target_skills_dirs[target_index]}' is a specific skill path and requires exactly one source skill" >&2
      return 1
    fi
  done

  local -i removed=0

  for source_item in "${source_items[@]}"; do
    for (( target_index = 1; target_index <= ${#target_skills_dirs}; target_index += 1 )); do
      target_skills="${target_skills_dirs[target_index]}"
      if [[ "${target_modes[target_index]}" == "skill" ]]; then
        _skills_remove_matching_exact_symlink "$source_item" "$target_skills" && ((removed += 1))
      elif _skills_remove_matching_symlink "$source_item" "$target_skills"; then
        ((removed += 1))
      fi
    done
  done

  if (( removed == 0 )); then
    echo "skills unsync: no matching symlinks found" >&2
  fi
}

# --- Skill CRUD helpers -------------------------------------------------------

function _skills_resolve_scope() {
  # reply: navigation root, skills directory, plugins directory, provider.
  # Keep provider paths lexical so linked skills cannot change plugin discovery.
  emulate -L zsh
  local is_global="$1" provider="${2-}" root_dir="" skills_dir=""
  reply=()

  _skills_validate_provider "$provider" || return 1

  if [[ "$is_global" == false && -z "$provider" ]]; then
    [[ "${PWD:t}" == skills ]] && skills_dir="$PWD"
    [[ -z "$skills_dir" && -d "$PWD/skills" ]] && skills_dir="$PWD/skills"
  fi

  if [[ -n "$skills_dir" ]]; then
    reply=("$skills_dir" "$skills_dir" "" agents)
    return 0
  fi

  if [[ "$is_global" == true ]]; then
    root_dir="$HOME"
  else
    root_dir="$(git rev-parse --show-toplevel 2>/dev/null)" || {
      echo 'skills: no Git repository or CWD skills directory; use -g for global scope' >&2
      return 1
    }
    [[ -n "$root_dir" ]] || return 1
  fi

  provider="${provider:-agents}"
  _skills_provider_parent_dir "$provider" || return 1
  root_dir="$root_dir/$REPLY"
  [[ "$is_global" == true && "$provider" == pi ]] && root_dir="$HOME/.pi/agent"
  reply=("$root_dir" "$root_dir/skills" "$root_dir/plugins" "$provider")
}

function _skills_parse_access_arguments() {
  # Parse `[-g] [-p PROVIDER] [--] POSITIONAL...` for the sk* commands.
  # Sets reply to (is_global provider positional...). Rejects more than MAX_POSITIONALS positionals.
  emulate -L zsh
  local caller_name="$1" argument=""
  local -i max_positionals="$2"
  shift 2

  local is_global="false" provider="" expect_provider="false"
  local -a positionals
  reply=()

  while [[ $# -gt 0 ]]; do
    argument="$1"
    shift

    if [[ "$expect_provider" == "true" ]]; then
      provider="$argument"
      expect_provider="false"
      continue
    fi

    case "$argument" in
      --) positionals+=("$@"); set -- ;;
      -g) is_global="true" ;;
      -p) expect_provider="true" ;;
      -*)
        echo "$caller_name: unknown flag '$argument'" >&2
        return 1
        ;;
      *)  positionals+=("$argument") ;;
    esac
  done

  if [[ "$expect_provider" == "true" ]]; then
    echo "$caller_name: option '-p' requires a provider" >&2
    return 1
  fi

  if (( ${#positionals} > max_positionals )); then
    echo "$caller_name: unexpected argument '${positionals[max_positionals + 1]}'" >&2
    return 1
  fi

  reply=("$is_global" "$provider" "${positionals[@]}")
}

function _skills_strip() {
  emulate -L zsh
  local value="$1"

  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  REPLY="$value"
}

function _skills_yaml_double_quote() {
  emulate -L zsh
  local value="$1"

  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  REPLY="\"$value\""
}

function _skills_provider_base_relative_path() {
  emulate -L zsh
  local provider="${1-}" root_dir="${2:-$PWD}" parent_dir=""
  local root_absolute="${root_dir:A}" home_absolute="${HOME:A}"

  if [[ -z "$provider" || "$provider" == "agents" ]]; then
    REPLY=".agents/skills"
    return 0
  fi

  _skills_provider_parent_dir "$provider" || return 1
  parent_dir="$REPLY"

  if [[ "$provider" == "pi" && "$root_absolute" == "$home_absolute" ]]; then
    REPLY=".pi/agent/skills"
    return 0
  fi

  REPLY="$parent_dir/skills"
}

function _skills_prompt_required_value() {
  emulate -L zsh
  local caller_name="$1" label="$2" prompt="$3" value=""

  value="$(input "$prompt")" || return 1
  _skills_strip "$value"
  value="$REPLY"

  if [[ -z "$value" ]]; then
    echo "$caller_name: $label cannot be empty" >&2
    return 1
  fi

  REPLY="$value"
}

function _skills_resolve_target() {
  # reply: target kind, navigation root, content directories.
  emulate -L zsh
  local name="$1" root_dir="$2" skills_dir="$3" plugins_dir="$4" provider="$5" caller_name="$6"
  local directory=""
  local -a directories
  reply=()

  if [[ -z "$name" || "$name" == "$provider" ]]; then
    for directory in "$skills_dir" "$plugins_dir"; do
      [[ -d "$directory" ]] && directories+=("$directory")
    done
    (( ${#directories} )) || {
      echo "$caller_name: no skills or plugins in $root_dir" >&2
      return 1
    }
    reply=(scope "$root_dir" "${directories[@]}")
    return 0
  fi

  if [[ "$name" == */* || "$name" == . || "$name" == .. ]]; then
    echo "$caller_name: '$name' is a path; pass a skill or plugin name" >&2
    return 1
  fi

  directories=("$skills_dir/$name")
  [[ -n "$plugins_dir" ]] && directories+=("$plugins_dir"/*/skills/"$name"(N-/))
  for directory in "${directories[@]}"; do
    [[ -d "$directory" ]] || continue
    [[ -f "$directory/SKILL.md" ]] || {
      echo "$caller_name: '$name' in ${directory:h} is not a skill (missing SKILL.md)" >&2
      return 1
    }
    reply=(skill "${directory:A}" "${directory:A}")
    return 0
  done

  if [[ -n "$plugins_dir" && -d "$plugins_dir/$name" ]]; then
    directory="$plugins_dir/$name"
    reply=(plugin "${directory:A}" "${directory:A}")
    return 0
  fi

  echo "$caller_name: skill or plugin '$name' not found in $root_dir" >&2
  return 1
}

function _skills_resolve_file_path() {
  emulate -L zsh
  local relative_path="$1" target_root="$2" caller_name="$3" directory="" resolved_path=""
  local candidate_path="$target_root/$relative_path" ancestor_dir="" boundary_dir=""
  local -a boundary_dirs
  shift 3

  resolved_path="$(realpath "$candidate_path" 2>/dev/null)"
  [[ -f "$resolved_path" ]] || {
    echo "$caller_name: '$relative_path' is not an existing file in $target_root" >&2
    return 1
  }

  for directory in "$@"; do
    [[ "${candidate_path:a}" == "${directory:a}"/* ]] || continue
    boundary_dirs=("${directory:A}")
    ancestor_dir="${candidate_path:a:h}"
    while [[ "$ancestor_dir" != "${directory:a}" ]]; do
      [[ -L "$ancestor_dir" ]] && boundary_dirs+=("${ancestor_dir:A}")
      ancestor_dir="${ancestor_dir:h}"
    done
    for boundary_dir in "${boundary_dirs[@]}"; do
      [[ "$resolved_path" == "$boundary_dir"/* ]] || continue
      REPLY="$resolved_path"
      return 0
    done
  done

  echo "$caller_name: '$relative_path' resolves outside the selected content" >&2
  return 1
}

function _skills_format_path_with_home_tilde() {
  emulate -L zsh
  local file_path="$1" home_dir="${HOME:A}"

  if [[ "$file_path" == "$home_dir" ]]; then
    REPLY='~'
    return 0
  fi

  if [[ "$file_path" == "$home_dir"/* ]]; then
    REPLY="~/${file_path#"$home_dir"/}"
    return 0
  fi

  REPLY="$file_path"
}

function _skills_format_path_relative_to_pwd() {
  emulate -L zsh
  local target_path="$1" from_path="${2:-${PWD:A}}"
  local -a from_segments target_segments relative_segments
  local -i common_length=0 index=0

  [[ "$target_path" == /* ]] || target_path="$PWD/$target_path"
  [[ "$from_path" == /* ]] || from_path="$PWD/$from_path"

  from_segments=("${(@s:/:)from_path}")
  target_segments=("${(@s:/:)target_path}")

  while (( common_length < ${#from_segments} && common_length < ${#target_segments} )); do
    index=$(( common_length + 1 ))
    [[ "${from_segments[index]}" == "${target_segments[index]}" ]] || break
    (( common_length += 1 ))
  done

  for (( index = common_length + 1; index <= ${#from_segments}; index += 1 )); do
    relative_segments+=("..")
  done

  for (( index = common_length + 1; index <= ${#target_segments}; index += 1 )); do
    relative_segments+=("${target_segments[index]}")
  done

  if (( ${#relative_segments} == 0 )); then
    REPLY='.'
    return 0
  fi

  REPLY="${(j:/:)relative_segments}"
  [[ "$REPLY" == ..* ]] || REPLY="./$REPLY"
}

function _skills_format_source_path_for_display() {
  emulate -L zsh
  local file_path="$1" relative_path="" home_path=""

  _skills_format_path_relative_to_pwd "$file_path"
  relative_path="$REPLY"

  _skills_format_path_with_home_tilde "$file_path"
  home_path="$REPLY"

  if (( ${#relative_path} <= ${#home_path} )); then
    REPLY="$relative_path"
  else
    REPLY="$home_path"
  fi
}

function _skills_collect_accessible_skill_names() {
  emulate -L zsh
  local skills_dir="$1" plugins_dir="$2" provider="$3" skill_file="" plugin_dir=""
  local -a skill_files
  local -aU names=("$provider")

  skill_files=("$skills_dir"/*/SKILL.md(ND.))
  [[ -n "$plugins_dir" ]] && skill_files+=("$plugins_dir"/*/skills/*/SKILL.md(ND.))
  for skill_file in "${skill_files[@]}"; do
    names+=("${skill_file:h:t}")
  done

  if [[ -n "$plugins_dir" ]]; then
    for plugin_dir in "$plugins_dir"/*(N-/); do
      names+=("${plugin_dir:t}")
    done
  fi

  reply=("${names[@]}")
}

function _skills_collect_paths() {
  emulate -L zsh
  local root=""
  reply=()
  for root in "$@"; do
    reply+=("$root" "$root"/***/*(ND))
  done
}

function _skills_read_files_recursively() {
  emulate -L zsh
  local file_path="" mime_encoding=""
  local -a file_paths

  _skills_collect_paths "$@"
  for file_path in "${reply[@]}"; do
    [[ -f "$file_path" ]] || continue
    mime_encoding="$(file --mime-encoding -b -L -- "$file_path")"
    [[ -s "$file_path" && "$mime_encoding" == binary ]] && continue
    file_paths+=("$file_path")
  done

  (( ${#file_paths} )) || {
    echo 'skr: no readable files in the selected content' >&2
    return 1
  }
  bat "${file_paths[@]}"
}

function skcr() {
  # Create a skill. Usage: skcr [-g] [-p PROVIDER] SKILL-NAME
  emulate -L zsh
  local is_global="false" provider="" skill_name="" skill_dir="" skill_file=""
  local skill_name_yaml="" skill_description_yaml=""

  _skills_parse_access_arguments "skcr" 1 "$@" || return 1
  is_global="${reply[1]}"
  provider="${reply[2]}"
  skill_name="${reply[3]-}"

  if [[ -z "$skill_name" ]]; then
    echo "Usage: skcr [-g] [-p PROVIDER] SKILL-NAME" >&2
    return 1
  fi

  if [[ "$skill_name" == */* ]]; then
    echo "skcr: '$skill_name' is a path. Pass a skill name and pick the directory with -g and -p" >&2
    return 1
  fi

  _skills_resolve_scope "$is_global" "$provider" || return 1
  skill_dir="${reply[2]}/$skill_name"
  skill_file="$skill_dir/SKILL.md"

  if [[ -e "$skill_dir" || -L "$skill_dir" ]]; then
    echo "skcr: skill already exists: $skill_dir" >&2
    return 1
  fi

  _skills_prompt_required_value "skcr" "description" "Skill description:" || return 1
  _skills_yaml_double_quote "$REPLY"
  skill_description_yaml="$REPLY"
  _skills_yaml_double_quote "$skill_name"
  skill_name_yaml="$REPLY"

  mkdir -p "$skill_dir" || return 1
  {
    print -- "---"
    print -- "name: $skill_name_yaml"
    print -- "description: $skill_description_yaml"
    print -- "---"
    print
  } > "$skill_file" || return 1

  ${EDITOR:-vim} "$skill_file"
}

function _skills_access() {
  emulate -L zsh
  local caller_name="$1" is_global="" provider="" name="" relative_file_path=""
  local target_kind="" target_root="" selected_path=""
  local -i max_positionals=1
  local -a targets entries
  shift

  [[ "$caller_name" == skr ]] && max_positionals=2
  _skills_parse_access_arguments "$caller_name" "$max_positionals" "$@" || return 1
  is_global="${reply[1]}"
  provider="${reply[2]}"
  name="${reply[3]-}"
  relative_file_path="${reply[4]-}"

  _skills_resolve_scope "$is_global" "$provider" || return 1
  _skills_resolve_target "$name" "${reply[@]}" "$caller_name" || return 1
  target_kind="${reply[1]}"
  target_root="${reply[2]}"
  targets=("${reply[@]:2}")

  if [[ -n "$relative_file_path" ]]; then
    _skills_resolve_file_path "$relative_file_path" "$target_root" "$caller_name" "${targets[@]}" || return 1
    bat "$REPLY"
    return
  fi

  case "$caller_name" in
    skcd) cd "$target_root" ;;
    skt) tree --no-git-ignore --follow-symlinks -- "${targets[@]}" ;;
    skr) _skills_read_files_recursively "${targets[@]}" ;;
    ske)
      [[ "$target_kind" == skill ]] && entries=("$target_root"/*(ND))
      [[ ${#entries} == 1 && "${entries[1]}" == "$target_root/SKILL.md" ]] && targets=("${entries[1]}")
      ${EDITOR:-vim} "${targets[@]}"
      ;;
    skl)
      _skills_collect_paths "${targets[@]}"
      for selected_path in "${reply[@]}"; do
        _skills_format_source_path_for_display "${selected_path:A}"
        print -r -- "$REPLY"
      done
      ;;
  esac
}

# Usage: COMMAND [-g] [-p PROVIDER] [NAME]. skr also accepts [RELATIVE-FILE-PATH].
function skr() { _skills_access skr "$@" }
function ske() { _skills_access ske "$@" }
function skcd() { _skills_access skcd "$@" }
function skt() { _skills_access skt "$@" }
function skl() { _skills_access skl "$@" }
