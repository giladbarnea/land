#!/usr/bin/env zsh

alias lst='powershell.exe -C "tree /F"'

if [[ -e "$PROGFILES/Meld/Meld.exe" ]]; then
	alias meld="'$PROGFILES/Meld/Meld.exe'"
elif [[ -e "$PROGFILES86/Meld/Meld.exe" ]]; then
	alias meld="'$PROGFILES86/Meld/Meld.exe'"
fi

function open() {
	if [[ -z "$1" ]]; then
		log.fatal "open() needs 1 arg"
		return 1
	fi
	local with_backslashes
	# shellcheck disable=SC1003
	with_backslashes=$(tr '/' '\\' <<< "$1")
	log.debug "with_backslashes: $with_backslashes"
	powershell.exe -C "$with_backslashes"
}