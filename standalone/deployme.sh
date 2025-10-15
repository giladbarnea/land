#!/usr/bin/env bash
{
# https://gist.github.com/dfontana/3e27ec5ea3a6f935b7322b580d3df318  # Windows Cmder Cygwin Zsh etc


if { ! type wget && ! type curl ; } &>/dev/null; then
	printf "\n  %b\n\n" "! $0 ERROR: Neither wget nor curl are installed, need at least one to do something" 1>&2
	printf "\n  %b\n\n" "  Install wget with apt (if you're on ubuntu), yum (if you're on centos) or apk (if you're on alpine)" 1>&2
	if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
		exit 1
	else
		return 1
	fi

fi

[ -z "$THIS_SCRIPT_DIR" ] && THIS_SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]:-$0}")")"

{ ! type isdefined \
	&& ! { source "$THIS_SCRIPT_DIR"/util.sh && source "$THIS_SCRIPT_DIR"/log.sh && source "$THIS_SCRIPT_DIR"/str.sh ; } \
	&& source <(curl --silent --parallel https://raw.githubusercontent.com/giladbarnea/land/master/{log,util,str}.sh) ;
	# && source <(wget -qO- https://raw.githubusercontent.com/giladbarnea/land/master/{util,log,str}.sh --no-check-certificate) ;
} &>/dev/null


declare os      # wsl | windows | centos | ubuntu | alpine | macos
#declare distro

# ------[ $os ]--------
# uname -m -> x86_64; uname -s -> Linux. See curl https://getmic.ro | bat -l bash for granular info
if [[ "$WSL_DISTRO_NAME" ]]; then
	os=wsl
elif [[ "$OS" =~ Windows(_NT) ]]; then
	os=windows
elif [[ "$OSTYPE" = darwin* ]]; then
	os=macos
else
	if ! os="$(grep -Eo '^ID=.+$' /etc/os-release | cut -c 4- | str.unquote)"; then
	# if distro="$(lsb_release -i)"; then
	#   if [[ "$distro" == *CentOS ]]; then
	# 	  # http://mirror.centos.org/centos/7/os/x86_64/Packages/
	# 	  os=centos
	#   elif [[ "$distro" == *Ubuntu ]]; then
	#   	os=ubuntu
	#   else
	#   	log.fatal "os is unset. distro: $distro"
	#   	return 1
	#   fi
		log.fatal "os is unset, failed grepping /etc/os-release | OS: $OS | OSTYPE: $OSTYPE"
		return 1
	fi
fi

log.info "os: ${Cb}$os${Cb0}"



# ------[ Helper Functions ]--------

# # get_latest_version <OWNER/REPO>
# Outputs 'v1.11.0'
function get_latest_version(){
	local htmlcontent grepped
	if htmlcontent="$(fetchhtml https://github.com/$1/releases/latest)"; then
		if grepped="$(echo "$htmlcontent" | grep -m 1 -Po "(?<=/$1/tree/)[\w.]+")"; then
			echo "$grepped" | cut -d $'\n' -f 1
			return 0
		fi
	fi
	if htmlcontent="$(fetchhtml https://api.github.com/repos/$1/releases/latest)"; then
		echo "$htmlcontent" | grep -m 1 -Po '(?<="name": ").+(?=")'
		return $?
	fi
	return 1
}

#complete -o default -C "completion.generate <OWNER/REPO>" get_latest_version
complete -o default -W '1:<OWNER/REPO>' get_latest_version

# # get_release_filenames <OWNER/REPO> <RELEASE>
function get_release_filenames(){
	local ownerrepo="$1"
	local release="$2"

	local filenames
	fetchhtml "https://github.com/$ownerrepo/releases/$release" \
			| grep -Eo "href=\"/$ownerrepo/releases/download/[^\"]+" \
			| rev | cut -d / -f 1 | rev
	return $?
}

complete -o default -W '1:<OWNER/REPO> 2:<RELEASE>' get_release_filenames

# # download_release <OWNER/REPO> [FILE REGEX=.*] [-r RELEASE=latest] [-o OUTPATH]
# Downloads the installation file to current dir
function download_release(){
	local ownerrepo="$1"
	shift || return 1
	local fileregex
	local release=latest
	local outpath
	while [[ $# -gt 0 ]]; do
		case "$1" in
			-o)
				outpath="$2"
				shift 2 ;;
			-r)
				release="$2"
				shift 2 ;;
			*)
				if [[ "$fileregex" ]]; then
					log.warn "$0: too many positional arguments, already set ownerrepo = $ownerrepo and fileregex = $fileregex. Ignoring $1"
				else
					fileregex="$1"
				fi
				shift ;;
		esac
	done

	if [[ ! "$fileregex" ]]; then
		fileregex=".*"
	fi
	log.debug "ownerrepo: ${ownerrepo} | fileregex: ${fileregex} | release: ${release} | outpath: ${outpath}"
	# local latest_ver="$(get_latest_version "$ownerrepo")"
	# log.debug "latest_ver: $latest_ver"
	# local release
	# local version  # semantic, e.g v1.11.0
	# if [[ ! "$1" || "$1" == "$latest_ver" || "$1" == latest ]]; then
	#   # releases/v1.11.0 doesnt work if it's latest, only releases/latest
	#   release=latest
	#   version="$latest_ver"
	# else
	#   release="$1"
	#   version="$1"
	# fi

	local filenames="$(get_release_filenames "$ownerrepo" "$release")"
	# No grep -P on some systems
	# if ! filenames="$(fetchhtml "https://github.com/$ownerrepo/releases/$release" | grep -Po "(?<=href\=\"/$ownerrepo/releases/download/)[^/]+/[^\"]+")"
	if [[ ! $filenames ]]; then
		log.warn "Failed fetching html of https://github.com/$ownerrepo/releases/$release"
		local correct_release="$(fetchhtml "https://github.com/$ownerrepo/releases" | grep -Eo -m1 "href=\"/$ownerrepo/tree/.*${release}[^\"]+")"
		if [[ ! $correct_release ]]; then
			log.fatal "Failed fetching https://github.com/$ownerrepo/releases and grepping for tree/.*${release}[^\"]+"
			return 1
		fi
		release="${correct_release##*/}"
		log.info "Corrected release to $release"
		filenames="$(get_release_filenames "$ownerrepo" "$release")"
		if [[ ! $filenames ]]; then
			log.fatal "Failed"
		fi
	fi

	local filtered_filenames=( $(echo "$filenames" | grep -E "$fileregex") )
	local filename
	if [[ ! ${filtered_filenames} ]]; then
		log.fatal "No files matched. Filenames:\n$filenames"
		return 1
	fi
	if [[ "${#filtered_filenames[@]}" -ge 2 ]]; then
		local prompt="Got multiple file matches, select one: (hint: on Linux, something like 'linux_amd64' or 'manylinux_amd64'; on Windows, 'windows_amd64')"
		if ! filename="$(input "$prompt" --choices "( ${filtered_filenames[*]} )")"; then return 3; fi
		log.debug "filename: $filename"
	else
		filename="${filtered_filenames}"
	fi

	# https://github.com/BurntSushi/ripgrep/releases/download/13.0.0/ripgrep_13.0.0_amd64.deb
	# https://github.com/BurntSushi/ripgrep/releases/latest/download/ripgrep_13.0.0_amd64.deb
	if [ "$release" = latest ]; then
		vex fetchfile https://github.com/"$ownerrepo"/releases/latest/download/"$filename" "$outpath" # ok if outpath is empty
	else
		vex fetchfile https://github.com/"$ownerrepo"/releases/download/"$release"/"$filename" "$outpath" # ok if outpath is empty
	fi
	return $?

}

