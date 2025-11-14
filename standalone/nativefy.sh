#!/usr/bin/env bash
# sourced towards the end, after launch.sh

function nativefier._kill_running_app() {
	if [[ -z "$(pgrep -f ".*$appname.*")" ]]; then
		log.success "[nativefier._kill_running_app] no processes with \"$appname\" existed in the first place"
		return 0
	fi
	if ! proc.killgrep ".*$1.*"; then
		log.fatal "[nativefier._kill_running_app] failed proc.killgrep; kill processes yourself and retry"
		return 1
	fi
	return 0
}

function nativefier._has_latest_version(){
	if python3.12 -c "import subprocess as sp
import sys
out = sp.getoutput('gh release list -R jiahaog/nativefier').splitlines()
latest = out[0].removeprefix('Nativefier').partition('\t')[0].strip()[1:]
current = sp.getoutput('nativefier --version')
print(f'[nativefier._has_latest_version] {current = }, {latest = }', file=sys.stderr)
sys.exit(0) if current >= latest else sys.exit(1)"
	then
		return 0
	else
		return 1
	fi
	# local versions
	# if ! versions="$(vex gh release list -R jiahaog/nativefier)"; then
	# 	log.warn "failed getting list of releases with gh cli"
	# 	return 1
	# fi
	# local verline
	# verline="$(echo "$versions" | head -1)"
	# local latest
	# # Nativefier v42.0.2	Latest	v42.0.2	2020-12-07T21:52:58Z
	# # -> v42.0.2	Latest	v42.0.2	2020-12-07T21:52:58Z
	# # -> v42.0.2	%
	# # -> 42.0.2	%
	# # -> 42.0.2%
	# latest=$(echo -n "$verline" | cut -d' ' -f2 | cut -z -d'L' -f1 | cut -z -d'v' -f2 | tr -d '[:space:]' | tr -d '\n')
	# local current
	# current="$(nativefier --version | tr -d '\n')"
	# log.debug "latest: $latest | current: $current"
	# local pyout=$(python3 -c "print('''$current''' >= '''$latest''')" 2>&1);
	# log.debug "pyout: $pyout"
	# if is_true "$pyout"; then
	# 	return 0
	# else
	# 	return 1
	# fi
}

