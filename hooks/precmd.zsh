# === History shrink backup hook ===
# Creates a backup when ~/.zsh_history shrinks by >= HIST_BACKUP_MIN_SHRINK bytes
# Backup file path: ~/.zsh_history.shrinkbackup.$EPOCHSECONDS
# Uses a previous snapshot to capture the pre-shrink content where possible.
typeset -gi HIST_BACKUP_MIN_SHRINK=256
typeset -gi _g_hist_prev_size=0
typeset -g  _g_hist_prev_snapshot_path

hbackup() {
  local f; f=$(.hist_effective_file) || { print -u2 "no on-disk history"; return 1; }
  local backup="${f}.${EPOCHSECONDS}"
  local -i cp_exit_code
  command cp -p -- "$f" "$backup" 2>/dev/null || command cp -p "$f" "$backup"
  cp_exit_code=$?
  if (( cp_exit_code == 0 )); then
    print -P "%F{green}[history]%f manual backup -> $backup"
  else
    print -P "%F{red}[history]%f manual backup -> $backup failed with exit code $cp_exit_code"
  fi
  return $cp_exit_code
}

.hist_effective_file() {
  # Echo the active history file path, or fail with non-zero if none.
  # No on-disk history when HISTFILE is unset, empty, or /dev/null.
  if (( ${+HISTFILE} == 0 )); then
    return 1
  fi
  local f="$HISTFILE"
  if [[ -z "$f" || "$f" == /dev/null ]]; then
    return 1
  fi
  print -r -- "$f"
}

.hist_file_size() {
  local f
  f=$(.hist_effective_file) || { echo 0; return 1; }
  [[ -f $f ]] || { echo 0; return 1; }
  local s
  # Byte size only (no filename) via input redirection
  s=$(wc -c < "$f" 2>/dev/null)
  [[ -n $s ]] || { echo 0; return 1; }
  echo $s
}

# Copies the history file to a .prevsnapshot file
.hist_backup_update_snapshot() {
  local f
  f=$(.hist_effective_file) || return 1
  _g_hist_prev_snapshot_path="${f}.prevsnapshot"
  if [[ -f $f ]]; then
    command cp -p -- "$f" "$_g_hist_prev_snapshot_path" 2>/dev/null || command cp -p -- "$f" "$_g_hist_prev_snapshot_path"
  fi
}

# .hist_notify_shrink <previous_bytes> <current_bytes> <backup_path>
# Show a blocking dialog (macOS) when a shrink is detected. Keep message simple.
.hist_notify_shrink() {
  local prev_bytes="$1" cur_bytes="$2" backup_path="$3"
  if (( prev_bytes == 0 )); then
    return
  fi
  local diff percent msg prev_fmt cur_fmt diff_fmt
  diff=$(( prev_bytes - cur_bytes ))
  
  # Only notify if shrink is significant (≥10% of original size)
  percent=$(( 100 * diff / prev_bytes ))
  if (( percent < 10 )); then
    return  # Shrink not significant enough
  fi
  
  # Add thousands separators using printf
  prev_fmt=$(printf "%'d" "$prev_bytes")
  cur_fmt=$(printf "%'d" "$cur_bytes")
  diff_fmt=$(printf "%'d" "$diff")
  
  msg="Zsh history trimmed: prev=${prev_fmt}B current=${cur_fmt}B shrink=${diff_fmt}B (${percent}%) backup=${backup_path}"
  if command -v osascript >/dev/null 2>&1; then
    MSG="$msg" osascript -e 'display dialog (system attribute "MSG") buttons {"OK"} default button "OK" with title "Zsh History Trimmed" with icon caution'
  else
    print -P "%F{yellow}[history]%f $msg"
  fi
}

# precmd timing:
# 1. You press Enter: zsh adds the line to in‑memory history and appends it to $HISTFILE immediately (SHARE_HISTORY also imports new lines from disk right then). If this append pushes the file past the SAVEHIST+20% threshold, zsh immediately trim-rewrites the file at this point.
# 2. preexec runs (just before executing the command).
# 3. Command runs and finishes.
# 4. precmd runs (just before the next prompt). By now any trim that happened since the last prompt is already on disk, so your hook sees the post‑trim size.
# 
# Key nuance:
# - With SHARE_HISTORY, the write happens at accept‑line (before the command runs), so the trim often happens then, not “after the command finishes.” Your hook doesn’t depend on the exact sub‑moment — it just observes that by precmd time the shrink has already occurred.
# - Only if you used INC_APPEND_HISTORY_TIME (you don’t) would the write happen after the command finishes, shifting the possible trim to that time window.
.hist_shrink_backup_precmd() {
  local f s prev
  f=$(.hist_effective_file) || { _g_hist_prev_size=0; return; }
  s=$(.hist_file_size) || { _g_hist_prev_size=0; return; }
  prev=${_g_hist_prev_size:-0}

  # First run: establish snapshot and baseline size, then return.
  if [[ -z ${_g_hist_prev_snapshot_path:-} || ! -e $_g_hist_prev_snapshot_path ]]; then
    .hist_backup_update_snapshot
    _g_hist_prev_size=$s
    return
  fi

  # If file shrank significantly since last check, back up the pre-shrink snapshot
  if (( prev > 0 && s + HIST_BACKUP_MIN_SHRINK < prev )); then
    local backup
    backup="${f}.shrinkbackup.${EPOCHSECONDS}"
    # Prefer backing up the previous snapshot (pre-shrink); fall back to current
    if [[ -e $_g_hist_prev_snapshot_path ]]; then
      command cp -p -- "$_g_hist_prev_snapshot_path" "$backup" 2>/dev/null || command cp -p -- "$_g_hist_prev_snapshot_path" "$backup"
    else
      command cp -p -- "$f" "$backup" 2>/dev/null || command cp -p -- "$f" "$backup"
    fi
    .hist_notify_shrink "$prev" "$s" "$backup"
  fi

  # Refresh snapshot and size for next comparison (only if size changed).
  # We do not return after the backup block because we want the snapshot
  # to track the current on-disk state for the next prompt.
  if (( s != prev )); then
    .hist_backup_update_snapshot
    _g_hist_prev_size=$s
  fi
}

autoload -Uz add-zsh-hook 2>/dev/null || true
add-zsh-hook precmd .hist_shrink_backup_precmd 2>/dev/null || .hist_shrink_backup_precmd
