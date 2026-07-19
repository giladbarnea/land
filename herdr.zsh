# Source from zsh. Requires herdr and jq.

# # _herdr_error MESSAGE
# Prints a helper error to stderr.
function _herdr_error() {
  print -u2 -r -- "$*"
  return 1
}

# # _herdr_object_type pane|tab|workspace
# Normalizes ws to workspace.
function _herdr_object_type() {
  case "$1" in
    pane) print -r -- pane ;;
    tab) print -r -- tab ;;
    workspace|ws) print -r -- workspace ;;
    *) _herdr_error "unknown Herdr object type: $1" ;;
  esac
}

# # _herdr_snapshot
# Prints the current Herdr session snapshot.
function _herdr_snapshot() {
  local response
  response="$(herdr api snapshot)" || return
  print -r -- "$response" | jq -ec '.result.snapshot'
}

# # herdrget pane|tab|workspace [ID|LABEL|current]
# Resolves one Herdr object to its canonical ID; ambiguous selectors fail.
function herdrget() {
  emulate -L zsh
  setopt pipefail

  (( $# >= 1 && $# <= 2 )) || {
    _herdr_error 'usage: herdrget pane|tab|workspace [ID|LABEL|current]'
    return
  }

  local object_type selector collection_name id_field focused_id_field snapshot matches match_count
  object_type="$(_herdr_object_type "$1")" || return
  selector="${2:-current}"

  case "$object_type" in
    pane)
      collection_name=panes
      id_field=pane_id
      focused_id_field=focused_pane_id
      ;;
    tab)
      collection_name=tabs
      id_field=tab_id
      focused_id_field=focused_tab_id
      ;;
    workspace)
      collection_name=workspaces
      id_field=workspace_id
      focused_id_field=focused_workspace_id
      ;;
  esac

  snapshot="$(_herdr_snapshot)" || return

  if [[ -z "$selector" || "$selector" == . || "$selector" == current ]]; then
    print -r -- "$snapshot" | jq -er --arg field "$focused_id_field" '.[$field]'
    return
  fi

  matches="$(
    print -r -- "$snapshot" | jq -ce \
      --arg collection "$collection_name" \
      --arg id_field "$id_field" \
      --arg selector "$selector" '
        .[$collection] as $objects
        | ($selector | ascii_downcase) as $needle
        | [$objects[] | select((.[$id_field] | ascii_downcase) == $needle)] as $exact_ids
        | [$objects[]
            | (.[$id_field] | split(":")[-1] | ascii_downcase) as $short_id
            | select($short_id == $needle or $short_id[1:] == $needle)
          ] as $exact_short_ids
        | [$objects[] | select(((.label // "") | ascii_downcase) == $needle)] as $exact_labels
        | [$objects[] | select(
            (.[$id_field] | ascii_downcase | contains($needle))
            or ((.label // "") | ascii_downcase | contains($needle))
          )] as $substring_matches
        | if ($exact_ids | length) > 0 then $exact_ids
          elif ($exact_short_ids | length) > 0 then $exact_short_ids
          elif ($exact_labels | length) > 0 then $exact_labels
          else $substring_matches
          end
      '
  )" || return

  match_count="$(print -r -- "$matches" | jq -r 'length')" || return

  case "$match_count" in
    0)
      _herdr_error "no $object_type matches: $selector"
      ;;
    1)
      print -r -- "$matches" | jq -r --arg field "$id_field" '.[0][$field]'
      ;;
    *)
      print -u2 -r -- "ambiguous $object_type selector: $selector"
      print -r -- "$matches" | jq -r --arg field "$id_field" \
        '.[] | "  \(.[$field])\t\(.label // "<unnamed>")"' >&2
      return 2
      ;;
  esac
}

# # herdrls panes [TAB] | tabs [WORKSPACE] | tree [WORKSPACE]
# Lists Herdr objects within the selected parent, defaulting to the focused one.
function herdrls() {
  emulate -L zsh
  setopt pipefail

  (( $# >= 1 && $# <= 2 )) || {
    _herdr_error 'usage: herdrls panes [TAB] | tabs [WORKSPACE] | tree [WORKSPACE]'
    return
  }

  local list_type selector parent_id snapshot
  list_type="$1"
  selector="${2:-current}"

  case "$list_type" in
    panes)
      parent_id="$(herdrget tab "$selector")" || return
      snapshot="$(_herdr_snapshot)" || return
      print -r -- "$snapshot" | jq -r --arg tab_id "$parent_id" '
        .panes[]
        | select(.tab_id == $tab_id)
        | "\(.pane_id)\t\(.label // "<unnamed>")"
      '
      ;;
    tabs)
      parent_id="$(herdrget workspace "$selector")" || return
      snapshot="$(_herdr_snapshot)" || return
      print -r -- "$snapshot" | jq -r --arg workspace_id "$parent_id" '
        .tabs
        | map(select(.workspace_id == $workspace_id))
        | sort_by(.number)[]
        | "\(.tab_id)\t\(.label // "<unnamed>")"
      '
      ;;
    tree)
      parent_id="$(herdrget workspace "$selector")" || return
      snapshot="$(_herdr_snapshot)" || return
      print -r -- "$snapshot" | jq -r --arg workspace_id "$parent_id" '
        . as $snapshot
        | ($snapshot.workspaces[] | select(.workspace_id == $workspace_id)) as $workspace
        | ($snapshot.tabs | map(select(.workspace_id == $workspace_id)) | sort_by(.number)) as $tabs
        | [
            "\($workspace.workspace_id)\t\($workspace.label // "<unnamed>")",
            (
              $tabs[] as $tab
              | "  \($tab.tab_id)\t\($tab.label // "<unnamed>")",
                (
                  $snapshot.panes[]
                  | select(.tab_id == $tab.tab_id)
                  | "    \(.pane_id)\t\(.label // "<unnamed>")"
                )
            )
          ][]
      '
      ;;
    *)
      _herdr_error "unknown list type: $list_type"
      ;;
  esac
}