complete -o default -W '1:<OWNER/REPO> 2:[FILEREGEX] [-r:RELEASE] [-o:OUTPATH]' download_release

# ------[ Install Functions ]--------

function install_font() {
	log.megatitle "install_font($*)" -x
	# ----[ Roboto Mono ]----
	# https://fonts.google.com/specimen/Roboto+Mono
	# fc-cat | grep -oP "(?<=fullname=)[^:]+"
	# sudo mkdir -pv /usr/share/fonts/truetype/robotomono || return 1
	# sudo mv *.ttf /usr/share/fonts/truetype/robotomono/

	# ----[ Nerd Fonts ]----
	# https://www.nerdfonts.com/font-downloads
	# "Patched" nerd fonts have added powerline symbols. (ryanoasis) looks better overall.
	#   Fira Code (non patched == tonsky) is an extension of Fira Mono with ligatures.
	#   Fira Italic:
	#   https://github.com/Avi-D-coder/fira-mono-italic/tree/master/distr/otf (better than zwaldowski)
	# ----[ Download / Installation ]----
	# 3 ways: desktop, package manager or script.
	# --[ Desktop ]--
	# Download zip from https://github.com/ryanoasis/nerd-fonts/tree/master/patched-fonts/FiraCode,
	#   extract and doubleclick -> install each file in ttf dir.
	# --[ package manager ]--
	# https://github.com/tonsky/FiraCode/wiki/Linux-instructions#installing-with-a-package-manager
	# sudo add-apt-repository universe && sudo apt install fonts-firacode
	# --[ manually ]--
	# https://github.com/tonsky/FiraCode/wiki/Linux-instructions#manual-installation (script below)
	# https://github.com/ryanoasis/nerd-fonts/tree/master/patched-fonts/FiraCode,
	#  go over all families (Bold, Light etc), Bold/complete/Fira Code Bold Nerd Font Complete.ttf or *Windows Compatible.ttf,
	#  move ttfs to ~/.local/share/fonts and fc-cache -f.
	#  Example urls:
	#  https://github.com/ryanoasis/nerd-fonts/blob/master/patched-fonts/FiraCode/Bold/complete/Fira%20Code%20Bold%20Nerd%20Font%20Complete.ttf?raw=true
	#  https://github.com/ryanoasis/nerd-fonts/blob/master/patched-fonts/JetBrainsMono/Ligatures/Bold/complete/JetBrains%20Mono%20Bold%20Nerd%20Font%20Complete.ttf?raw=true
	# OR ?:
	# https://github.com/ryanoasis/nerd-fonts/releases/download/v2.1.0/JetBrainsMono.zip
	# https://github.com/ryanoasis/nerd-fonts/releases/download/v2.1.0/FiraCode.zip

	local font_name="${1:-fira}"
	if [[ $font_name != fira && $font_name != jetbrains ]]; then
		log.fatal "Font name must be either fira or jetbrains. Got $font_name."
		return 1
	fi
	local fonts_dir="${HOME}/.local/share/fonts"
	if [ ! -d "${fonts_dir}" ]; then
			mkdir -vp "${fonts_dir}"
	else
			log.success "Found fonts dir $fonts_dir"
	fi


	local font_types=()
	# local file_path_prefix file_url_prefix
	if [[ $font_name == fira ]]; then
		function download_font(){
			local font_type="$1"
			local file_path="$fonts_dir/Fira Code ${font_type} Nerd Font Complete.ttf"
			if [[ -e "$file_path" ]]; then
				if [[ -s "$file_path" ]]; then
					log.success "Exists: $file_path"
					return 0
				fi
				log.warn "Exists but empty: $file_path. Overwriting"
				rm -v "$file_path"
			fi
			# local file_url="https://github.com/tonsky/FiraCode/blob/master/distr/ttf/FiraCode-${font_type}.ttf?raw=true"
			local file_url="https://github.com/ryanoasis/nerd-fonts/raw/master/patched-fonts/FiraCode/${font_type}/complete/Fira%20Code%20${font_type}%20Nerd%20Font%20Complete.ttf"
			wget --no-check-certificate -qO "${file_path}" "${file_url}"
			return $?
		}
		font_types=(Bold Light Medium Regular Retina SemiBold)
		# wget -q \
		#      https://github.com/ryanoasis/nerd-fonts/raw/master/patched-fonts/FiraCode/Regular/complete/Fira%20Code%20Regular%20Nerd%20Font%20Complete.ttf \
		#      -O "$fonts_dir/Fira Code Regular Nerd Font Complete.ttf"

	else
		function download_font(){
			 local font_type="$1"
			 local file_path="${HOME}/.local/share/fonts/JetBrainsMono-${font_type}.ttf"
				if [[ -e "$file_path" ]]; then
					if [[ -s "$file_path" ]]; then
						log.success "Exists: $file_path"
						return 0
					fi
					log.warn "Exists but empty: $file_path. Overwriting"
					rm -v $file_path
				fi
			 local font_type2
			 if [[ "$font_type" =~ .+Italic ]]; then
				 font_type2="${font_type/Italic/%20Italic}"
				else
				 font_type2="$font_type"
			 fi
			 local file_url="https://github.com/ryanoasis/nerd-fonts/blob/master/patched-fonts/JetBrainsMono/Ligatures/${font_type}/complete/JetBrains%20Mono%20${font_type2}%20Nerd%20Font%20Complete.ttf?raw=true"
			 # ExtraBoldItalic
			 # ThinItalic
			 # BoldItalic
			 # MediumItalic
			 # LightItalic
			 # ExtraLightItalic
			 wget --no-check-certificate -qO "${file_path}" "${file_url}"
			 return $?
		}
		font_types=(Bold BoldItalic ExtraBold ExtraBoldItalic ExtraLight ExtraLightItalic Italic Light LightItalic Medium MediumItalic Regular Thin ThinItalic)
	fi

	for font_type in ${font_types[@]}; do
			vex download_font "$font_type"
	done

	vex fc-cache -f
	fc-scan ~/.local/share/fonts | grep -C1 -i "${font_name}" | grep fullname:
	return 0

}


