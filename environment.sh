#!/usr/bin/env bash
# Sourced first, before aliases.sh
# *** Environment Vars ***

# export WHOIAM="${WHOIAM:-$(whoami)}"
export LESS="--quit-if-one-screen --RAW-CONTROL-CHARS --hilite-unread --quit-on-intr --jump-target=15 --use-color --ignore-case --save-marks"
export EDITOR=nvim
export RIPGREP_CONFIG_PATH="$HOME"/.ripgreprc
export HISTORY_SUBSTRING_SEARCH_ENSURE_UNIQUE=true
export BAT_STYLE='numbers,header,grid,snip,changes'
export KITTY_SHELL_INTEGRATION=enabled
# export ZPP_LOG_LEVEL=4  # debug and above

# WSL: $OSTYPE = linux-gnu; $OS = Linux? (probably); $PLATFORM = UNIX?
# git-bash: $OSTYPE = ?; $OS = ?; $PLATFORM=UNIX?
# Ubuntu (native): $OSTYPE = linux-gnu; $OS = Linux; $PLATFORM = UNIX
# Mac: $OSTYPE = darwin*; $OS is undefined

# In Linux, $OS is not empty (it's 'Linux'). So if it's empty, this is a Mac
export "${OS=macos}"

if [[ -z "$PLATFORM" ]]; then
  if [[ "$OS" =~ Windows(_NT) || "$PATH" = */c/windows* ]]; then
    export PLATFORM="WIN"
  else
    export PLATFORM="UNIX"
  fi
fi

if [[ "$PLATFORM" == UNIX ]]; then
  # ** Unix
  # export DOC="$HOME/Documents"
  # export DL="$HOME/Downloads"
  # export PIC="$HOME/Pictures"
  export PATH="$HOME/bin:$HOME/.local/bin${PATH+:${PATH}}"
  # export PATH="$PATH:$HOME/Library/Application Support/JetBrains/Toolbox/scripts"
  # export PATH="$PATH:/Applications/kitty.app/Contents/MacOS"

  if [[ "$OS" == macos ]]; then
    # * MacOS
    # Similar to `brew shellenv`.
    export HOMEBREW_PREFIX="/opt/homebrew"
    export HOMEBREW_CELLAR="/opt/homebrew/Cellar"
    export HOMEBREW_REPOSITORY="/opt/homebrew"
    export HOMEBREW_AUTO_UPDATE_SECS=604800 # 1 week
    fpath[1,0]="/opt/homebrew/share/zsh/site-functions"

    # export MANPATH="${HOMEBREW_PREFIX}/share/man${MANPATH+:${MANPATH}}"
    # export INFOPATH="${HOMEBREW_PREFIX}/share/info${INFOPATH+:${INFOPATH}}"

    # The `grep` part is crucial, otherwise macos grep is used (no -P, etc.)
    declare _homebrew_bins="${HOMEBREW_PREFIX}/bin:${HOMEBREW_PREFIX}/sbin:${HOMEBREW_PREFIX}/opt/grep/libexec/gnubin"
    export PATH="${_homebrew_bins}${PATH+:${PATH}}"

    unset _homebrew_bins

    # If no coreutils (happens on fresh mac), and if `realpath` is an alias (defined in init.sh),
    # and now after extending PATH, a real `realpath` is available, then use it instead of the alias
    # type realpath | command grep --color=never -q alias && type -a -f -p realpath >/dev/null 2>&1 && unalias realpath
  else
    # * Linux
    export VID="$HOME/Videos"
    export GTK_THEME=Adwaita:dark # for meld
    # export QT_AUTO_SCREEN_SCALE_FACTOR=0 # in .profile

    ## Mounted systems
    # WSL -> WIN Host: $WINHOME, $WINDEV, $WINSCRIPTS
    if [[ "$WSL_DISTRO_NAME" ]]; then
      if [[ -d /mnt/c/Users/$WHOIAM ]]; then
        export PROGFILES='/mnt/c/Program Files'
        export PROGFILES86='/mnt/c/Program Files (x86)'
        export WINHOME=/mnt/c/Users/$WHOIAM
        export WINDEV=/mnt/c/Users/$WHOIAM/dev
        export WINSCRIPTS=/mnt/c/Users/$WHOIAM/dev/bashscripts
        [[ -d "$WINHOME" ]] && export PATH="$PATH:$WINHOME/.local/bin"
      fi
    # export DISPLAY="$(cat /etc/resolv.conf | grep -Po '(?<=nameserver )[\d.]+'):0.0"
    elif [[ -d /mnt/win && -n $(command ls /mnt/win) ]]; then
      export PROGFILES='/mnt/win/Program Files'
      export PROGFILES86='/mnt/win/Program Files (x86)'
      export WINUSER="$(command ls -ltH '/mnt/win/Documents and Settings' | head -2 | tail -1 | rev | cut -d' ' -f 1 | rev)"
      export WINHOME='/mnt/win/Documents and Settings/'$WINUSER
      export WINDOC='/mnt/win/Documents and Settings/'$WINUSER/Documents
      export WINDL='/mnt/win/Documents and Settings/'$WINUSER/Downloads
      export WINDEV="$WINHOME/dev"
    fi
  fi
else # ** Windows
  export PROGFILES86="'/c/Program Files (x86)'"
  export PROGFILES="'/c/Program Files'"
  # export DESKTOP="'$HOME/<USER>/Desktop'"
fi

# $DEV
export DEV="$HOME/dev"

# $MAN, $MANPROJ
# export MANPROJ="$DEV/manuals"
# export MAN="$MANPROJ/manuals/manuals.py"

# $SCRIPTS
# typeset PATH
export SCRIPTS="$DEV/bashscripts"
export PATH="$PATH:$SCRIPTS"
export COMP="$SCRIPTS/completions"

# $WINMGMT
# export WINMGMT="$SCRIPTS/winmgmt"
# export PATH="$PATH:$WINMGMT"

# export PYTHONBREAKPOINT=pdbpp.set_trace

# export IPDB_CONTEXT_SIZE=30 # _init_pdb()
# export IPDB_CONFIG="$HOME/.ipython/profile_default/startup/ipython_utils.py"
# export PYP_CONFIG_PATH="$HOME/.ipython/profile_default/pyp_config.py"

# if [[ -f "$HOME/debug.py" ]]; then
#   export PYTHONDEBUGFILE="$HOME/debug.py"
#   export PYTHONSTARTUP="$PYTHONDEBUGFILE" # Executed only on interactive startup (no default)
# fi

# export SHELLCHECK_OPTS='-e SC2016 -e SC2034 -e SC2155 -e SC2164 -e SC2140 -e SC1090 -e SC2030 -e SC2031 -e SC2004 -e SC2120'
[[ $- == *i* ]] && export CD_PATCH=true