# # nativefy <APPNAME> <URL> [OPTIONS...]
# ## OPTIONS
#   --tray                  off by default
#   --useragent=STRING      tries to fetch from google, or prompts for input if fails
#   --iconpath=FILEPATH     looks in /tmp/APPNAME.png, or 'nativefier-icons' repo
#   --installdir=DIRPATH    defaults to $HOME/.local/share
#
# ## Vanilla 'nativefier' usage:
# `nativefier [options] URL [dest]`
#
# ## Examples:
# `nativefy whatsapp 'https://web.whatsapp.com'`
function nativefy() {
	log.title "nativefy(${*})"
	maybe_help "$1" "$0" && return 0
	if [[ -z "$2" ]]; then
		log.fatal "expecting at least 2 positional args"
		docstring -p "$0"
		return 1
	fi
	if ! isdefined nativefier; then
		log.fatal "'nativefier' is not a cmd, aborting"
		return 1
	fi
	# *** Check for updates
	if confirm "Check if nativefier update available?"; then
		log.debug "python running ${Cc}gh release list -R jiahaog/nativefier"
		if nativefier._has_latest_version; then
			log.success "you have the latest version"
		else
			if confirm "You don't have latest version. upgrade?"; then
				local _yarn_global_dir="$(yarn global dir)"
				vex yarn upgrade -L --cwd "\"$_yarn_global_dir\"" --non-interactive nativefier || return 1
			fi
			# local prev_pwd="$PWD"
			# vex cd "'$(yarn global dir)' --quiet" || return 1
			# vex yarn upgradeInteractive -L nativefier || return 1
			# vex cd "'$prev_pwd' --quiet" || return 1
			
		fi
	fi
	local _tmp_val
	local appname
	local url

	local installdir
	local apppath
	local iconpath

	local NATIVEFIER_ARGS=()
	local internalurls
	local iconurl

	local py_useragent_code
	local firefox_ver
	local useragent

	local prompt

	local execpath

	local alias_str
	local existing_alias
	local py_alias_code
	local user_answer

	# "whatsapp"
	appname="$1"
	url="$2"
	shift 2

	# *** Argument parsing
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--tray)

			NATIVEFIER_ARGS+=(--tray)
			log.debug "added '--tray' to NATIVEFIER_ARGS"
			shift ;;
		--useragent=*)
			_tmp_val="${1##*=}"
			if [[ "$_tmp_val" == "Mozilla/"* ]]; then
				useragent="$_tmp_val"
				log.debug "useragent: '$useragent'"
			else
				log.warn "bad: '$1'"
			fi
			shift ;;
		--iconpath=*)
			_tmp_val="${1##*=}"
			if [[ -f "$_tmp_val" ]]; then
				iconpath="$_tmp_val"
				log.debug "iconpath: '$iconpath'"
			else
				log.warn "does not exist or is not a file: '$1'"
			fi

			shift ;;
		--installdir=*)
			_tmp_val="${1##*=}"
			if [[ -d "$_tmp_val" ]]; then
				installdir="$_tmp_val"
				log.info "installdir: '$installdir'"
			else
				log.warn "does not exist or is not a dir: '$1'"
			fi
			shift ;;
		*)
			log.warn "unknown arg: '$1'. ignoring"
			shift ;;
		esac
	done

	if [[ -z "$installdir" ]]; then
		installdir="$HOME/.local/share"
	fi
	apppath="$installdir/$appname"

	# *** Handle possibly existing processes
	if ! nativefier._kill_running_app "$appname"; then
		log.fatal "failed killing $appname"
		return 1
	fi
	
	# *** Handle possibly existing target dir
	if [[ -e "$apppath" ]]; then
		user_answer="$(input "target path already exists: '$apppath'. what to do? [o]verwrite, [r]ename existing, [q]uit")"
		case "$user_answer" in
		q)
			log.warn "user aborted"
			return 2 ;;
		r) # rename
			vex mv "'$apppath'" "'${apppath}__backup'" || return 1 ;;
		o) # overwrite
			vex rm -rf "'$apppath'" || return 1 ;;
		*)
			log.fatal "unknown option: $user_answer. aborting"
			return 1 ;;
		esac
	fi

	# *** Handle possibly existing config dirs in ~/.config
	log.info "looking for possible pre-existing config dirs in ~/.config..."
	local configdirs=()
	find "$HOME/.config" -maxdepth 1 -type d -iname "$appname-nativefier*" | while read -r configdir; do
		configdirs+=("$configdir")
	done
	# can't do it inside the while above, because confirm doesnt stop execution
	for configdir in "${configdirs[@]}"; do
		if confirm "found '$configdir'; remove?"; then
			vex "rm -rf \"$configdir\""
		fi
	done
	

	# *** Icon
	if [[ -z "$iconpath" ]]; then
		iconpath="/tmp/$appname.png"
	fi

	if [[ -f "$iconpath" ]]; then
		log.success "found existing $iconpath, using it"
		NATIVEFIER_ARGS+=(-i "$iconpath")
	else
		log.warn "icon does not exist in '$iconpath'. trying to get icon from github..."
		iconurl="https://raw.githubusercontent.com/jiahaog/nativefier-icons/gh-pages/files/$appname.png"
		if vex curl -f --fail-early --create-dirs "'$iconurl'" -o "'$iconpath'"; then
			NATIVEFIER_ARGS+=(-i "$iconpath")
		fi
	fi

	# *** User Agent
	# navigator.userAgent
	# https://www.whatismybrowser.com/guides/the-latest-user-agent/firefox

	if [[ -z "$useragent" ]]; then
		py_useragent_code='
import requests
import re
import sys
res = requests.get("https://www.google.com/search?q=chrome+latest+user+agent")
if not res.ok:
    sys.exit("[nativefier] python: res not ok")
match = re.search(r"Mozilla/\d+\.\d+ \(X11; Linux x86_64\) AppleWebKit/(\d+\.\d+) \(KHTML, like Gecko\) Chrome/\d+\.\d+\.\d+\.\d+ Safari/\1", res.text)
if not match:
    sys.exit(f"[nativefier] python: no match")