function install_fzf(){
# https://github.com/junegunn/fzf/releases
	log.megatitle "install_fzf($*)" -x
	if isdefined fzf && ! confirm "fzf seems to be installed; continue with installation anyway?"; then
		log.info "Returning 0"
		return 0
	fi
	local cmds=(
		'mkdir -p /tmp/fzf'
		'builtin cd /tmp/fzf'
	)
	if ! runcmds "${cmds[@]}"; then log.fatal Failed; return 1; fi
	case "$os" in
		ubuntu|wsl)
			cmds=(
				'download_release junegunn/fzf "linux_amd64.tar.gz"'
				'tar -xvf fzf*'
				'sudo mv ./fzf /usr/local/bin'
				'rm fzf-*.tar.gz'
			)
			if ! runcmds "${cmds[@]}"; then
				log.fatal Failed
				return 1
			fi
			log.success "Installed fzf successfully"
			if vex fetchhtml https://raw.githubusercontent.com/junegunn/fzf/master/man/man1/fzf.1 | sudo tee /usr/share/man/man1/fzf.1; then
				log.success "Downloaded fzf man page successfully"
			else
				log.success "Failed downloading fzf man page, but fzf itself is installed correctly"
			fi
			return 0 ;;
		*)
			log.fatal "dunno how to download fzf for os: $os"
			return 1 ;;
	esac
}

function install_micro() {
	log.megatitle "install_micro($*)" -x
	# curl https://getmic.ro | bash
	if isdefined micro && ! confirm "micro seems to be installed; continue with installation anyway? (includes plugins and settings)"; then
		log.info "Returning 0"
		return 0
	fi

	local cmds=(
		'builtin cd /tmp'
		'curl https://getmic.ro | $SHELL'
		'sudo mv ./micro /usr/local/bin'
		'micro -plugin install bounce manipulator filemanager monokai-dark'
		'mkdir -pv ~/.config/micro'
		'fetchfile https://gist.github.com/giladbarnea/969723d94efcd9c38da9293372fed960/raw/settings.json ~/.config/micro/settings.json'
		'fetchfile https://gist.github.com/giladbarnea/969723d94efcd9c38da9293372fed960/raw/bindings.json ~/.config/micro/bindings.json'
	)
	runcmds "${cmds[@]}"
	return $?
}

function install_ghcli() {
	log.megatitle "install_ghcli($*)" -x
	# https://github.com/cli/cli/releases
	if isdefined gh && ! confirm "gh seems to be installed; continue with installation anyway?"; then
		log.info "Returning 0"
		return 0
	fi
	if [[ $os == windows || "$os" == wsl ]]; then
		download_release cli/cli ".*msi" && \
		sudo apt install ./gh*
	else
		local cmds=(
			'sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-key C99B11DEB97541F0'
			'sudo apt-add-repository https://cli.github.com/packages'
			'sudo apt update'
			'sudo apt install gh'
		)
		runcmds "${cmds[@]}"
		return $?
	fi

}

function install_exa(){
	log.megatitle "install_exa($*)" -x
	# https://packages.debian.org/unstable/exa
	# https://the.exa.website/#installation
	if isdefined exa && ! confirm "exa seems to be installed; continue with installation anyway?"; then
		log.info "Returning 0"
		return 0
	fi
	download_release ogham/exa '.*linux-x86_64-v.*.zip' && \
	runcmds 'unzip exa-linux-x86_64*.zip -d exa'  \
					'sudo mv ./exa/bin/exa /usr/local/bin' \
					'sudo mv ./exa/man/exa.1 /usr/share/man/man1' || return 1

	if [[ ${SHELL##*/} == zsh ]]; then
		vex sudo mv ./exa/completions/exa.zsh /usr/local/share/zsh/site-functions/_exa
	else
		log.warn "Completion file was not installed. Try /usr/share/bash-completion/completions."
	fi
	return 0



}

function install_bat() {
	log.megatitle "install_bat($*)" -x
	if isdefined bat && ! confirm "bat seems to be installed; continue with installation anyway?"; then
		log.info "Returning 0"
		return 0
	fi
	mkdir -pv ~/.local/share || return 1
	builtin cd ~/.local/share || return 1
	local file_regex
	local post_download_commands=()
	case "$os" in
		windows|wsl)
			file_regex="x86_64-pc-windows-gnu.zip" ;;
		centos)
			file_regex="x86_64-unknown-linux-gnu.tar.gz"
			post_download_commands=(
				'tar --strip-components=1 -xvf "$bat_installation_file" "bat*bat"'
				'mv ./bat /usr/bin'
			) ;;
		ubuntu)
			file_regex="amd64.deb"
			post_download_commands=(
				'sudo apt install "$bat_installation_file"'
			) ;;
		*)
			log.warn "Don't how to download bat for os, not filtering github releases" ;;
	esac
	download_release sharkdp/bat "$file_regex" || {
		log.fatal Failed downloading
		return 1
	}

	log.debug "Finding bat*$file_regex file..."
	local bat_installation_file=$(find . -maxdepth 1 -type f -name "bat*$file_regex")
	if [[ ! "${post_download_commands[*]}" ]]; then
		log.warn "Installation file at $bat_installation_file, no predefined post_download_commands. Returning"
		return 1
	fi
	post_download_commands+=('rm "$bat_installation_file"')
	runcmds "${post_download_commands[@]}"
	return $?

}
function install_ripgrep() {
	log.megatitle "install_ripgrep($*)" -x
	#  https://github.com/BurntSushi/ripgrep/releases
	# wget -O ripgrep.tar.gz https://github.com/BurntSushi/ripgrep/releases/download/12.1.1/ripgrep-12.1.1-x86_64-unknown-linux-musl.tar.gz --no-check-certificate
	if isdefined rg && ! confirm "ripgrep seems to be installed; continue with installation anyway?"; then
		log.info "Returning 0"
		return 0
	fi
	case "$os" in
		# windows|wsl)
			# download_release sharkdp/bat "x86_64-pc-windows-gnu.zip" || { log.fatal Failed; return 1 ; } ;;
		# centos)
			# fetchfile https://copr-be.cloud.fedoraproject.org/results/carlwgeorge/ripgrep/epel-7-x86_64/01858399-ripgrep/ripgrep-12.1.1-1.el7.x86_64.rpm ;;
			
		ubuntu)
			local cmds=(
				'download_release BurntSushi/ripgrep ".*amd64.deb"'
				'sudo apt install ./ripgrep_*'
				'rm ripgrep*.deb'
			)
			runcmds "${cmds[@]}"
			return $? ;;
		*)
			log.fatal "dunno how to download ripgrep for os: $os"
			return 1 ;;

	esac

	# sudo chmod +x ripgrep*.deb
	# sudo apt install ./ripgrep*.deb


}
function install_fdfind() {
	log.megatitle "install_fdfind($*)" -x
	if isdefined fd && ! confirm "fdfind seems to be installed; continue with installation anyway?"; then
		log.info "Returning 0"
		return 0
	fi
	case "$os" in
		windows)
			download_release sharkdp/fd "x86_64-pc-windows-gnu.zip"  || { log.fatal Failed; return 1 ; } ;;
		centos|alpine)
			runcmds ---log-only-errors \
				'download_release sharkdp/fd "x86_64-unknown-linux-gnu.tar.gz" -o fd.tar.gz' \
				'tar -xvf fd.tar.gz' \
				'mv fd-*x86_64-unknown-linux-gnu/fd /usr/bin/' \
				'rm -rf fd-*x86_64-unknown-linux-gnu'
			return $? ;;
		ubuntu|wsl)
			local cmds=(
				'download_release sharkdp/fd "fd_.*amd64.deb"'
				'sudo apt install ./fd_*'
				'rm fd_*.deb'
			)
			runcmds "${cmds[@]}"
			return $? ;;
		*)
			log.fatal "dunno how to download fd for os: $os"
			return 1 ;;

	esac


}

