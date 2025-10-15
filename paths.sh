#!/usr/bin/env zsh


# # cppwd
# Copies absolute $PWD to clipboard
function cppwd() {
  copy "$PWD"
}

# # cppath [ABSOLUTE OR RELATIVE FILE OR DIR PATH] [-r, --relative]
# Copies absolute path by default.
function cppath() {
  local specified_relative_true=false
  local path_to_copy
  local -a realpath_args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -r|--relative)
        realpath_args+=(--relative-to="$PWD")
        specified_relative_true=true ;;
      *)
        if [[ "$path_to_copy" ]]; then
          log.warn "Ignoring $1 because flag is unknown and already specified path: $path_to_copy"
        else
          if [[ -e "$1" ]]; then
            path_to_copy="$1"
          else
            log.fatal "'$1' does not exist. Returning 1"
            return 1
          fi
        fi ;;
    esac
    shift
  done
  [[ -z "$path_to_copy" ]] && {
    $specified_relative_true && {
      log.warn "Specified --relative but no path to copy. This doesn't make sense. Copying absolute PWD instead"
    }
    cppwd
    return $?
  }
  local normalized_path_to_copy="$(realpath "${realpath_args[@]}" "$path_to_copy")"
  log.debug "$(typeset -p realpath_args path_to_copy normalized_path_to_copy)"
  copy "$normalized_path_to_copy" --raw -v 1
}

# # resolve PATH [RELATIVE_TO=PWD]
function resolve(){
  setopt localoptions pipefail
  local target_path="$1"
  local original_target_path="$target_path"
  [[ -e "$target_path" ]] && {
    echo "$target_path"
    return 0
  }
  
  local removed_from_start
  local part
  local -a target_path_parts
  target_path_parts=("${(s./.)target_path}")
  
  for part in ${target_path_parts[@]}; do
      removed_from_start="${target_path#"$part"}"
      target_path="${removed_from_start#"/"}"
      [[ -z "$target_path" ]] && return 1
      [[ -e "$target_path" ]] && {
        echo "${target_path}"
        return 0
      }
  done
  local deeper_match
  deeper_match="$(fzf -f "${original_target_path}" --select-1 --exit-0 2>&1 | head -n 1)"
  if [[ $? -eq 0 && -n "$deeper_match" && -e "$deeper_match" ]]; then
    echo "$deeper_match"
    return 0
  fi
  return 1
}

# # tree [PATH=.]
# Prints a simple visual recursive file tree.
function tree() {
  setopt localoptions pipefail errreturn
  command eza \
    --classify \
    --icons \
    --tree \
    --git-ignore \
    --all \
    --ignore-glob "$(tr $'\n' \| < ~/.gitignore.global)" \
    "$@"
}

# -----[ $PATH ]-----

# # pathprepend <VALUE> [-q, --quiet]
# Prepends a value to PATH. If the value is already in PATH, it is moved to the beginning.
function pathprepend(){
  is_pycharm && return 1
  local value="$1"
  shift || { log.error "No value provided. Usage:\n$(docstring "$0")"; return 2; }
  [[ -z "$value" ]] && { log.error "No value provided. Usage:\n$(docstring "$0")"; return 2; }
  local quiet=false
  [[ "$1" == -q || "$1" == --quiet ]] && quiet=true && shift

  local old_path="$PATH"

  local -a path_array=(${(@)${(s.:.)PATH}})
  local -i value_index

  value_index="$(pathi "$value")" && {
    [[ "$value_index" = 1 ]] && {
      "$quiet" || log.success "PATH already starts with ${Cc}${value}"
      return 0
    }
    # Remove the value from its current position to be prepended later
    path_array[$value_index]=()
  }

  # Prepend the value
  path_array=("$value" ${path_array[@]})

  export PATH=${(j.:.)path_array[@]}
  rehash
}

