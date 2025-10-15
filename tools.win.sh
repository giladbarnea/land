# ------------[ AutoHotKey ]------------
[[ -n "$PROGFILES" && -f "$PROGFILES/AutoHotkey/AutoHotkey.exe" ]] && {
  function ahk() {
    if [[ -z "$1" ]]; then
      "$PROGFILES/AutoHotkey/AutoHotkey.exe"
      return $?
    fi
    if [[ -f "$1" ]]; then
      "$PROGFILES/AutoHotkey/AutoHotkey.exe" "$@"
      return $?
    fi
    echo "$@" >/tmp/ahk.ahk && "$PROGFILES/AutoHotkey/AutoHotkey.exe" /tmp/ahk.ahk
    return $?
  }

  __ahk_comp() { completion.generate '<FILE OR LITERAL>' -e 'ahk "WinHide ahk_exe VirtualBoxVM.exe"'; }
  complete -o default -F __ahk_comp ahk
}