# # herdrrename pane|tab|workspace SELECTOR NEW_NAME
# Renames the selected Herdr object and prints its canonical ID.
function herdrrename() {
  emulate -L zsh

  (( $# == 3 )) || {
    _herdr_error 'usage: herdrrename pane|tab|workspace SELECTOR NEW_NAME'
    return
  }

  local object_type object_id
  object_type="$(_herdr_object_type "$1")" || return
  object_id="$(herdrget "$object_type" "$2")" || return
  herdr "$object_type" rename "$object_id" "$3" >/dev/null || return
  print -r -- "$object_id"
}

# # _herdr_move_tab_to_workspace TAB_ID WORKSPACE_ID
# Moves a tab by reconstructing its pane layout; failures report the partial destination tab.
function _herdr_move_tab_to_workspace() {
  local source_tab_id="$1" destination_workspace_id="$2"
  local snapshot replay_plan source_tab_label
  local original_root_pane_id original_focused_pane_id original_global_tab_id source_was_zoomed
  local first_move_response destination_tab_id destination_root_pane_id move_focus_option

  snapshot="$(_herdr_snapshot)" || return
  replay_plan="$(
    print -r -- "$snapshot" | jq -ce --arg tab_id "$source_tab_id" '
      def contains_point($rect; $x; $y):
        ($rect.x <= $x)
        and ($x < ($rect.x + $rect.width))
        and ($rect.y <= $y)
        and ($y < ($rect.y + $rect.height));

      def pane_at($panes; $x; $y):
        [$panes[] | select(contains_point(.rect; $x; $y))]
        | if length == 1 then .[0].pane_id
          else error("layout point maps to \(length) panes")
          end;

      . as $snapshot
      | ($snapshot.layouts[] | select(.tab_id == $tab_id)) as $layout
      | {
          source_tab_label: ($snapshot.tabs[] | select(.tab_id == $tab_id) | .label // ""),
          original_global_tab_id: ($snapshot.focused_tab_id // ""),
          original_focused_pane_id: $layout.focused_pane_id,
          source_was_zoomed: $layout.zoomed,
          root_pane_id: pane_at($layout.panes; $layout.area.x; $layout.area.y),
          steps: [
            $layout.splits
            | sort_by(-(.rect.width * .rect.height))[]
            | . as $split
            | (if $split.direction == "right"
                then $split.rect.x + (($split.rect.width * $split.ratio) | round)
                else $split.rect.x
              end) as $second_x
            | (if $split.direction == "down"
                then $split.rect.y + (($split.rect.height * $split.ratio) | round)
                else $split.rect.y
              end) as $second_y
            | {
                source_pane_id: pane_at($layout.panes; $second_x; $second_y),
                target_pane_id: pane_at($layout.panes; $split.rect.x; $split.rect.y),
                direction: $split.direction,
                ratio: $split.ratio
              }
          ]
        }
    '
  )" || return

  source_tab_label="$(print -r -- "$replay_plan" | jq -r '.source_tab_label')" || return
  original_root_pane_id="$(print -r -- "$replay_plan" | jq -r '.root_pane_id')" || return
  original_focused_pane_id="$(print -r -- "$replay_plan" | jq -r '.original_focused_pane_id')" || return
  source_was_zoomed="$(print -r -- "$replay_plan" | jq -r '.source_was_zoomed')" || return
  original_global_tab_id="$(print -r -- "$replay_plan" | jq -r '.original_global_tab_id')" || return

  [[ "$source_was_zoomed" != true ]] || \
    herdr pane zoom "$original_focused_pane_id" --off >/dev/null || return

  move_focus_option=--no-focus
  [[ "$original_root_pane_id" == "$original_focused_pane_id" ]] && move_focus_option=--focus

  local -a first_move_command=(
    herdr pane move "$original_root_pane_id"
    --new-tab --workspace "$destination_workspace_id"
    --no-focus
  )
  first_move_command[-1]="$move_focus_option"
  [[ -n "$source_tab_label" ]] && first_move_command+=(--label "$source_tab_label")

  first_move_response="$("${first_move_command[@]}")" || return
  destination_tab_id="$(
    print -r -- "$first_move_response" | jq -er '
      .result.move_result
      | if .changed then .created_tab.tab_id else error("pane move: \(.reason)") end
    '
  )" || return
  destination_root_pane_id="$(
    print -r -- "$first_move_response" | jq -er '.result.move_result.pane.pane_id'
  )" || return

  local -A moved_pane_ids_by_original_id
  moved_pane_ids_by_original_id[$original_root_pane_id]="$destination_root_pane_id"

  local replay_steps_text
  local -a replay_steps
  replay_steps_text="$(
    print -r -- "$replay_plan" | jq -r \
      '.steps[] | [.source_pane_id, .target_pane_id, .direction, (.ratio | tostring)] | @tsv'
  )" || return
  replay_steps=()
  [[ -n "$replay_steps_text" ]] && replay_steps=("${(@f)replay_steps_text}")

  local replay_step original_source_pane_id original_target_pane_id split_direction split_ratio
  local destination_target_pane_id move_response destination_source_pane_id
  for replay_step in "${replay_steps[@]}"; do
    IFS=$'\t' read -r \
      original_source_pane_id original_target_pane_id split_direction split_ratio \
      <<< "$replay_step"

    destination_target_pane_id="${moved_pane_ids_by_original_id[$original_target_pane_id]}"
    [[ -n "$destination_target_pane_id" ]] || {
      _herdr_error "tab move is partial; missing moved target for $original_target_pane_id; destination tab: $destination_tab_id"
      return
    }

    move_focus_option=--no-focus
    [[ "$original_source_pane_id" == "$original_focused_pane_id" ]] && move_focus_option=--focus
    move_response="$(
      herdr pane move "$original_source_pane_id" \
        --tab "$destination_tab_id" \
        --split "$split_direction" \
        --target-pane "$destination_target_pane_id" \
        --ratio "$split_ratio" \
        "$move_focus_option"
    )" || {
      _herdr_error "tab move is partial; destination tab: $destination_tab_id"
      return
    }

    destination_source_pane_id="$(
      print -r -- "$move_response" | jq -er '
        .result.move_result
        | if .changed then .pane.pane_id else error("pane move: \(.reason)") end
      '
    )" || {
      _herdr_error "tab move completed a pane but could not read its new ID; destination tab: $destination_tab_id"
      return
    }
    moved_pane_ids_by_original_id[$original_source_pane_id]="$destination_source_pane_id"
  done

  local destination_focused_pane_id
  destination_focused_pane_id="${moved_pane_ids_by_original_id[$original_focused_pane_id]}"
  [[ "$source_was_zoomed" != true ]] || \
    herdr pane zoom "$destination_focused_pane_id" --on >/dev/null || return

  [[ -z "$original_global_tab_id" || "$original_global_tab_id" == "$source_tab_id" ]] || \
    herdr tab focus "$original_global_tab_id" >/dev/null || return

  print -r -- "$destination_tab_id"
}

