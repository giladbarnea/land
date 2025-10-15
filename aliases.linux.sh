#!/usr/bin/env zsh

alias open='xdg-open'
alias xdt='xdotool'
alias wmc='wmctrl'
alias java=/snap/libreoffice/current/usr/lib/jvm/java-11-openjdk-amd64/bin/java
if type brave &>/dev/null-browser; then
	alias brave=brave-browser
elif type google &>/dev/null-chrome; then
	alias chrome=google-chrome
fi