print(match.group(), end="")
  '
		log.info "python: making google request to get chrome user agent..."
		if useragent="$(python3 -c "$py_useragent_code")"; then
			# Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/87.0.4280.88 Safari/537.36
			# useragent="Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:$firefox_ver) Gecko/20100101 Firefox/$firefox_ver"
			log.success "successfully got useragent from google: '$useragent'"
		else
			useragent="$(input "failed getting useragent from google, please insert chrome user agent (no quotes; e.g. Mozilla/...)")"
			# shellcheck disable=SC2076
			while ! [[ "$useragent" =~ "Mozilla/[0-9]+\.[0-9]+ \(X11; Linux x86_64\) AppleWebKit/[0-9]+\.[0-9]+ \(KHTML, like Gecko\) Chrome/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ Safari/[0-9]+\.[0-9]+" ]]; do
				useragent="$(input "bad answer: '$useragent'.\n\tplease try again")"
			done
		fi
	fi

	# *** Nativefier arguments
	internalurls=".*?$appname.*?" # if doesn't work, try having accounts\.google\.com
	# consider internalurls=".*"
	# newer versions of nativefier seem to work fine without explicitly setting internal urls (at least google hangouts works without setting anything, and doesn't work when indeed setting)
	# NATIVEFIER_ARGS+=(-u "$useragent" --insecure --single-instance "--internal-urls=\"$internalurls\"" --name "$appname")
	
	# don't extra escape
	NATIVEFIER_ARGS+=(--user-agent "$useragent" --insecure --single-instance --internal-urls "$internalurls" --name "$appname")

	prompt="
  
  Confirm:
  --------
  name: '$appname'
  url: '$url'
  user agent: '$useragent'
  installdir: '$installdir' (will be installed in '$apppath')
  NATIVEFIER_ARGS:
  ${NATIVEFIER_ARGS[*]}
  
  what to do? [c]ontinue | [q]uit | add --[t]ray option
  "
	user_answer="$(input "$prompt")"
	case "$user_answer" in
	q)
		log.warn "user aborted"
		return 1 ;;
	t)
		NATIVEFIER_ARGS+=(--tray)
		log.info "added '--tray' option" ;;
	c) : ;;
	*)
		log.fatal "unknown option: $user_answer. aborting"
		return 1 ;;
	esac

	# *** Running nativefier
	set -x
	if ! nativefier "${NATIVEFIER_ARGS[@]}" "$url" "$installdir"; then
		set +x
		log.fatal "failed 'nativefier' command, aborting"
		return 1
	fi
	set +x
	if [[ -d "$apppath-linux-x64" ]]; then
		vex mv "'$apppath-linux-x64'" "'$apppath'" || return 1
	fi

	# todo: .desktop file

	# *** Post install: alias
	if [[ -d "$apppath" ]]; then
		log.success "created dir successfully: $apppath"
		execpath="$apppath/$appname"
		if [[ -f "$execpath" ]]; then
			log.success "installed successfully with exec file: $execpath"
			if ! confirm "try to add alias to ${LAND}/init.sh? (with basic checks beforehand)"; then
				log.info "ok, done. returning 0"
				return 0
			fi
			alias_str="alias $appname='launch $execpath'"
			log.info "alias_str: $alias_str. doing checks before adding alias to init.sh..."

			if existing_alias=$(grep -P "^alias $appname" "${LAND}"/init.sh); then
				if grep -P "$alias_str" "${LAND}"/init.sh; then
					log.success "correct alias already found in ${LAND}/init.sh, script finished"
					return 0
				else
					log.warn "an alias to $appname was found in ${LAND}/init.sh, but it's a bad path. existing alias:\n$existing_alias\n"
					return 1
				fi
			else
				# no existing alias
				log.info "no existing alias found in ${LAND}/init.sh; adding new"
				py_alias_code="
import os
with open('${LAND}/init.sh') as f:
    lines = f.readlines()
execs_aliases_i = lines.index(next(l for l in lines if '# execs aliases' in l))
first_empty_line_after_i = lines[execs_aliases_i:].index(next(l for l in lines if not l)) + execs_aliases_i
alias_str=\"$alias_str\"
lines_with_alias = lines[:first_empty_line_after_i] + [alias_str] + lines[first_empty_line_after_i:]
os.system('cp ${LAND}/init.sh ${LAND}/init.sh.backup')
with open('${LAND}/init.sh.test', mode='w') as f:
    f.writelines(lines_with_alias)
        "
				if python3 -c "$py_alias_code"; then
					log.success "added '$alias_str' to ${LAND}/init.sh successfully"
					return 0
				else
					log.warn "failed adding alias str to ${LAND}/init.sh, returning 1"
					return 1
				fi
			fi
		else
			log.fatal "$execpath is not a file, returning 1"
			return 1
		fi
	else
		log.fatal "dir '$apppath' does not exist"
		return 1
	fi
}