# # pathappend <VALUE> [-q, --quiet]
# Appends a value to PATH. If the value is already in PATH, it is moved to the end.
function pathappend(){
  is_pycharm && return 1
  local value="$1"
  shift || { log.error "no value provided. Usage:\n$(docstring "$0")"; return 2; }
  [[ -z "$value" ]] && { log.error "No value provided. Usage:\n$(docstring "$0")"; return 2; }
  local quiet=false
  [[ "$1" == -q || "$1" == --quiet ]] && quiet=true && shift

  local old_path="$PATH"

  local -a path_array=(${(@)${(s.:.)PATH}})
  local -i value_index
  value_index="$(pathi "$value")" && {
    [[ "$value_index" = "${#path_array}" ]] && {
      log.success "PATH already ends with ${Cc}${value}"
      return 0
    }
    # Remove the value from its current position to be appended later
    path_array[$value_index]=()
  }

  # Append the value
  path_array+=("$value")

  export PATH=${(j.:.)path_array[@]}
  rehash

}

# # pathdel <VALUE/INDEX> [-q, --quiet]
# Deletes VALUE from PATH, if it exists.
function pathdel(){
  local value="$1"
  local quiet=false
  shift || { log.error "no value provided. Usage:\n$(docstring "$0")"; return 2; }
  [[ -z "$value" ]] && { log.error "No value provided. Usage:\n$(docstring "$0")"; return 2; }
  [[ "$1" == -q || "$1" == --quiet ]] && quiet=true && shift
  local old_path="$PATH"

  local -a path_array=(${(@)${(s.:.)PATH}})

  local -i value_index
  if ! value_index="$(pathi "$value")"; then
    $quiet || log.success "PATH does not contain ${Cc}${value}"
    return 0
  fi

  # Remove the value from its current position
  path_array[$value_index]=()

  export PATH=${(j.:.)path_array[@]}
  rehash
}

# # pathi <VALUE/INDEX>
# Prints the index of the first item in PATH that equals VALUE or VALUE/.
# If VALUE is not an absolute path, also checks PWD/VALUE and PWD/VALUE/.
# If VALUE is a number, and it is a valid index in PATH, prints the number.
# Returns 1 if VALUE is not in PATH.
function pathi(){
  local value="$1"
  shift || { log.error "No value provided. Usage:\n$(docstring -p "$0")"; return 2; }
  [[ -z "$value" ]] && { log.error "No value provided. Usage:\n$(docstring -p "$0")"; return 2; }
  local -a path_array=(${(@)${(s.:.)PATH}})

  isnum "$value" && {
    silence pathat "$value" || return 1
    printf "%s" "$value"
    return 0
  }

  local -i i
  local path_item
  for (( i = 1; i <= $#path_array; i++ )); do
    path_item="${path_array[$i]}"
    if {
      [[ "$path_item" == "${value}" || "$path_item" == "${value}/" ]] ||
      # If the value is not an absolute path, also check if it is a relative path to the current directory
      { [[ "${value}" != /* ]] && [[ "$path_item" == "${PWD}/${value}" || "$path_item" == "${PWD}/${value}/" ]] ; }
      }; then
      printf "%s" "$i"
      return 0
    fi
  done
  return 1
}

# # pathat <INDEX>
# Prints the item in PATH at the given index.
function pathat(){
  local index="$1"
  shift || { log.error "no index provided. Usage:\n$(docstring -p "$0")"; return 2; }
  [[ -z "$index" ]] && { log.error "No index provided. Usage:\n$(docstring -p "$0")"; return 2; }

  local -a path_array=(${(@)${(s.:.)PATH}})

  local path_item
  path_item="${path_array[$index]}"
  [[ -n "$path_item" ]] && {
    printf "%s" "$path_item"
    return 0
  }
  return 1
}

# # pathfind <REGEX>
# Returns the index of the first item in PATH that matches the REGEX.
function pathfind(){
  local regex="$1"
  shift || { log.error "No regex provided. Usage:\n$(docstring -p "$0")"; return 2; }
  [[ -z "$regex" ]] && { log.error "No regex provided. Usage:\n$(docstring -p "$0")"; return 2; }

  local -a path_array=(${(@)${(s.:.)PATH}})

  local i path_item
  for (( i = 1; i <= $#path_array; i++ )); do
    path_item="${path_array[$i]}"
    [[ "$path_item" =~ $regex ]] && {
      printf "%s" "$i"
      return 0
    }
  done
  return 1
}

# # pprint
# Prints PATH entries nicely.
function ppath(){
  print -l "${(s.:.)PATH}"
}