function install_xvkbd() {
	log.megatitle "install_xvkbd($*)" -x
	# http://t-sato.in.coocan.jp/xvkbd/#download
	# http://t-sato.in.coocan.jp/xvkbd/xvkbd-4.1.tar.gz
	if isdefined xvkbd && ! confirm "xvkbd seems to be installed; continue with installation anyway?"; then
		log.info "Returning 0"
		return 0
	fi
	local cmds=(
		"sudo apt install pkg-config libxaw7 libxaw7-dev libxtst-dev make"
		"builtin cd ~/.local/share"
		"fetchfile http://t-sato.in.coocan.jp/xvkbd/xvkbd-4.1.tar.gz"
		"tar -xvf xvkbd-4.1.tar.gz"
		"builtin cd xvkbd-4.1"
		"./configure"
		# "sudo make"
		"make"
		"sudo make install"
	)
	runcmds "${cmds[@]}"
	return $?
}

function install_sxhkd() {
	log.megatitle "install_sxhkd($*)" -x
	# https://github.com/baskerville/sxhkd/issues/251#issuecomment-1004353758
	if isdefined sxhkd && ! confirm "sxhkd seems to be installed; continue with installation anyway?"; then
		log.info "Returning 0"
		return 0
	fi
	log.info "Remember to install xdotool and wmctrl afterwards!"
	local cmds=(
		"sudo apt install libxcb-util-dev libxcb-keysyms1-dev libc6 libxcb-keysyms1 libxcb1 make"
		"builtin cd ~/.local/share"
		"git clone https://github.com/baskerville/sxhkd"
		"builtin cd sxhkd"
		"make"
		"sudo make install"
	)
	runcmds "${cmds[@]}"
	return $?
}

function install_lazydocker() {
	log.megatitle "install_lazydocker($*)" -x
	if isdefined lazydocker && ! confirm "lazydocker seems to be installed; continue with installation anyway?"; then
		log.info "Returning 0"
		return 0
	fi
	local cmds=(
		'fetchfile https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh lazydocker_install.sh'
		'chmod +x ./lazydocker_install.sh'
		'$SHELL ./lazydocker_install.sh'
		'rm ./lazydocker_install.sh'
		'sudo mv ./lazydocker /usr/local/bin'
	)
	runcmds "${cmds[@]}"
	return $?
}

function install_nvm(){
	log.megatitle "install_nvm($*)" -x
	if isdefined nvm && ! confirm "nvm seems to be installed; continue with installation anyway?"; then
		log.info "Returning 0"
		return 0
	fi
	runcmds \
		'local nvm_latest_version="$(get_latest_version nvm-sh/nvm)"' \
		'fetchfile https://raw.githubusercontent.com/nvm-sh/nvm/"$nvm_latest_version"/install.sh nvm_install.sh' \
		'$SHELL nvm_install.sh' \
		'rm nvm_install.sh' || return 1
	log.info "Remember to remove the export NVM_DIR from ~/.zshrc. You can do it via ${Cc}sed -i '/export NVM_DIR/,+3d' ~/.zshrc" -x
	return 0
}

function install_flameshot(){
	log.megatitle "install_flameshot($*)" -x
	if isdefined flameshot; then
		if [[ "$1" != -y ]] && ! confirm "flameshot seems to be installed; continue with installation anyway?"; then
			log.info "Returning 0"
			return 0
		fi
	else
		# ok if already installed
		if ! vex sudo snap install flameshot; then log.fatal Failed installing; return 1; fi
	fi

	local flameshot_exec
	if ! flameshot_exec="$(which flameshot | head -1)"; then
		log.error "Flameshot installed but exec path not found"
		return 2
	fi

	if ! pgrep flameshot; then
		sleep 1s
		(nohup "$flameshot_exec" &) &>/dev/null
		sleep 2s
		if ! pgrep flameshot; then
			log.error "Failed running $flameshot_exec"
			return 2
		fi
	fi
	"$flameshot_exec" config --autostart true
	pkill flameshot
	local flameshot_config="$HOME/snap/flameshot/current/.config/flameshot/flameshot.ini"
	if [[ ! -f "$flameshot_config" ]]; then
		log.megawarn "Flameshot config is not found at $flameshot_config\n" \
		"It is recommended to config flameshot to launch at startup, and disable welcome / help notifications"
		return 2
	fi

	log.debug "flameshot_config: ${flameshot_config}"

	local config_rest
	runcmds ---log-only-errors \
		'declare -i general_section_start_linenum' \
		'declare -i general_section_end_linenum' \
		'general_section_start_linenum="$(grep --line-number --only-matching --max-count 1 General "$flameshot_config" | cut -d : -f 1)"' \
		'general_section_end_linenum="$(tail +"${general_section_start_linenum}" "$flameshot_config" | grep -P --line-number --max-count 1 "^$" | cut -d : -f 1)"' \
		'((general_section_end_linenum+=general_section_start_linenum))' \
		'config_rest="$(tail +"$general_section_end_linenum" "$flameshot_config")"' \
		|| return $?


	echo "[General]" > "$flameshot_config"
	local config=(
		"copyPathAfterSave=true"
		"disabledTrayIcon=false"
		"drawColor=#ff0000"
		"drawFontSize=18"
		"drawThickness=2"
		"savePath=$HOME/Pictures"
		"savePathFixed=true"
		"setSaveAsFileExtension="
		"showDesktopNotification=false"
		"showHelp=false"
		"showStartupLaunchMessage=false"
		"startupLaunch=true\n"
	 )
	local line
	for line in "${config[@]}" ${config_rest[@]}; do echo "$line" >> "$flameshot_config"; done
	log.success "Installed and configured flameshot successfully"
	return $?
}

function install_jetbrains_toolbox() {
	log.megatitle "install_jetbrains_toolbox($*)" -x
	# https://download.jetbrains.com/toolbox/jetbrains-toolbox-1.20.7940.tar.gz
	:
}

