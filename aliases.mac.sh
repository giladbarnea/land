#!/usr/bin/env zsh

# alias code='(){ if [[ "$1" && ! -e "$1" ]]; then open -a "Visual Studio Code" --args "$@"; else open -a "Visual Studio Code" "$@"; fi ; }'
alias cut=gcut
alias realpath=grealpath

alias pif='pi --model claude-bridge/claude-fable-5'
alias pio='pi --model claude-bridge/claude-opus-4-8'
alias pis='pi --model claude-bridge/claude-sonnet-5'
alias pih='pi --model claude-bridge/claude-haiku-4-5'
