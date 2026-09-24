#!/usr/bin/env zsh
# This script is a rule of thumb, not a binding procedure.
# Agents are encouraged to write their own temporary test scripts when that helps the task at hand.
#
# # comptest.zsh LINE...
# Types each LINE into a fresh `zsh -f -i`, presses Tab, and prints what the shell shows afterwards:
# the completed command line, or the match listing when the completion is ambiguous.
# Uses the completion scripts in this directory, not the installed ones.
zmodload zsh/zpty

completions_dir="${0:A:h}"

# The pty shell runs input only while its output is being read, so every step drains it.
function drain_pty_output() {
	local chunk
	local -i step
	for step in {1..$1}; do
		zpty -r -t comptest chunk && pty_output+=$chunk
		sleep 0.1
	done
}

function comptest() {
	local pty_output=''
	zpty comptest zsh -f -i
	zpty -w -n comptest "fpath=('$completions_dir' \$fpath); autoload -Uz compinit; compinit -u -D; PROMPT='> '"$'\r'
	drain_pty_output 15
	pty_output=''
	zpty -w -n comptest "$1"$'\t'
	drain_pty_output 20
	zpty -d comptest
	print -r -- "=== $1"
	print -r -- "$pty_output" | tr -d '\r' | sed $'s/\x1b\\[[0-9;?]*[a-zA-Z]//g' | tail -n 8
	print
}

for line in "$@"; do
	comptest "$line"
done