# # install_zsh [-y]
function install_zsh() {
	log.megatitle "install_zsh($*)" -x
	# .zshrc: https://gist.github.com/giladbarnea/00080883c19e55a38f4a5e5086fed2aa

	local interactive=true
	local interactive_flag=
	if [[ "$1" == -y || ! -t 0 || ! -t 1 ]]; then
		interactive=false
		interactive_flag=-y
	fi
	# --[ Install ]--

	if [[ ! $ZSH_VERSION ]]; then
		case "$os" in
			ubuntu|wsl)
				sudo apt install zsh "$interactive_flag" ;;
			centos)
				# zsh 5.6.2: https://gist.github.com/Semo/378fba2516a31f2608f0ad0161a73ab7
				yum install zsh "$interactive_flag" ;;
			alpine)
				apk add zsh "$interactive_flag" ;;
			windows)
				if isdefined pacman; then
					pacman -S zsh || return 1
				else
					log.warn "install zsh from here: https://packages.msys2.org/package/zsh?repo=msys&variant=x86_64 and tips from https://gist.github.com/fworks/af4c896c9de47d827d4caa6fd7154b6b"
					return 1
				fi ;;
			*)
				log.warn "Not implemented for os = $os"
				return 2 ;;
		esac
	fi

	local cmds=()
	if [[ ! "$ZSH" && ! -e "${ZSH:-"$HOME"/.oh-my-zsh}" ]]; then
		if ! $interactive || confirm "Download zsh_install.sh and run it?"; then
			# TODO: requires git!
			cmds=(
				'builtin cd /tmp'
				'[[ -e zsh_install.sh ]] || fetchfile https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh zsh_install.sh'
				'[[ ! -e ~/.zshrc ]] || mv -v ~/.zshrc ~/.zshrc.backup'
				'[[ ! -e ~/.p10k.zsh ]] || mv -v ~/.p10k.zsh ~/.p10k.zsh.backup'
				# "sed -i 's/RUNZSH:-yes/RUNZSH:-no/g' ./zsh_install.sh"
				# sed -i 's/KEEP_ZSHRC:-no/KEEP_ZSHRC:-yes/g' ./zsh_install.sh
				# 'sudo chmod 777 ./zsh_install.sh'
				'$SHELL ./zsh_install.sh'
			)
			if ! runcmds "${cmds[@]}"; then
				log.fatal "Failed"
				return 1
			fi
		fi
	fi


	# [ ! -e ~/.p10k.gist.zsh ] && vex fetchfile https://gist.github.com/giladbarnea/60e9cf6709a6bd02df6bb61a1b15900a/raw ~/.p10k.gist.zsh

	# # This shouldn't happen
	# if [[ "${SHELL##*/}" != zsh ]] && false; then
	#   sudo chmod 777 ~/.zshrc
	#   if [[ -e "$HOME/.bashrc" ]]; then
	#     sudo chmod 777 "$HOME/.bashrc"
	#   elif [[ -e "$HOME/.bash_profile" ]]; then
	#     sudo chmod 777 "$HOME/.bash_profile"
	#   fi
	#   # might need to chmod ~/.oh-my-zsh repo
	#   #chsh -s /data/data/com.termux/files/usr/bin/zsh
	#   # or (sudo?) chsh -s "$(which zsh)"
	# fi

	import standalone/omz-post-install.sh
	# zsh-newuser-install
	return $?
}

function install_brave(){
	log.megatitle "install_brave($*)" -x
	if [[ "$1" != -y ]] && isdefined brave-browser && ! confirm "Brave seems to be installed; continue with installation anyway?"; then
		log.info "Returning 0"
		return 0
	fi
	local cmds=(
		'sudo apt install apt-transport-https curl -y'
		'sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg'
		'echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg arch=amd64] https://brave-browser-apt-release.s3.brave.com/ stable main"|sudo tee /etc/apt/sources.list.d/brave-browser-release.list'
		'sudo apt update'
		'sudo apt install brave-browser -y'
	)
	runcmds "${cmds[@]}" && log.success "Installed brave successfully"
	return $?
}

function install_chrome() {
	log.megatitle "install_chrome($*)" -x
	if [[ "$1" != -y ]] && isdefined google-chrome && ! confirm "Chrome seems to be installed; continue with installation anyway?"; then
		log.info "Returning 0"
		return 0
	fi
	local cmds=(
		"wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb --no-check-certificate"
		"sudo apt install ./google-chrome-stable_current_amd64.deb -y"
		"rm ./google-chrome-stable_current_amd64.deb"
	)
	runcmds "${cmds[@]}" && log.success "Installed chrome successfully"
	return $?
}

# ------[ Optional ]--------

function install_delta() {
	log.megatitle "install_delta($*)" -x
	# https://github.com/dandavison/delta
	# needs libgcc
	# curl -sLO "http://ftp.fr.debian.org/debian/pool/main/g/gcc-10/gcc-10-base_10.2.1-6_amd64.deb" && sudo dpkg -i ./gcc-10-base_10.2.1-6_amd64.deb
	# curl -sLO "http://ftp.fr.debian.org/debian/pool/main/g/gcc-10/libgcc-s1_10.2.1-6_amd64.deb" && sudo dpkg -i ./libgcc-s1_10.2.1-6_amd64.deb
	# https://github.com/dandavison/delta/releases
	runcmds \
		'mkdir -p ~/.local/bin' \
		'builtin cd ~/.local/bin' \
		|| return $?

	case "$os" in
		ubuntu|wsl)
			download_release dandavison/delta 'x86_64.*linux.*gnu' ;;
		*)
			log.warn "Not implemented for os = $os"
			return 2 ;;
	esac

	if runcmds ---log-only-errors \
		'declare -g tar_file="$(find . -maxdepth 1 -type f -name "delta*")"' \
		'tar -xvf "$tar_file"' \
		'mv ./${tar_file%.tar.gz}/delta .' \
		'rm -rf ./${tar_file%.tar.gz} $tar_file' \
		'unset tar_file'
	then
		log.success "Installed delta to $PWD/delta"
		return 0
	else
		log.fatal "Errored during delta installation"
		return 1
	fi


}
function install_kitty(){
	log.megatitle "install_kitty($*)" -x
	local cmds=(
		'[ -e $HOME/.local/kitty.app ] || curl -L https://sw.kovidgoyal.net/kitty/installer.sh | $SHELL /dev/stdin'
		'[ -e $HOME/.local/share/applications/kitty.desktop ] || cp -v $HOME/.local/kitty.app/share/applications/kitty.desktop  $HOME/.local/share/applications'
	)
	if ! runcmds "${cmds[@]}"; then return 1; fi
	local kitty_conf
	if kitty_conf="$(find $HOME/.local/kitty.app/share/doc/kitty/html/_downloads -type f -name kitty.conf)"; then
		confirm "Copy $kitty_conf to ~/.config/kitty?" && cp "$kitty_conf" "$HOME/.config/kitty"
	else
		log.warn "Didn't find kitty.conf in $HOME/.local/kitty.app/share/doc/kitty/html/_downloads"
	fi
	if [ -e /usr/local/bin/kitty ]; then
		sed -i "s/Exec=kitty/Exec=\/usr\/local\/bin\/kitty/g" $HOME/.local/share/applications/kitty.desktop
	elif [ -e $HOME/.local/kitty.app/bin/kitty ]; then
		sed -i "s/Exec=kitty/Exec=${HOME////\\/}\/.local\/kitty.app\/bin\/kitty/g" $HOME/.local/share/applications/kitty.desktop
	else
		log.warn "Didnt find kitty bin so didn't sed Exec in $HOME/.local/share/applications/kitty.desktop"
	fi
	sed -i "s/Icon=kitty/Icon=${HOME////\\/}\/.local\/kitty.app\/share\/icons\/hicolor\/256x256\/apps\/kitty.png/g" $HOME/.local/share/applications/kitty.desktop
	# sed -i "s/# copy_on_select no/copy_on_select yes/g" ~/.config/kitty/kitty.conf
	# sed -i "s/# strip_trailing_spaces never/strip_trailing_spaces smart/g" ~/.config/kitty/kitty.conf
	# sed -i "s/# enable_audio_bell yes/enable_audio_bell no/g" ~/.config/kitty/kitty.conf
	# sed -i "s/# editor ./editor micro/g" ~/.config/kitty/kitty.conf
	# sed -i "s/# map kitty_mod+v paste_from_clipboard/map ctrl+v paste_from_clipboard/g" ~/.config/kitty/kitty.conf
	# sed -i "s/# map kitty_mod+w close_window/map kitty_mod+TAB previous_window\nmap ctrl+TAB next_window\n# map kitty_mod+w close_window/g" ~/.config/kitty/kitty.conf
	if ! confirm "Download kitty.conf gist into ~/.config/kitty/kitty.conf?"; then return 3; fi
	fetchfile https://gist.github.com/giladbarnea/ecc92a37256378c6dc86166a3463775e/raw ~/.config/kitty/kitty.conf
	return $?
}

