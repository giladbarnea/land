#!/usr/bin/env bash

: "${THIS_SCRIPT_DIR:=$(dirname -- "$0")}"

# Check out `bgnotify` OMZ plugin

if [[ "$OS" == Linux ]]; then
  source "$THIS_SCRIPT_DIR/notify.linux.sh"
else
  source "$THIS_SCRIPT_DIR/notify.mac.sh"
fi

