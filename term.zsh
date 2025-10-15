#!/usr/bin/env zsh
# Sourced third, after aliases.sh

# ==========[ Visual manipulation of text ]==========

# -------------[ Colors ]-------------

# All control codes:
# https://www.compart.com/en/unicode/category/Cc
# Awesome escape codes (cursor control):
# https://gist.github.com/fnky/458719343aabd01cfb17a3a4f7296797
# Moving Cursor
# echo -n $'\e[#A'  # Move cursor up # lines          ↑
# echo -n $'\e[#B'  # Move cursor down # lines        ↓
# echo -n $'\e[#C'  # Move cursor right # lines       →
# echo -n $'\e[#D'  # Move cursor right # lines       ←
# echo -n $'\e[#E'  # Move cursor to the beginning of # lines down
# echo -n $'\e[#F'  # Move cursor to the beginning of # lines up
# echo -n $'\e[#G'  # Move cursor to column #

# Cursor State: Movement
# echo -n $'\e7'  # Save cursor position
# echo -n $'\e8'  # Restore cursor position

# Erasing
# echo -n $'\e[0J'  # Erase screen from cursor down
# echo -n $'\e[1J'  # Erase screen from cursor up
# echo -n $'\e[2J'  # Erase entire screen

# echo -n $'\e[0K'  # Erase line from cursor right    ▎→
# echo -n $'\e[1K'  # Erase line from cursor left   ← ▎
# echo -n $'\e[2K'  # Erase entire line             ← ▎→

# Cursor State: Erasing
# echo -n $'\e[3J'  # Erase saved lines

# Screen / Buffer
# echo -n $'\e[?47h'    # Start alternate screen
# echo -n $'\e[?47l'    # Restore normal screen
# echo -n $'\e[?1049h'  # Start alternate buffer
# echo -n $'\e[?1049l'  # Restore normal buffer

# for i in {30..97}; do print -P "%B%F{$i} $i%f%b"; done
# print -P "%F{#999}grey%f"
# See 'man zshmisc' section 'Visual effects' and 'man zshzle' section 'CHARACTER HIGHLIGHTING'

export C0="\033[0m"
export Cb="\033[1m"
export Cb0="\033[22m"
export Cd="\033[2m"
export Cd0="\033[22m"
export Ci="\033[3m"
export Ci0="\033[23m"
export Cul="\033[4m"
export Cul0="\033[24m"
# White fg, 30,30,30 bg, italic
#export Cc="\033[37;3;48;2;30;30;30m"
#export Cc="\033[38;2;201;209;217;48;2;44;47;51m"
#export Cc="\033[38;2;201;209;217;48;2;30;33;36m"
#export Cc="\033[38;2;201;209;217;48;2;39;40;34m"
# export Cc="\033[38;2;240;246;252;48;2;21;27;35m "  # Github dark theme.
export Cc="\033[38;2;254;95;95;48;2;48;48;48m " # Glow Glamour theme (similar to Notion)
# Reset fg, bg and italic
export Cc0=" \033[39;49m"

export Cfg0="\033[39m"

export Cblk="\033[30m"
export Cred="\033[31m"
export Cgrn="\033[32m"
export Cylw="\033[33m"
export Cblu="\033[34m"
export Cmgta="\033[35m"
export Ccyn="\033[36m"
export Cwht="\033[37m"

export CbrBlk='\033[90m' # darker than Cd
export CbrRed='\033[91m'
export CbrGrn='\033[92m'
export CbrYlw='\033[93m'
export CbrBlu='\033[94m'
export CbrMgta='\033[95m'
export CbrCyn='\033[96m'
export CbrWht='\033[97m'

# Bold (1) and white on light purple (from glow) | log.title
export h1="${Cb}${Cfg0}\033[48;2;95;95;255m"
# Bright white (97) | log.notice, log.prompt, confirm, hi
export h2="${CbrWht}"

# Reset h1 and h2 codes (bold, underline and fg)
export h0="\033[22;24;39m"

# # decolor <TEXT>
function decolor() {
	local text="${1:-$(<&0)}"
	# `##`: Match one or more. `#`: Match zero or more.
	text=${text//$'\C-[['(<0-9>##;#)##m/}
	print -r -- $text
}

# # align <TEXT> <PERCENTAGE>
# Aligns text to the right by PERCENTAGE of the screen width.
# PERCENTAGE format can be e.g. `50`, `50%`, `0.5`.
function align() {
	local -i msg_len="${#$(decolor "$1")}"
	local -F width_percentage="${2%%%}"
	# Ensure width_percentage is [0-1]
	((width_percentage = width_percentage >= 1 ? width_percentage / 100 : width_percentage))
	local -i left_padding="$((width_percentage * (COLUMNS - msg_len) + msg_len))"
	printf "%${left_padding}s%s" "$1"
}

function center-align() {
	align "$1" 50
}

function right-align() {
	align "$1" 100
}

function box() {
	# https://www.compart.com/en/unicode/html  <- for all
	# https://en.wikipedia.org/wiki/Box-drawing_characters <- for all drawing chars
	local -i msg_len="${#1}"
	local -i box_len="$((COLUMNS / 2 - COLUMNS % 2))"
	local -i half_box_len="$((box_len / 2))"
	local -i left_padding="$((half_box_len - msg_len / 2))"
	local -i right_padding="$((half_box_len + 1 - (msg_len + 1) / 2))"
	# Top row
	printf "\n%${half_box_len}s┌" # Left-padding, top-left corner
	printf "─%.0s" {1..$box_len}  # Top border
	printf "┐\n"                  # Top-right corner
	# Middle row
	printf "%${half_box_len}s│"    # Left-padding, left border
	printf "%${left_padding}s"     # Internal left-padding of text
	printf "%b" "$1"               # Text
	printf "%${right_padding}s│\n" # Internal right-padding of text
	# Bottom row
	printf "%${half_box_len}s└"  # Left-padding, bottom-left corner
	printf "─%.0s" {1..$box_len} # Bottom border
	printf '┘'                   # Bottom-right corner
}

# # mdquote <TEXT>
# Prints TEXT in a quote block (indented, vertical bar, gray background).
function mdquote() {
	local value="${1:-$(<&0)}"
	echo "  \033[48;2;28;28;28;90m▍\033[39m  \033[2m${value}\033[0m"
}