function install_copyq(){
	log.megatitle "install_copyq($*)" -x
	if isdefined copyq; then
		if [[ "$1" != -y ]] && ! confirm "copyq seems to be installed; continue with installation anyway?"; then
			log.info "Returning 0"
			return 0
		fi
	elif ! vex sudo apt install copyq; then
		log.fatal "Failed installing copyq"
		return 1
	fi

	log.notice "Modifying copyq configuration..."

	if ! runcmds ---log-only-errors \
		'(nohup copyq &) &>/dev/null' \
		'sleep 0.5s' \
		'if ! pgrep copyq &>/dev/null; then sleep 1s; fi' \
		'pkill copyq'
	then
		log.warn Failed
		return 2
	fi

	local cmd_index
	if ! cmd_index="$(grep -Po "(?<=size=)\d+" "$HOME/.config/copyq/copyq-commands.ini")"; then
		log.warn Failed getting size= from copyq-commands.ini
		return 0
	fi

	if ! runcmds ---log-only-errors \
		'cp "$HOME/.config/copyq/copyq-commands.ini" "$HOME/.config/copyq/copyq-commands.ini~"' \
		'sed -i "/size=/d" "$HOME/.config/copyq/copyq-commands.ini"'
	then
		log.warn Failed modifying copyq-commands.ini
		return 0
	fi
	cmd_index=$((cmd_index+1))

	if ! cat <<-EOF >> "$HOME/.config/copyq/copyq-commands.ini"
		$cmd_index\Command=copyq: menu()
		$cmd_index\Icon=\xf01c
		$cmd_index\IsGlobalShortcut=true
		$cmd_index\Name=Show the tray menu
		$((cmd_index+1))\Command=copyq: toggle()
		$((cmd_index+1))\GlobalShortcut=ctrl+shift+v
		$((cmd_index+1))\Icon=\xf022
		$((cmd_index+1))\IsGlobalShortcut=true
		$((cmd_index+1))\Name=Show/hide main window
		$((cmd_index+2))\Command="copyq: \nvar text = clipboard()\ncopy(text)\ncopySelection(text)\npaste()"
		$((cmd_index+2))\GlobalShortcut=meta+ctrl+alt+shift+v
		$((cmd_index+2))\Icon=\xf0ea
		$((cmd_index+2))\IsGlobalShortcut=true
		$((cmd_index+2))\Name=Paste clipboard as plain text
EOF
	then
		log.warn Failed modifying copyq-commands.ini
		return 0
	fi
	if ! runcmds ---log-only-errors \
		'echo "size=$((cmd_index+2))" >> "$HOME/.config/copyq/copyq-commands.ini"' \
		'copyq config autostart true' \
		'copyq config save_filter_history true' \
		'copyq config run_selection false'
	then
		log.warn Failed modifying copyq-commands.ini
	fi

	return 0
}

function install_bottom(){
	log.megatitle "install_bottom($*)" -x
	if isdefined bottom; then
		if [[ "$1" != -y ]] && ! confirm "bottom seems to be installed; continue with installation anyway?"; then
			log.info "Returning 0"
			return 0
		fi
	fi
	runcmds \
		'builtin cd /tmp' \
		'download_release ClementTsang/bottom _amd64.deb -o bottom.deb' \
		'sudo apt install ./bottom.deb' || return 1

	log.success "bottom (${Cc}btm${Cc0}) installed successfully"

	runcmds \
		'download_release ClementTsang/bottom completions' \
		'tar -xf ./completions.tar.gz' || return 1

	if [[ "${SHELL##*/}" = zsh && "$ZSH" ]]; then
		if ! runcmds ---log-only-errors \
			'mkdir "$ZSH_CUSTOM/plugins/btm"' \
			'mv ./completions/_btm "$ZSH_CUSTOM/plugins/btm"'
		then
			log.warn "Failed installing btm completions"
		else
			log.success "Installed btm completions into $ZSH_CUSTOM/plugins/btm. Add ${Cc}btm${Cc0} to plugins array in .zshrc."
		fi
	else
		log.notice "Shell completions are available at $PWD/completions"
	fi
	return 0

}

function get_pip() {
	if [[ -z "$1" ]]; then
		log.fatal "[get_pip()] no args, expecting 1 (python executable)"
		return 1
	fi
	if [[ ! -x "$1" ]]; then
		log.fatal "[get_pip()] not executable: $1"
		return 1
	fi
	local pyexec="$1"
	shift
	local cmds=(
		'fetchfile https://bootstrap.pypa.io/get-pip.py get-pip.py'
		'chmod +x ./get-pip.py'
		'"$pyexec" ./get-pip.py'
		'"$pyexec" -m pip install -U pip'
		'"$pyexec" -m pip install -U setuptools wheel virtualenv'
	)
	runcmds "${cmds[@]}"
	return $?

}

