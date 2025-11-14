#!/usr/bin/env bash
# shellcheck disable=SC2139,SC1091,SC2142
# Requires brew packages: coreutils, grep, gnu-sed

# Early stop: this repo targets zsh. If sourced from bash, abort.
if [ -n "${BASH_VERSION:-}" ]; then
  printf "init.sh: detected bash (BASH_VERSION=%s).\n" "${BASH_VERSION}" 1>&2
  printf "Please source this file from zsh instead.\n" 1>&2
  return 1
fi

set -o pipefail
# command -v realpath >/dev/null 2>&1 || alias realpath='readlink -f'		# no coreutils; happens on fresh macos
export COMING_FROM_INIT=true
THIS_SCRIPT_DIR="${0%/*}"

# [[ -e "/usr/share/powerline/bindings/zsh/powerline.zsh" && -z "$BATS_TEST_FILENAME" ]] && source "/usr/share/powerline/bindings/zsh/powerline.zsh"

source "$THIS_SCRIPT_DIR/environment.sh"
source "$THIS_SCRIPT_DIR/aliases.sh" # docker.sh relies on alias cut=gcut
source "$THIS_SCRIPT_DIR/term.zsh"
source "$THIS_SCRIPT_DIR/log.sh"
source "$THIS_SCRIPT_DIR/util.sh"
source "$THIS_SCRIPT_DIR/inspect.sh"
source "$THIS_SCRIPT_DIR/python.sh"
source "$THIS_SCRIPT_DIR/str.sh" # Maybe before python.sh?
source "$THIS_SCRIPT_DIR/tools.sh"
source "$THIS_SCRIPT_DIR/pretty.sh"
source "$THIS_SCRIPT_DIR/llm.zsh"
source "$THIS_SCRIPT_DIR/nav.sh" # 'cd' related functions
source "$THIS_SCRIPT_DIR/fs.sh"  # mkcdir, mountdevice
source "$THIS_SCRIPT_DIR/notify.sh"
source "$THIS_SCRIPT_DIR/git.sh"
source "$THIS_SCRIPT_DIR/ghcli.sh"
source "$THIS_SCRIPT_DIR/history.sh" # hs/hsi/hl
source "$THIS_SCRIPT_DIR/async.zsh"
source "$THIS_SCRIPT_DIR/pkgmgr.sh" # brew, apt, snap
source "$THIS_SCRIPT_DIR/misc.sh"   # editfile, countlines, bashh, zshh
source "$THIS_SCRIPT_DIR/fzf.sh"
source "$THIS_SCRIPT_DIR/paths.sh" # cppwd, cppath, resolve
source "$THIS_SCRIPT_DIR/keybinds.zsh"
source "$THIS_SCRIPT_DIR/scraping.sh"
source "$THIS_SCRIPT_DIR/convert.sh"
# [[ "$ZSH" ]] && source "$THIS_SCRIPT_DIR/zsh_advanced_history.zsh"

# shellcheck disable=SC2188
if is_interactive; then
  source <(<"$THIS_SCRIPT_DIR"/completions/_*)
fi

# shellcheck disable=SC2188
source <(<"$THIS_SCRIPT_DIR"/hooks/*.zsh)
