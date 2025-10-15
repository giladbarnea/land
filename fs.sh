#!/usr/bin/env zsh
# CRUD for files.

# # renametopathlike <STRING / STDIN> [DESTINATION_DIR] [-f,--file] [-l,--lower] [-y,--yes] [-d,--with-date]
# Wrapper around `mv <source_path> "$(topathlike <source_path>)`.
# Confirms before running unless `-y` is passed.
# DESTINATION_DIR is the directory to move the renamed file to. Defaults to the source directory (e.g. unchanged).
# ## Examples
# ```sh
# renametopathlike '/path/of/foo bar.txt'    # -> /path/of/foo-bar.txt
# renametopathlike 'Foo Bar.txt' ~ -l        # -> ~/foo-bar.txt
# ```
function renametopathlike(){
  local source_path
  local destination_dir
  local pathlike
  local -a topathlike_opts
  local should_confirm=true
  local with_date=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -y|--yes) should_confirm=false ;;
      -d|--with-date) with_date=true ;;
      -*) topathlike_opts+=("$1") ;;
      *)
        [[ -n "$source_path" && -n "$destination_dir" ]] && { 
          log.error "Too many positional arguments: $(typeset source_path destination_dir), $1"
          docstring -p "$0"
          return 1 
        } 
        [[ -n "$source_path" ]] && destination_dir="${1:a}" ;
        [[ -z "$source_path" ]] && source_path="$1" ;
        ;;
    esac
    shift
  done
  [[ -z "$source_path" ]] && is_piped && source_path="$(<&0)"
  [[ -z "$source_path" ]] && {
    log.error "No source path provided"
    docstring "$0" -p
    return 1
  }
  pathlike="$(topathlike "$source_path" "${topathlike_opts[@]}")"
  [[ "$source_path" == "${pathlike}" ]] && {
    log.success "${source_path} is already pathlike."
    return 0
  }
  [[ "$destination_dir" ]] || destination_dir="${pathlike:a:h}"
  [[ -d "$destination_dir" ]] || {
    log.error "Destination directory does not exist or is not a directory: $destination_dir"
    return 1
  }
  local pathlike_file_name
  if [[ $with_date = true ]]; then
    pathlike_file_name="$(date +"%Y-%m-%d")-${pathlike:a:t}"
  else
    pathlike_file_name="${pathlike:a:t}"
  fi
  if [[ $should_confirm = true ]]; then
    confirm "Rename '$source_path' to '${destination_dir}/${pathlike_file_name}'?" || return 1
  fi
  mv -i "$source_path" "${destination_dir}/${pathlike_file_name}"
}

alias rntpl=renametopathlike

# # rm [OPTIONS] TARGET
# If `rm` fails on a directory, prompts to retry with `-rf`.
function rm(){
  local -i exitcode
  command rm "$@"
  exitcode=$?
  local -i failed_because_directory_code=1
  [[ $exitcode != $failed_because_directory_code ]] && return $exitcode
  [[ "${#@}" != 1 ]] && return $exitcode  # Don't want to handle complex cases
  local file="$1"
  [[ ! -d "$file" ]] && return $exitcode
  confirm "'$file' is a directory. rm -rf '$file'?" || $exitcode
  command rm -rf "$file"
}


# # mountdevice [DEVICE] [LOCAL_MOUNT_POINT]
# `DEVICE` e.g '/dev/nvme0n1p1', `LOCAL_MOUNT_POINT` e.g '/mnt/win'
function mountdevice(){
  local device_id mount_point
  local devices="$(sudo fdisk -l -o device,size,type | grep -E '^/dev' --color=never)"
  local device_ids="$(cut -d ' ' -f 1 <<< "$devices")"
  if [[ "$1" ]]; then
    device_id="$1"
    shift
    if ! [[ ${device_ids[(r)$device_id]} ]]; then
      log.warn "Bad device: $device_id"
      unset device_id
    fi
  fi
  if [ ! "$device_id" ]; then
    sudo fdisk -l -o device,size,type | grep -E '^/dev' --color=never
    device_id="$(input "Choose device to mount:" --choices="( $device_ids )")"
  fi

  local findmnt_device
  if findmnt_device="$(sudo findmnt -o target --noheading $device_id)"; then
    log.success "$device_id already mounted at $findmnt_device"
    return 0
  fi

  if [ "$1" ]; then
    mount_point="$1"
    shift
  else
    local prompt="Where to mount $device_id? For example: /mnt/best_dir"
    local empty_mnt_dirs
    if empty_mnt_dirs=("$(find /mnt -maxdepth 1 -empty -exec echo {} \;)"); then
      prompt+=". FYI, the following dirs are empty: ${empty_mnt_dirs[*]//$'\n'/, }"
    fi
    mount_point="$(input "$prompt")"
  fi

  local findmnt_mount_point
  if findmnt_mount_point="$(sudo findmnt -o source --noheading $mount_point)"; then
    log.fatal "$mount_point is not available. Already mounting $findmnt_mount_point"
    return 1
  fi

  vex sudo mkdir -p "$mount_point"
  local exitcode
  vex sudo mount "$device_id" "$mount_point"
  exitcode=$?
  if [ $exitcode = 0 ]; then
    log.success "Mounted $device_id onto $mount_point successfully"
    return 0
  elif [ $exitcode = 16 ]; then
    if ! confirm "Looks like $device_id: $mount_point is readonly. Remount with read-write permissions?"; then
      return 3
    fi
    vex sudo mount -o remount,rw "$device_id"
    return $?
  else
    log.fatal "Failed mounting $device_id onto $mount_point (status $exitcode)"
    return $exitcode
  fi
}


# # teemp [tee options...] [-c,--copy] [-v,--verbose]
# `tee` to a temp file (`mktemp`).
# -c,--copy: Copy path of temp file to clipboard.
# -v,--verbose: Log the path of temp file.
function teemp(){
  local temp_file
  temp_file="$(mktemp)"
  local -a tee_args=("$@")
  (( ${+tee_args[(I)-c|--copy]} )) && {
    tee_args[${tee_args[(I)-c|--copy]}]=()
    copy "$temp_file" -r
  }
  (( ${+tee_args[(I)-v|--verbose]} )) && {
    tee_args[${tee_args[(I)-v|--verbose]}]=()
    log.info "tee'ing to $temp_file"
  }
  tee "${tee_args[@]}" "$temp_file"
}


# # pastemp [tee options...]
# Creates a temp file, paste clipboard into it, and print the path.
function pastemp(){
  local temp_file
  temp_file="$(mktemp)"
  paste > "$temp_file"
  printf "%s\n" "$temp_file"
}
