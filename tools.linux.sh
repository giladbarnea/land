
# ------------[ xdotool ]------------

isdefined xdotool && {
# # xdtmap <xdotool-command...>
# ## Example
#   xdotool search pycharm | xdtmap getwindowname getwindowpid
function xdtmap() {
  for fn in "$@"; do
    printf "${Ccyn}%b${C0} | " "$fn"
  done
  printf "${Ccyn}x${C0} | "
  echo
  while read -r x; do
    for fn in "$@"; do
      y="$(xdotool "$fn" "$x" 2>/dev/null)"
      if [[ "$y" == 'Content window' ]]; then continue 2; fi
      if [[ -z "$y" ]]; then y='--'; fi
      printf "%s ${Ccyn}|${C0} " "${y//$'\n'/}"
    done
    printf "%s ${Ccyn}|${C0} " "${x}"
    echo
  done
}

complete -o default -W 'getactivewindow getwindowfocus getwindowname getwindowpid getwindowgeometry getdisplaygeometry search selectwindow help version behave behave_screen_edge click getmouselocation key keydown keyup mousedown mousemove mousemove_relative mouseup set_window type windowactivate windowfocus windowkill windowclose windowmap windowminimize windowmove windowraise windowreparent windowsize windowunmap set_num_desktops get_num_desktops set_desktop get_desktop set_desktop_for_window get_desktop_for_window get_desktop_viewport set_desktop_viewport exec sleep' xdotool xdtmap

}

# ----------[ inotifywait ]----------

isdefined inotifywait && {
declare _inotify_base_excludei='notion-linux-x64|tracker|kitty|brave|copyq|Slack|Code|pulse|.*lock.*|.*~$|\.java|\.git|winmgmt|.*\.desktop|event-sound-cache|gitstatus|\.tmp|__pycache__|METADATA'

# # inotifylog [options]
# ## Options
# --excludei <REGEX>		Can be specified multiple times
# -e, --event <EVENT>		Can be specified multiple times
# Allowed events:
# ACCESS, MODIFY, ATTRIB, CLOSE_WRITE, CLOSE_NOWRITE, CLOSE, OPEN, MOVED_TO, MOVED_FROM, MOVE, MOVE_SELF, CREATE, DELETE, DELETE_SELF, UNMOUNT
function inotifylog(){
  local time dir file event bname ext cpdir cppath filepath
  local excludei="$_inotify_base_excludei"
  local events="MODIFY|CLOSE_WRITE|OPEN"
  local positional=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --excludei) excludei+="|${2}"; shift 2;;
      -e|--event) events+="|${2}"; shift 2;;
      *) positional+=("$1"); shift;;
    esac
  done
  set -- "${positional[@]}"
  sudo inotifywait \
       --recursive . \
       --monitor \
       --format "%T %w %f %e" \
       --timefmt %T \
       --excludei "(${excludei})" \
    | while read -r time dir file event; do
        filepath="${dir}${file}"
        if [[ ! "$event" =~ .*("${events}").* || ! -f "$filepath" ]]; then
          continue
        fi
        echo "[$time] $event | $filepath"
			done
}

function inotifytee(){
  mkdir -p "/tmp/${0}" || return 1
	local logfile="$(date +%s)_${USER}_${${PWD//\//.}:1}.log"
	log.title "logfile: ${logfile}"
  inotifylog "$@" | tee -a "/tmp/${0}/${logfile}"
}

compdef "compadd -x 'inotifylog prints, inotifytee prints and writes.'; _describe command \"('--excludei:Regex pattern for paths to exclude. Case-insensitive, can multiple.' '{-e,--event}:EVENT. Default MODIFY|CLOSE_WRITE|OPEN. Can multiple')\"" inotifylog inotifytee

function inotifycp(){
  runcmds "rm -rf /tmp/${0}" \
          "mkdir -p /tmp/${0}" || return 1
  local time dir file event bname ext cpdir cppath filepath
  local excludei="$_inotify_base_excludei"
  local positional=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --excludei) excludei+="|${2}"; shift 2;;
      *) positional+=("$1"); shift;;
    esac
  done
  set -- "${positional[@]}"
  local count=$((1))
  local write_version=true
  sudo inotifywait \
       --recursive . \
       --monitor \
       --format "%T %w %f %e" \
       --timefmt %T \
       --excludei "(${excludei})" \
    | while read -r time dir file event; do
        filepath="${dir}${file}"
        if [[ ! "$event" =~ .*(MODIFY|CLOSE_WRITE|OPEN).* || ! -f "$filepath" ]]; then
          continue
        fi
        count=$((1))
        write_version=true
        bname="$(basename "$file")" || continue
        ext=${file##*.}
        cpdir="/tmp/inotifycp/${dir#*/}"
        mkdir -p "$cpdir"
        cppath="${cpdir}${bname}.${count}.${ext}"
        while [[ -e "$cppath" ]]; do
          if diff -qwEbBZ "$cppath" "$filepath" &>/dev/null; then
            [ "$event" != OPEN ] && log.info "[$time] $filepath | $event | Current version already saved at $cppath" -x
            write_version=false
            break
          fi
          ((count++))
          cppath="${cpdir}${bname}.${count}.${ext}"
        done
        if $write_version; then
          log.title "[$time] $filepath | $event | -> $cppath" -x
          cp "$filepath" "$cppath"
        fi
	  done

}
}