# # install_python <MAJOR.MINOR[.MICRO]> [-y]
# Example: install_python 3.9
# Example: install_python 3.7.10 -y
function install_python() {
	function _python_exec_path(){
		local _pyver="$1"
		local _maj_dot_min="$(echo "$_pyver" | cut -d . -f 1-2)"
		local _py_exec_paths
		if _py_exec_paths=( "$(which "python${_maj_dot_min}")" ); then
			for _py_exec_path in "${_py_exec_paths[@]}"; do
				if [[ "$("$_py_exec_path" -V | cut -d ' ' -f 2)" == "$_pyver" ]]; then
					echo -n "$_py_exec_path"
					return 0
				fi
			done
		fi
		return 1
	}

	log.megatitle "install_python($*)" -x
	local pyver="$1"
	local dot_count
	if ! dot_count="$(echo "$pyver" | grep -oF . | wc -l)"; then
		log.fatal "Bad version; Expecting format: MAJOR.MINOR or MAJOR.MINOR.MICRO | Example: install_python 3.9"
		return 1
	fi

	# e.g `install_python 3.9` -> get latest micro version
	if [[ $dot_count == 1 ]]; then
		local minor="${pyver#*.}"
		log.debug "minor: $minor"
		local micro
		if ! micro="$(wget -O- 'https://www.python.org/downloads/' --quiet --no-check-certificate | grep -Po "(?<=Python )3\.$minor\.[0-9]+" | sort -rV | head -1 | cut -d . -f 3)"; then
			log.warn "Failed getting latest 3.$minor.? from www.python.org."
			micro="$(input 'Specify micro version manually (e.g for Python 3.9.7, input 7)')"
		fi
		log.debug "micro: $micro"
		pyver="${pyver}.$micro"
		log.debug "micro: $micro | pyver: $pyver"
	elif [[ $dot_count != 2 ]]; then
		log.fatal "Bad version; Expecting format: MAJOR.MINOR or MAJOR.MINOR.MICRO | Example: install_python 3.9"
		return 1
	fi

	# Return if exact version is already installed
	local py_exec_path
	if py_exec_path="$(_python_exec_path "$pyver")"; then
		log.success "Python $pyver is already installed at $py_exec_path"
		return 0
	fi

	declare -a cmds=(
		'sudo apt update'
		'sudo apt upgrade'
		'sudo apt-get install libreadline-gplv2-dev libncursesw5-dev libssl-dev libsqlite3-dev tk-dev libgdbm-dev libc6-dev libbz2-dev libffi-dev zlib1g-dev wget build-essential checkinstall tar -y'
		'sudo mkdir -pv $HOME/bin'
		'builtin cd $HOME/bin'
		'sudo chmod 777 -R .'
		"[ -f Python-$pyver.tgz ] || fetchfile https://www.python.org/ftp/python/$pyver/Python-$pyver.tgz"
		"[ -d Python-$pyver ] || sudo tar -xvzf Python-$pyver.tgz"
		"builtin cd Python-$pyver"
	)


	local exitcode
	runcmds "${cmds[@]}"
	exitcode=$?
	if [[ "$exitcode" != 0 ]]; then
		return $exitcode
	fi
	if [[ "$2" != -y ]] && ! confirm "Python $pyver source files downloaded. Install?"; then
		return 3
	fi

	cmds=(
		'sudo ./configure --enable-optimizations'
		'sudo make altinstall'
	)
	runcmds "${cmds[@]}"
	exitcode=$?
	if [[ "$exitcode" == 0 ]]; then
		if py_exec_path="$(_python_exec_path "$pyver")"; then
			log.success "Python $pyver was successfully installed at ${py_exec_path}."
			vex "$py_exec_path" -m pip install -U pip setuptools wheel virtualenv requests
			return 0
		fi
		log.warn "Failed checking for successful installation of Python $pyver, make sure it was installed properly"
	else
		log.fatal "Failed installing python from source ($PWD)"
	fi
	return $exitcode
}

function install_fprint(){
	log.megatitle "install_fprint($*)" -x
	if isdefined fprintd-enroll; then
		if [[ "$1" != -y ]] && ! confirm "fprintd-enroll seems to be installed; continue with installation anyway?"; then
			log.info "Returning 0"
			return 0
		fi
	fi
	sudo apt install libpam-fprintd || return 1
	runcmds ---confirm-each \
		'sudo pam-auth-update' \
		'fprintd-enroll'
}

function install_mdcat() {
	log.megatitle "install_mdcat($*)" -x
	# https://github.com/lunaryorn/mdcat/releases/tag/mdcat-0.22.3
	:
}
function install_notion_nativefier(){
	log.megatitle "install_notion_nativefier($*)" -x
	# icon: https://github.com/nativefier/nativefier-icons/tree/gh-pages/files
	#       https://cdn.worldvectorlogo.com/logos/notion-logo-1.svg (curl -O it first, also nativefier needs imagemagick to convert to png)
	# imagemagick: apt install imagemagick, and curl -O https://download.imagemagick.org/ImageMagick/download/binaries/magick
	# --background-color '3C3F41' --basic-auth-password '...' --basic-auth-username giladbrn@gmail.com [--tray] (not sure if auth does something)
	if ! isdefined nativefier; then
		log.warn "nativefier is not defined"
		if isdefined nvm; then
			log.error "${Cc}nvm${Cc0} is defined, but looks like ${Cc}nativefier${Cc0} is not installed. Install ${Cc}nativefier${Cc0} and try again."
			return 1
		fi
		# nvm is not defined
		if ! isdefined loadnvm; then
			log.error "${Cc}loadnvm${Cc0} is not defined, and ${Cc}nvm${Cc0} is not defined. Install ${Cc}nativefier${Cc0} and try again."
			return 1
		fi
		if ! confirm "Run ${Cc}loadnvm${Cc0}?"; then
			return 1
		fi
		log.info "Loading nvm"
		loadnvm
		install_notion_nativefier "$@"
		return $?
	fi
	local install_dir
	local oldpwd="$PWD"
	if [[ "$PWD" != "$HOME"/.local* ]] &&
			\ confirm "You're currently in $PWD; Install nativefier in $HOME/.local/notion-linux-x64?"; then
		builtin cd "$HOME/.local"
	fi
	install_dir="$PWD/notion-linux-x64"
	if ! nativefier -p linux --portable --name notion -u 'Mozilla/5.0 (X11; Linux i686; rv:98.0) Gecko/20100101 Firefox/98.0' --disable-old-build-warning-yesiknowitisinsecure --ignore-certificate --insecure --single-instance "$@" https://notion.so; then
		log.fatal "Failed installing notion"
		return 1
	fi
	log.success "Successfully installed notion"
	# shellcheck disable=SC2038
	local icon_filename="$(find "$install_dir/resources/app" -maxdepth 1 -mindepth 1 -name 'icon*' | xargs basename)"
	local notion_desktop_content=$(cat <<-EOF
	[Desktop Entry]
	Version=1.0
	Type=Application
	Name=Notion
	GenericName=Notion
	TryExec=$install_dir/notion
	Exec=$install_dir/notion
	Icon=$install_dir/resources/app/$icon_filename
	Categories=Notes;Productivity;
EOF
	)
	local notion_desktop_path="$HOME/.local/share/applications/notion.desktop"
	if [[ -e "$notion_desktop_path" ]]; then
		if ! echo -n "$notion_desktop_content" | diff -wiEbBIZq "$notion_desktop_path" -; then
			log.success "$notion_desktop_path already exists and has the correct content"
			return 0
		fi
		confirm "$notion_desktop_path content is different than what's required. Overwrite $notion_desktop_path?" || return 0
	else
		confirm "$notion_desktop_path does not exist, write one?" || return 0
	fi
	echo "$notion_desktop_content" > "$notion_desktop_path"
	bat "$notion_desktop_path"
	return 0
}

