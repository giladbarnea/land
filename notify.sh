#!/usr/bin/env bash

# Check out `bgnotify` OMZ plugin

if [[ "$OS" == Linux ]]; then
  source notify.linux.sh
else
  source notify.mac.sh
fi

