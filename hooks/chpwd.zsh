# DEV_LOG_FORMAT='%(asctime)s %(levelname)-8s %(name)s:%(lineno)d %(funcName)s │ %(message)s'

potentially_activate_venv() {
  local venv_dir
  for venv_dir in ./.venv ./.env ./venv ./env; do
    [[ -f "$venv_dir/bin/activate" ]] || continue
    source "$venv_dir"/bin/activate 2>/dev/null
    return $?
  done
  silence deactivate
}

toggle_node_modules_bin_in_PATH() {
  if [[ -d "$PWD/node_modules/.bin" ]]; then
    pathprepend "$PWD/node_modules/.bin" -q
  else
    local previous_dir="${dirstack[1]}"
    if [[ "$previous_dir" ]] && silence pathi "$previous_dir/node_modules/.bin"; then
      pathdel "$previous_dir/node_modules/.bin" -q
    fi
  fi
}

load_dot_env_in_whitelisted_dirs() {
  if [[ 
    "$PWD" == "$HOME"/dev/aloud ]] &&
    [[ -f ./.env ]]; then
    loadenvfile ./.env
  fi
}

# add-zsh-hook chpwd potentially_activate_venv
add-zsh-hook chpwd toggle_node_modules_bin_in_PATH
# add-zsh-hook chpwd load_dot_env_in_whitelisted_dirs

# Also run them on startup:
# potentially_activate_venv
toggle_node_modules_bin_in_PATH
# load_dot_env_in_whitelisted_dirs