function install_notion_enhanced() {
	# JUST apt install notion-app-enhanced
	:
	# log.megatitle "install_notion_enhanced($*)" -x
	# mkdir -pv ~/.local/bin || return 1
	# builtin cd ~/.local/bin || return 1
	# local cmds=()
	# case "$os" in
	#   windows|wsl)
	#     cmds+=('download_release notion-enhancer/notion-repackaged ".exe$"')
	#     ;;
	#   centos)
	#     cmds+=('download_release notion-enhancer/notion-repackaged "enhanced.*rpm"')
	#     ;;
	#   ubuntu)
	#     cmds+=(
	#       "download_release notion-enhancer/notion-repackaged 'Enhanced.*AppImage'"
	#       'appimg="$(find . -maxdepth 1 -type f -regex ".*AppImage")"'
	#       'sudo chmod 777 "$appimg"'
	#       'mv "$appimg" ~/.local/bin'
	#       'fetchfile https://github.com/notion-enhancer/notion-enhancer/blob/dev/mods/core/icons/mac+linux.png ~/.local/bin/notion-enhanced.png'
	#       'echo "[Desktop Entry]" >> $HOME/.local/share/applications/notion.desktop'
	#       'echo "Name=Notion" >> $HOME/.local/share/applications/notion.desktop'
	#       'echo "Icon=$HOME/.local/bin/notion-enhanced.png" >> $HOME/.local/share/applications/notion.desktop'
	#       'echo "StartupWMClass=notion" >> $HOME/.local/share/applications/notion.desktop'
	#       'echo "Exec=$appimg %u" >> $HOME/.local/share/applications/notion.desktop'
	#       'echo "Type=Application" >> $HOME/.local/share/applications/notion.desktop'
	#       'rm "$appimg"'
	#     )
	#     ;;
	#   *)
	#     log.fatal "dunno how to download notion enhanced for os: $os"
	#     return 1
	#     ;;

	# esac

	# runcmds "${cmds[@]}"
	# return $?
}


function restore_pycharm_settings(){
	# Proofreading
	# ShellCheck
	# File Associations
	# Live Templates
	:
}
# gsettings list-schemas | sort | while read -r line; do log.megatitle $line -x; gsettings list-keys $line | sort; done -x

function gext.install(){
	local oldpwd="$(pwd)"
	builtin cd ~/.local/share/gnome-shell/extensions || return 1
	local zipfile="$1"
	if [[ ! -e "$zipfile" ]]; then
		fetchfile https://extensions.gnome.org/extension-data/"$zipfile" || return 1
	fi
	local ext_uuid="$(unzip -c "$zipfile" metadata.json | grep uuid | cut -d '"' -f4)"
	log.debug "ext_uuid: ${ext_uuid}"
	if [[ -z "$ext_uuid" ]]; then
		log.fatal "Failed getting extension uuid"
		return 1
	fi
	mkdir -pv "$ext_uuid" || return 1
	unzip -q "$zipfile" -d "$ext_uuid"/ || return 1
	local exitcode

	# Not sure this is needed!
	vex gnome-extensions enable "$ext_uuid"
	exitcode=$?

	if [[ "$exitcode" == 0 ]]; then
		rm ./"$zipfile"
		log.success "${zipfile%.shell-extension.zip} will be activated after next log in"
	fi
	builtin cd "$oldpwd"
	return $exitcode
}

# switcher@landau.fi
function gext.switcher() {
	gext.install switcherlandau.fi.v33.shell-extension.zip
	return $?
}

# remove-alt-tab-delay@daase.net
function gext.remove_alt_tab() {
	# https://extensions.gnome.org/extension/2741/remove-alttab-delay-v2/
	gext.install remove-alt-tab-delaydaase.net.v5.shell-extension.zip
	return $?
}

# noannoyance@daase.net
function gext.no_annoyance() {
	# https://extensions.gnome.org/extension/2182/noannoyance/
	:
}

function gext.night_light_slider(){
	gext.install night-light-slider.timurlinux.com.v22.shell-extension.zip
	return $?
}

function gext.hide_top_bar(){
	# create hidetopbar@mathieu.bidon.ca in ~/.local/share/gnome-shell/extensions/
	gext.install hidetopbarmathieu.bidon.ca.v99.shell-extension.zip
	return $?
}

# disconnect-wifi@kgshank.net
function gext.disconnect_wifi(){
	:
}

function system_tweaks(){
	:
	# /etc/bluetooth/input.conf:
	#   IdleTimeout=30 -> IdleTimeout=120
}

function install_doublecmd() {
	log.megatitle "install_doublecmd($*)" -x
	# https://sourceforge.net/projects/doublecmd/files/DC%20for%20Linux%2064%20bit/Double%20Commander%200.9.10%20beta/doublecmd-0.9.10.qt5.x86_64.tar.xz/download
	echo 'deb http://download.opensuse.org/repositories/home:/Alexx2000/xUbuntu_18.04/ /' | sudo tee /etc/apt/sources.list.d/home:Alexx2000.list
	curl -fsSL https://download.opensuse.org/repositories/home:Alexx2000/xUbuntu_18.04/Release.key | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/home_Alexx2000.gpg >/dev/null
	sudo apt update
	sudo apt install doublecmd-qt5

	# might need to modify doublecmd.sh:
	# ####
	# #!/usr/bin/env bash
	# cd /home/gilad/.local/share/doublecmd
	# export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$(pwd)
	# ./doublecmd
	# ####
	# ln -srvL -T /home/gilad/.local/share/doublecmd/doublecmd.sh /home/gilad/.local/bin/doublecmd

}
function install_bash5() {
	log.megatitle "install_bash5($*)" -x
	local cmds=(
		'mkdir -pv ~/.local/bin'
		'builtin cd ~/.local/bin'
		'fetchfile https://ftp.gnu.org/gnu/bash/bash-5.1.tar.gz'
		'tar xvf bash-5.1.tar.gz'
		'builtin cd bash-5.1'
		'sudo ./configure'
		'sudo make'
		'sudo make install'
	)
	runcmds "${cmds[@]}"
	return $?
}
function install_git_sdk() {
	log.megatitle "install_git_sdk($*)" -x
	# https://github.com/git-for-windows/git-sdk-64
	:
}
function install_git_lfs() {
	log.megatitle "install_git_lfs($*)" -x
	curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh | sudo bash
	# apti git-lfs?

}
function install_gitkraken_504() {
	log.megatitle "install_gitkraken_504($*)" -x
	# mac:
	# https://release.axocdn.com/darwin/GitKraken-v5.0.4.zip
	# linux:
	# https://release.gitkraken.com/linux/gitkraken-amd64.deb
	# win:
	:
}
function install_git_fuzzy() {
	log.megatitle "install_git_fuzzy($*)" -x
	# https://github.com/giladbarnea/git-fuzzy
	builtin cd ~/.local/share || return 1
	git clone https://github.com/bigH/git-fuzzy.git # or giladbarnea/git-fuzzy
	# then add /home/vagrant/.local/share/git-fuzzy/bin to PATH
}
function install_lazygit() {
	log.megatitle "install_lazygit($*)" -x
	sudo add-apt-repository ppa:lazygit-team/release || return 1
	sudo apt-get update || return 1
	sudo apt-get install lazygit || return 1
	return 0
}
function install_fasd() {
	log.megatitle "install_fasd($*)" -x
	if [[ "$iswindows" ]]; then
		mkcdir ~/.local/share || return 1
		git clone https://github.com/clarity20/fasder || return 1
		cd fasder || return 1
		PREFIX=$HOME make install || return 1
	else
		sudo apt install fasd || return 1
	fi
}
}