# # herdrmove pane SOURCE tab|workspace DESTINATION | tab SOURCE workspace DESTINATION
# Moves a pane, or moves a tab while preserving its pane layout.
function herdrmove() {
  emulate -L zsh
  setopt pipefail

  (( $# == 4 )) || {
    _herdr_error 'usage: herdrmove pane SOURCE tab|workspace DESTINATION | tab SOURCE workspace DESTINATION'
    return
  }

  local source_type source_id destination_type destination_id response snapshot new_tab_label
  source_type="$(_herdr_object_type "$1")" || return
  source_id="$(herdrget "$source_type" "$2")" || return
  destination_type="$(_herdr_object_type "$3")" || return
  destination_id="$(herdrget "$destination_type" "$4")" || return

  if [[ "$source_type" == pane && "$destination_type" == tab ]]; then
    response="$(
      herdr pane move "$source_id" --tab "$destination_id" --split right --no-focus
    )" || return
    print -r -- "$response" | jq -er '
      .result.move_result
      | if .changed then .pane.pane_id else error("pane move: \(.reason)") end
    '
    return
  fi

  if [[ "$source_type" == pane && "$destination_type" == workspace ]]; then
    snapshot="$(_herdr_snapshot)" || return
    new_tab_label="$(
      print -r -- "$snapshot" | jq -r --arg pane_id "$source_id" '
        (.panes[] | select(.pane_id == $pane_id)) as $pane
        | $pane.label
          // (.tabs[] | select(.tab_id == $pane.tab_id) | .label)
          // ""
      '
    )" || return

    local -a move_command=(
      herdr pane move "$source_id"
      --new-tab --workspace "$destination_id"
      --no-focus
    )
    [[ -n "$new_tab_label" ]] && move_command+=(--label "$new_tab_label")
    response="$("${move_command[@]}")" || return
    print -r -- "$response" | jq -er '
      .result.move_result
      | if .changed then .pane.pane_id else error("pane move: \(.reason)") end
    '
    return
  fi

  if [[ "$source_type" == tab && "$destination_type" == workspace ]]; then
    _herdr_move_tab_to_workspace "$source_id" "$destination_id"
    return
  fi

  _herdr_error "cannot move $source_type to $destination_type"
}

