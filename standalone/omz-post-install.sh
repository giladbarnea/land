#!/usr/bin/env zsh

"${ZSH_CUSTOM:="$ZSH"/custom}"

function download_zsh_plugins_and_theme(){
  local GH=https://github.com
  declare -A custom_addons=(
    [plugins/zsh-autosuggestions]=zsh-users/zsh-autosuggestions.git
    [plugins/fast-syntax-highlighting]=zdharma-continuum/fast-syntax-highlighting.git
    [plugins/you-should-use]=MichaelAquilina/zsh-you-should-use.git
    [themes/powerlevel10k]=romkatv/powerlevel10k.git
  )

  for addon in "${(k)custom_addons[@]}"; do
    if [ ! -e "$ZSH_CUSTOM"/$addon ]; then
      if ! confirm "$ZSH_CUSTOM/$addon does not exist, clone?"; then continue; fi
      log.info "Cloning ${custom_addons[$addon]} into $ZSH_CUSTOM/$addon..."
      vex git clone --depth=1 $GH/${custom_addons[$addon]} "$ZSH_CUSTOM"/$addon
    fi
  done
}

function download_zshrc(){
  log.warn "Not implemented. Use gh gist"
}

function set_macos_settings(){
  hidutil property --set '{"CapsLockDelayOverride":0}'
}
function main(){
  # set -o errexit
  { ! type isdefined \
    && source <(wget -qO- https://raw.githubusercontent.com/giladbarnea/land/master/{util,log}.sh --no-check-certificate) ;
  } &>/dev/null

  [[ "${BASH_SOURCE[0]}" == "${0}" ]] && {
    log.error "Detected bash. returning 1"
    return 1
  }

  if [[ ! -d "$ZSH" || ! -d "$HOME"/.oh-my-zsh || ! -f "$HOME"/.zshrc ]]; then
    log.error "Oh-My-Zsh is not installed, or $HOME/.zshrc does not exist. Aborting"
	  return 1
  fi


  download_zshrc
  download_zsh_plugins_and_theme
  set_macos_settings
}

main "$@"
