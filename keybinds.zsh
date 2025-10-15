#!/usr/bin/env zsh

# https://en.wikipedia.org/wiki/GNU_Readline#Emacs_keyboard_shortcuts
# http://web.cs.elte.hu/zsh-manual/zsh_14.html#SEC49
# https://skorks.com/2009/09/bash-shortcuts-for-maximum-productivity/
# https://github.com/junegunn/fzf/issues/546#issuecomment-213344845
# cat -v      # Show control characters
# bindkey -L  # List all key bindings
# zle -l [-L] # List all widgets or functions

# ---[ Glossary ]---
# Code 	Key 	Example
# --------------------------
# ^ 	Ctrl	^/ = Ctrl+/
# ^[ 	Esc

bindkey -M emacs "^ "  _expand_alias    # This worked when vi plugin is set on but not installed 
bindkey -M viins "^ "  _expand_alias    # This works (old comment: both with and without vi plugin. now vi plugin is set on but is not installed and it doesn't work)
bindkey -M vicmd "^ "  _expand_alias    # This works with vi plugin when in cmd mode (ESC)
##bindkey -M emacs "^[ "  _expand_alias  # Esc+Space

bindkey -M vicmd "_" insert-last-word   # Cmd (ESC) + '_'. This also works in visual mode
bindkey -M vicmd "m" copy-prev-shell-word   # Cmd (ESC) + '_'. This also works in visual mode

# Looks better: zdharma-continuum/history-search-multi-word
bindkey '^[[A' history-substring-search-up    # up arrow
bindkey '^[[B' history-substring-search-down  # down arrow


# Runs `bath <buffer>` on Esc+h
run_bathelp_on_buffer() {
  local -a words=(${(z)BUFFER})
  [[ -z "${words[1]}" ]] && {
    # Save cursor position, print message, restore cursor position, remove message.
    echo -n $'\e7'
    log.warn "No words in buffer" -n
    sleep 1
    echo -n $'\e8'
    echo -n $'\e[0J'
    return 1
  }
  [[ "$BUFFER" == "bath "* ]] && return 0
  BUFFER="bath ${words[1]}"
  zle .accept-line
}
zle -N run_bathelp_on_buffer
bindkey '^[h' run_bathelp_on_buffer  # Esc+h

# Runs `ds <buffer>` on Esc+d
run_docstring_on_buffer() {
  local -a words=(${(z)BUFFER})
  [[ -z "${words[1]}" ]] && {
    # Save cursor position, print message, restore cursor position, remove message.
    echo -n $'\e7'
    log.warn "No words in buffer" -n
    sleep 1
    echo -n $'\e8'
    echo -n $'\e[0J'
    return 1
  }
  [[ "$BUFFER" == "ds "* || "$BUFFER" == "docstring "* ]] && return 0
  BUFFER="docstring -p ${words[1]}"
  zle .accept-line
}
zle -N run_docstring_on_buffer
bindkey '^[d' run_docstring_on_buffer  # Esc+d

# Runs `ts <buffer>` on Esc+t
run_typeset_on_buffer() {
  local -a words=(${(z)BUFFER})
  [[ -z "${words[1]}" ]] && {
    # Save cursor position, print message, restore cursor position, remove message.
    echo -n $'\e7'
    log.warn "No words in buffer" -n
    sleep 1
    echo -n $'\e8'
    echo -n $'\e[0J'
    return 1
  }
  [[ "$BUFFER" == "ts "* || "$BUFFER" == "typeset "* ]] && return 0
  BUFFER="ts ${words[1]}"
  zle .accept-line
}
zle -N run_typeset_on_buffer
bindkey '^[t' run_typeset_on_buffer  # Esc+t

# Runs `batw <buffer>` on Esc+w
run_batw_on_buffer() {
  local -a words=(${(z)BUFFER})
  [[ -z "${words[1]}" ]] && {
    # Save cursor position, print message, restore cursor position, remove message.
    echo -n $'\e7'
    log.warn "No words in buffer" -n
    sleep 1
    echo -n $'\e8'
    echo -n $'\e[0J'
    return 1
  }
  [[ "$BUFFER" == "batw "* ]] && return 0
  BUFFER="batw ${words[1]}"
  zle .accept-line
}
zle -N run_batw_on_buffer
bindkey '^[w' run_batw_on_buffer  # Esc+w

