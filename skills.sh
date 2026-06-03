#!/usr/bin/env zsh
#
# Skills live in .agents/skills (user-scoped: ~/.agents/skills; project-scoped: .agents/skills).
# They're symlinked into each CLI agent's skills directory for reuse:
#
#   User-level                Project-level
#   ~/.pi/agent/skills        .pi/skills
#   ~/.claude/skills          .claude/skills
#   ~/.codex/skills           .codex/skills
#   ~/.gemini/skills          .gemini/skills
#
# Pi quirk: user-level uses ~/.pi/agent/skills (not ~/.pi/skills). Project-level is .pi/skills.
# This script manages the symlink plumbing from a canonical SOURCE into one or more TARGETs.

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

function _skills_canonicalize_pi_home_skills_dir() {
  # Pi quirk: the home-level .pi skills dir is ~/.pi/agent/skills, never ~/.pi/skills.
  # Whatever angle resolved a target to the home .pi skills dir, force the agent/ path.
  emulate -L zsh
  local skills_dir="$1" absolute="$1"
  [[ "$absolute" == /* ]] || absolute="$PWD/$absolute"

  if [[ "${absolute:A}" == "$HOME/.pi/skills" ]]; then
    REPLY="$HOME/.pi/agent/skills"
  else
    REPLY="$skills_dir"
  fi
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

  _skills_canonicalize_pi_home_skills_dir "$target/skills"
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

# --- Skill CRUD helpers -------------------------------------------------------

function _skills_hidden_base_dir_relative_paths() {
  emulate -L zsh
  local provider="${1-}"
  reply=()

  case "$provider" in
    "")
      reply=(
        ".agents/skills"
        ".pi/agent/skills"
        ".claude/skills"
        ".codex/skills"
        ".gemini/skills"
        ".pi/skills"
      )
      ;;
    pi)      reply=(".pi/agent/skills" ".pi/skills") ;;
    claude)  reply=(".claude/skills") ;;
    codex)   reply=(".codex/skills") ;;
    gemini)  reply=(".gemini/skills") ;;
    *)
      echo "skills: unknown provider '$provider'. Expected: pi, claude, codex, gemini" >&2
      return 1
      ;;
  esac
}

function _skills_detect_provider_from_base_dir() {
  emulate -L zsh
  local base_dir="$1" parent_dir_name="${base_dir:h:t}" grandparent_dir_name="${base_dir:h:h:t}"

  [[ "${base_dir:t}" == "skills" ]] || {
    echo "skills: expected a skills directory, got '$base_dir'" >&2
    return 1
  }

  case "$parent_dir_name" in
    .agents) REPLY="agents" ;;
    .claude) REPLY="claude" ;;
    .codex)  REPLY="codex" ;;
    .gemini) REPLY="gemini" ;;
    .pi)     REPLY="pi" ;;
    agent)
      if [[ "$grandparent_dir_name" == ".pi" ]]; then
        REPLY="pi"
      else
        REPLY="unknown"
      fi
      ;;
    *) REPLY="unknown" ;;
  esac
}

function _skills_base_dir_matches_provider() {
  emulate -L zsh
  local base_dir="$1" provider="${2-}"

  [[ -d "$base_dir" && "${base_dir:t}" == "skills" ]] || return 1
  [[ -z "$provider" ]] && return 0

  _skills_detect_provider_from_base_dir "$base_dir" || return 1
  [[ "$REPLY" == "$provider" ]]
}

function _skills_resolve_existing_dir() {
  emulate -L zsh
  local path="$1" resolved=""

  resolved="$(realpath "$path" 2>/dev/null)"
  [[ -n "$resolved" ]] || resolved="$path"
  REPLY="$resolved"
}

function _skills_find_nearest_plain_base_dir() {
  emulate -L zsh
  local provider="${1-}" current_dir="${PWD:A}" candidate=""

  while true; do
    if [[ "$current_dir:t" == "skills" ]] && _skills_base_dir_matches_provider "$current_dir" "$provider"; then
      _skills_resolve_existing_dir "$current_dir"
      return 0
    fi

    candidate="$current_dir/skills"
    if _skills_base_dir_matches_provider "$candidate" "$provider"; then
      _skills_resolve_existing_dir "$candidate"
      return 0
    fi

    [[ "$current_dir" == "/" ]] && break
    current_dir="$current_dir:h"
  done

  return 1
}

function _skills_find_nearest_hidden_base_dir() {
  emulate -L zsh
  local provider="${1-}" current_dir="${PWD:A}" candidate="" relative_path=""
  local -a relative_paths

  _skills_hidden_base_dir_relative_paths "$provider" || return 1
  relative_paths=("${reply[@]}")

  while true; do
    for relative_path in "${relative_paths[@]}"; do
      candidate="$current_dir/$relative_path"
      if [[ -d "$candidate" ]]; then
        _skills_resolve_existing_dir "$candidate"
        return 0
      fi
    done

    [[ "$current_dir" == "/" ]] && break
    current_dir="$current_dir:h"
  done

  return 1
}

function _skills_find_local_base_dir() {
  emulate -L zsh
  local provider="${1-}"

  _skills_find_nearest_plain_base_dir "$provider" && return 0
  _skills_find_nearest_hidden_base_dir "$provider" && return 0

  if [[ -n "$provider" ]]; then
    echo "skills: could not find local $provider skills from ${PWD:A} upward" >&2
  else
    echo "skills: could not find local skills from ${PWD:A} upward" >&2
  fi
  return 1
}

function _skills_base_dir() {
  # Resolve the skills directory from -g (global) and -p (provider) flags.
  # Sets REPLY to the resolved path.
  emulate -L zsh
  local global="$1" provider="${2-}" base_dir=""

  if [[ "$global" == "true" ]]; then
    case "$provider" in
      pi)      base_dir="$HOME/.pi/agent/skills" ;;
      claude)  base_dir="$HOME/.claude/skills" ;;
      codex)   base_dir="$HOME/.codex/skills" ;;
      gemini)  base_dir="$HOME/.gemini/skills" ;;
      "")      base_dir="$HOME/.agents/skills" ;;
      *)
        echo "skills: unknown provider '$provider'. Expected: pi, claude, codex, gemini" >&2
        return 1
        ;;
    esac

    if [[ ! -d "$base_dir" ]]; then
      echo "skills: directory not found: $base_dir" >&2
      return 1
    fi

    _skills_resolve_existing_dir "$base_dir"
    return 0
  fi

  _skills_find_local_base_dir "$provider"
}

function _skills_parse_access_arguments() {
  emulate -L zsh
  local caller_name="$1"
  shift

  local global="false" provider="" skill_name="" expect_provider="false" argument=""
  reply=()

  while [[ $# -gt 0 ]]; do
    argument="$1"

    if [[ "$expect_provider" == "true" ]]; then
      provider="$argument"
      expect_provider="false"
      shift
      continue
    fi

    case "$argument" in
      --)
        shift
        while [[ $# -gt 0 ]]; do
          [[ -n "$skill_name" ]] || skill_name="$1"
          shift
        done
        break
        ;;
      -g)
        global="true"
        ;;
      -p)
        expect_provider="true"
        ;;
      -*)
        echo "$caller_name: unknown flag '$argument'" >&2
        return 1
        ;;
      *)
        [[ -n "$skill_name" ]] || skill_name="$argument"
        ;;
    esac

    shift
  done

  if [[ "$expect_provider" == "true" ]]; then
    echo "$caller_name: option '-p' requires a provider" >&2
    return 1
  fi

  reply=("$global" "$provider" "$skill_name")
}

function _skills_resolve_target() {
  # Resolve the target path for a skill name within a base skills directory.
  # Sets REPLY to the path and _skills_target_mode to "file" or "dir".
  emulate -L zsh
  local skill_name="$1" base_dir="$2" caller_name="$3"
  local skill_dir="$base_dir/$skill_name"
  local -a all_entries subdirs

  if [[ ! -d "$skill_dir" ]]; then
    echo "$caller_name: skill '$skill_name' not found in $base_dir" >&2
    return 1
  fi

  if [[ ! -f "$skill_dir/SKILL.md" ]]; then
    echo "$caller_name: '$skill_name' in $base_dir is not a skill (missing SKILL.md)" >&2
    return 1
  fi

  all_entries=("$skill_dir"/*(N))
  subdirs=("$skill_dir"/*(N/))

  if (( ${#all_entries} == 1 )) && (( ${#subdirs} == 0 )) && [[ "${all_entries[1]:t}" == "SKILL.md" ]]; then
    REPLY="$skill_dir/SKILL.md"
    _skills_target_mode="file"
  else
    REPLY="$skill_dir"
    _skills_target_mode="dir"
  fi
}

function _skills_format_path_with_home_tilde() {
  emulate -L zsh
  local path="$1" home_dir="$HOME"

  if [[ "$path" == "$home_dir" ]]; then
    REPLY='~'
    return 0
  fi

  if [[ "$path" == "$home_dir"/* ]]; then
    REPLY="~/${path#"$home_dir"/}"
    return 0
  fi

  REPLY="$path"
}

function _skills_format_path_relative_to_pwd() {
  emulate -L zsh
  local target_path="$1" from_path="${2:-$PWD}"
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
  local path="$1" relative_path="" home_path=""

  _skills_format_path_relative_to_pwd "$path"
  relative_path="$REPLY"

  _skills_format_path_with_home_tilde "$path"
  home_path="$REPLY"

  if (( ${#relative_path} <= ${#home_path} )); then
    REPLY="$relative_path"
  else
    REPLY="$home_path"
  fi
}

function _skills_describe_base_dir_source() {
  emulate -L zsh
  local base_dir="$1" resolution_scope="$2" display_path=""

  if [[ "$resolution_scope" == "global" ]]; then
    _skills_format_path_with_home_tilde "$base_dir"
  else
    _skills_format_source_path_for_display "$base_dir"
  fi

  display_path="$REPLY"
  REPLY="$resolution_scope: $display_path"
}

function _skills_collect_resolvable_skill_names() {
  emulate -L zsh
  local base_dir="$1" entry="" entry_name=""
  reply=()

  [[ -d "$base_dir" ]] || {
    echo "skills: directory not found: $base_dir" >&2
    return 1
  }

  for entry in "$base_dir"/*(ND); do
    entry_name="${entry:t}"
    _skills_resolve_target "$entry_name" "$base_dir" "_skills_collect_resolvable_skill_names" >/dev/null 2>&1 || continue
    reply+=("$entry_name")
  done
}

function skr() {
  # Read a skill. Usage: skr [-g] [-p pi|claude|codex|gemini] [skill-name]
  emulate -L zsh
  local global="false" provider="" skill_name="" target=""
  local base_dir=""

  _skills_parse_access_arguments "skr" "$@" || return 1
  global="${reply[1]}"
  provider="${reply[2]}"
  skill_name="${reply[3]}"

  _skills_base_dir "$global" "$provider" || return 1
  base_dir="$REPLY"

  if [[ -z "$skill_name" ]]; then
    bat "$base_dir"/*(N)
    return
  fi

  _skills_resolve_target "$skill_name" "$base_dir" "skr" || return 1
  target="$REPLY"

  if [[ "$_skills_target_mode" == "file" ]]; then
    bat "$target"
  else
    bat "$target"/**/*(.N)
  fi
}

function ske() {
  # Edit a skill. Usage: ske [-g] [-p pi|claude|codex|gemini] [skill-name]
  emulate -L zsh
  local global="false" provider="" skill_name=""
  local base_dir=""

  _skills_parse_access_arguments "ske" "$@" || return 1
  global="${reply[1]}"
  provider="${reply[2]}"
  skill_name="${reply[3]}"

  _skills_base_dir "$global" "$provider" || return 1
  base_dir="$REPLY"

  if [[ -z "$skill_name" ]]; then
    ${EDITOR:-vim} "$base_dir"
    return
  fi

  _skills_resolve_target "$skill_name" "$base_dir" "ske" || return 1
  ${EDITOR:-vim} "$REPLY"
}

function skcd() {
  # Navigate to a skill directory. Usage: skcd [-g] [-p pi|claude|codex|gemini] [skill-name]
  emulate -L zsh
  local global="false" provider="" skill_name=""
  local base_dir=""

  _skills_parse_access_arguments "skcd" "$@" || return 1
  global="${reply[1]}"
  provider="${reply[2]}"
  skill_name="${reply[3]}"

  _skills_base_dir "$global" "$provider" || return 1
  base_dir="$REPLY"

  if [[ -z "$skill_name" ]]; then
    cd "$base_dir"
    return
  fi

  _skills_resolve_target "$skill_name" "$base_dir" "skcd" || return 1
  if [[ "$_skills_target_mode" == "file" ]]; then
    cd "${REPLY:h}"
  else
    cd "$REPLY"
  fi
}

function skt() {
  # Tree a skill directory. Usage: skt [-g] [-p pi|claude|codex|gemini] [skill-name]
  emulate -L zsh
  local global="false" provider="" skill_name=""
  local base_dir=""

  _skills_parse_access_arguments "skt" "$@" || return 1
  global="${reply[1]}"
  provider="${reply[2]}"
  skill_name="${reply[3]}"

  _skills_base_dir "$global" "$provider" || return 1
  base_dir="$REPLY"

  if [[ -z "$skill_name" ]]; then
    tree "$base_dir"
    return
  fi

  _skills_resolve_target "$skill_name" "$base_dir" "skt" || return 1
  if [[ "$_skills_target_mode" == "file" ]]; then
    tree "${REPLY:h}"
  else
    tree "$REPLY"
  fi
}

function skl() {
  # List all existing skill directories. Usage: skl [-g] [-p pi|claude|codex|gemini]
  # Lists local (project) skills if any exist; otherwise falls back to global.
  emulate -L zsh
  local global="false" provider="" skill_name=""

  _skills_parse_access_arguments "skl" "$@" || return 1
  global="${reply[1]}"
  provider="${reply[2]}"
  skill_name="${reply[3]}"

  if [[ -n "$skill_name" ]]; then
    echo "skl: unexpected argument '$skill_name' (skl lists all skills, not a specific one)" >&2
    return 1
  fi

  local -aU base_dirs
  local -a providers_to_check
  local p=""

  if [[ -n "$provider" ]]; then
    providers_to_check=("$provider")
  else
    providers_to_check=("" pi claude codex gemini)
  fi

  for p in "${providers_to_check[@]}"; do
    _skills_base_dir "$global" "$p" 2>/dev/null && base_dirs+=("$REPLY")
  done

  # When not explicitly global: if no local base dirs found, try global as fallback.
  if [[ "$global" != "true" ]] && (( ${#base_dirs} == 0 )); then
    for p in "${providers_to_check[@]}"; do
      _skills_base_dir "true" "$p" 2>/dev/null && base_dirs+=("$REPLY")
    done
  fi

  if (( ${#base_dirs} == 0 )); then
    echo "skl: no skill directories found" >&2
    return 1
  fi

  local base_dir="" scope="" display_base="" skill_name_entry=""
  for base_dir in "${base_dirs[@]}"; do
    if [[ "$base_dir" == "$HOME"/* ]]; then
      scope="global"
    else
      scope="local"
    fi
    _skills_describe_base_dir_source "$base_dir" "$scope"
    display_base="$REPLY"

    _skills_collect_resolvable_skill_names "$base_dir" || continue
    for skill_name_entry in "${reply[@]}"; do
      echo "$display_base/$skill_name_entry"
    done
  done
}
