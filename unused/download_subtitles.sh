# # dlsub
# 	dlsub [-m,--movieid <movieid>] [-s,--subtitleid <subtitleid>] [-l,--lang <lang=eng>] [-q,--quiet] <NAME>
# ```bash
# source $SCRIPTS/standalone/dlsub.sh [-q]
# source $SCRIPTS/standalone/dlsub.sh [-q] 'Game of Thrones S04E04 Oathkeeper.mp4'
# source $SCRIPTS/standalone/dlsub.sh [-q] -l heb 'House of Cards S02E01'
# source $SCRIPTS/standalone/dlsub.sh [-q] -s, --subid <SUBTITLE_ID[,SUBTITLE_ID,...]>
# source $SCRIPTS/standalone/dlsub.sh [-q] -m, --movieid <MOVIE_ID[,MOVIE_ID,...]>
# source $SCRIPTS/standalone/dlsub.sh -s 8587940,8587941,8587942,8587943
# while read -r episode; do dlsub "$episode" &; done <<< $(command ls)
# ```
function dlsub(){
  set -o pipefail # -o errexit
  { ! type isdefined \
    && source <(wget -qO- https://raw.githubusercontent.com/giladbarnea/land/master/{util,log}.sh --no-check-certificate) ;
  } &>/dev/null
  log.title "dlsub $*"
  local name movieid subid url lang=eng
  local quiet=false
  local base_wget_args=(--no-check-certificate)
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        isdefined docstring \
        	&& docstring -p "$0" \
        	|| printf "dlsub [-m,--movieid <movieid>] [-s,--subtitleid <subtitleid>] [-l,--lang <lang=eng>] [-q,--quiet] <NAME>\n"
        return 0 ;;
      -m|--movieid) movieid="$2"; shift 2;;
      -l|--lang) lang="$2"; shift 2;;
      -s|--subid) subid="$2"; shift 2;;
      -q|--quiet) quiet=true; shift;;
      *) name="${1%.*}"; shift;;
    esac
  done
  if $quiet && [[ ! "$name" && ! "$movieid" && ! "$subid" ]]; then
    log.fatal "if ${Cc}-q${Cc0}, must specify -s, -m, positional name"
    return 1
  fi
  ## Check for batch
  if [[ "$movieid" && "$movieid" = *,* ]]; then
    local mid
    local dlsub_args=()
    "$quiet" && dlsub_args+=(-q)
    # shellcheck disable=SC2086,SC2116
    for mid in $(echo ${movieid//,/ }); do
      dlsub -m "$mid" "${dlsub_args[@]}" &
    done
    return
  fi
  if [[ "$subid" && "$subid" = *,* ]]; then
    local sid
    local dlsub_args=()
    "$quiet" && dlsub_args+=(-q)
    # shellcheck disable=SC2086,SC2116
    for sid in $(echo ${subid//,/ }); do
      dlsub -s "$sid" "${dlsub_args[@]}" &
    done
    return
  fi
  ## Single mode
  if $quiet; then
    base_wget_args+=(--quiet -o /dev/null)
  else
    base_wget_args+=(--no-verbose)
  fi
  if [[ ! "$name" ]] && ! "$quiet"; then
    ls
    name="$(input "Enter movie / episode name: ")"
    name="${name%.*}"
  fi
  log.debug "name: ${name} | quiet: ${quiet}"
  if [[ ! "$subid" ]]; then
    if [[ ! "$movieid" ]]; then
      url="https://www.opensubtitles.org/en/search2/sublanguageid-${lang}/moviename-${name// /+}"
      movieid="$(wget -O- "$url" "${base_wget_args[@]}" | \
        grep -Po "(?<=/en/search/sublanguageid-${lang}/idmovie-)\d+" | head -1)" ||
          { log.fatal "Failed wget $url"; return 1 ; }
    fi
    log.notice "movieid: ${movieid}"
    url="https://www.opensubtitles.org/en/search/sublanguageid-${lang}/idmovie-${movieid}"
    subid="$(wget -O- "$url" "${base_wget_args[@]}" | \
      grep -Po '(?<=/en/subtitleserve/sub/)\d+' | head -1)" ||
        { log.fatal "Failed wget $url"; return 1 ; }
  fi
  log.notice "subid: ${subid}"
  url="https://dl.opensubtitles.org/en/download/sub/$subid"
  log.debug "url: ${url}"
  local zipfile
  if [[ "$name" ]]; then
    # Extract .srt from .zip, rename to $name.srt and rm .zip
    zipfile="${name// /_}.zip"
  else
    # Extract .srt from .zip and rm .zip
    zipfile="$(randstr 4).zip"
  fi
  log.debug "zipfile: ${zipfile}"
  wget -o /dev/null -O "$zipfile" "$url" "${base_wget_args[@]}" || { log.fatal "Failed wget $url"; return 1 ; }
  unzip "$zipfile" '*.srt' || { log.fatal "Failed ${Cc}unzip $zipfile '*.srt'"; return 1 ; }
#  local srtfile="$(unzip -l "$zipfile" '*.srt' | cut -d $'\n' -f 4 | xargs -n1 | tail -1)"
  local srtfile="$(unzip -l "$zipfile" '*.srt' | xargs -n1 | grep -Po '^.*\.srt$')"
  log.debug "srtfile: ${srtfile}"
  if [[ "$name" ]]; then
    mv "$srtfile" "${name}.srt" && \
      log.success "Downloaded subtitles to ${name}.srt" || \
      log.warn "Failed to rename ${srtfile} to ${name}.srt"
  else
    log.success "Downloaded subtitles to ${srtfile}"
  fi
  rm "$zipfile"
  return 0
}

dlsub "$@"