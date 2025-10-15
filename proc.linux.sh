# # proc.get_focusable <ID_OR_NAME>
# Anything that `xdotool windowactivate` can work with is focusable.
# (e.g. a bundle id or app path).
function proc.get_focusable(){
	local name="$1"
	shift 1 || { log.error "$0: Not enough args (expected 1, got ${#$}). Usage:\n$(docstring "$0")"; return 2; }
	# Linux
	if isnum "$name"; then
		# This needs distinguishing between hexid, pid
		printf "%s" "$name"
		return 0
	fi
	log.error "$0 doesn't know how to handle '$name', printing as-is and returning 2"
	printf "%s" "$name"
	return 2
}

# # proc.focus <EXECUTABLE_OR_PID>
function proc.focus(){
	isdefined xdotool || {
		log.error "Must have xdotool installed to use $0"
		return 1
	}
	local executable_or_pid="$1"
	shift 1 || { log.error "$0: Not enough args (expected 1, got ${#$}). Usage:\n$(docstring "$0")"; return 2; }
	local focusable="$(proc.get_focusable "$executable_or_pid")"
	local xdotool_windowactivate_output
	xdotool_windowactivate_output="$(vex xdotool windowactivate "$focusable" 2>&1)"
	if [[ -z "$xdotool_windowactivate_output" ]]; then
		log.success "${Cc}xdotool windowactivate '$focusable'${Cc0} raised no err. returning 0"
		return 0
	else
		log.warn "${Cc}xdotool windowactivate '$focusable'${Cc0} raised err: ${Ci}${proc_focus_output}"
		return 1
	fi
}