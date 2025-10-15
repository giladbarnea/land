#!/usr/bin/env bash

function dconfbackup() {
	local name
	name=$(date +"%d-%m-%Y_%H:%M:%S")
	if dconf dump / >"$HOME/dconf_$name"; then
		log.success "dumped dconf to $name"
		return 0
	else
		log.fatal "failed dumping dconf to $name"
		return 1
	fi
}

# # colorpick [--delay=4] [--loops=0]
function colorpick() {
	local delay=4
	local loops=0
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--delay=*)
			if [[ "$1" = *=* ]]; then
				delay="${1##*=}"
				shift
			else
				delay="$2"
				shift 2
			fi ;;
		--loops*)
			if [[ "$1" = *=* ]]; then
				loops="${1##*=}"
				shift
			else
				loops="$2"
				shift 2
			fi ;;
		*)
			shift ;;
		esac
	done

	log "Picking color in $delay seconds" -x
	sleep "$delay"

	unset X &>/dev/null
	unset Y &>/dev/null
	local X Y
	# evals X, Y
	eval "$(xdotool getmouselocation --shell | head -2)"
	local color
	if ! color=$(command import -window root -depth 8 -crop 1x1+"$X"+"$Y" txt:- | grep -om1 '#\w\+'); then
		return 1
	fi
	echo "$color"
	if [[ "$loops" -gt 0 ]]; then
		for _ in $(seq "$((loops - 1))"); do
			colorpick --delay="$delay" --loops=0 || return 1
		done
	fi
}