# # herdrnew workspace NAME [CWD] | tab NAME [WORKSPACE] [CWD] | pane right|down [ANCHOR] [CWD]
# Creates a Herdr workspace, tab, or split pane and prints its canonical ID.
function herdrnew() {
  emulate -L zsh
  setopt pipefail

  (( $# >= 2 && $# <= 4 )) || {
    _herdr_error 'usage: herdrnew workspace NAME [CWD] | tab NAME [WORKSPACE] [CWD] | pane right|down [ANCHOR] [CWD]'
    return
  }

  local object_type response cwd label workspace_id anchor_pane_id direction
  local -a command
  object_type="$(_herdr_object_type "$1")" || return

  case "$object_type" in
    workspace)
      (( $# <= 3 )) || {
        _herdr_error 'usage: herdrnew workspace NAME [CWD]'
        return
      }
      label="$2"
      cwd="${3:-}"
      command=(herdr workspace create --label "$label" --no-focus)
      [[ -n "$cwd" ]] && command+=(--cwd "$cwd")
      response="$("${command[@]}")" || return
      print -r -- "$response" | jq -er '.result.workspace.workspace_id'
      ;;
    tab)
      label="$2"
      workspace_id="$(herdrget workspace "${3:-current}")" || return
      cwd="${4:-}"
      command=(herdr tab create --workspace "$workspace_id" --label "$label" --no-focus)
      [[ -n "$cwd" ]] && command+=(--cwd "$cwd")
      response="$("${command[@]}")" || return
      print -r -- "$response" | jq -er '.result.tab.tab_id'
      ;;
    pane)
      direction="$2"
      [[ "$direction" == right || "$direction" == down ]] || {
        _herdr_error 'new pane direction must be right or down'
        return
      }
      anchor_pane_id="$(herdrget pane "${3:-current}")" || return
      cwd="${4:-}"
      command=(herdr pane split "$anchor_pane_id" --direction "$direction" --no-focus)
      [[ -n "$cwd" ]] && command+=(--cwd "$cwd")
      response="$("${command[@]}")" || return
      print -r -- "$response" | jq -er '.result.pane.pane_id'
      ;;
  esac
}

# # herdrclose pane|tab|workspace [SELECTOR]
# Closes the selected Herdr object and prints its canonical ID.
function herdrclose() {
  emulate -L zsh

  (( $# >= 1 && $# <= 2 )) || {
    _herdr_error 'usage: herdrclose pane|tab|workspace [SELECTOR]'
    return
  }

  local object_type object_id
  object_type="$(_herdr_object_type "$1")" || return
  object_id="$(herdrget "$object_type" "${2:-current}")" || return
  herdr "$object_type" close "$object_id" >/dev/null || return
  print -r -- "$object_id"
}
