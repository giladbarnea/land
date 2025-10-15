#!/usr/bin/env bash

if ! isdefined ffmpeg; then
  log.fatal "ffmpeg is not installed"
  return 1
fi

function ffmpeg.concatOLD() {
  python3 -c "
import sys
import time
args = \"$*\".split()
print(f'args: ({type(args)})',args)
if len(args) < 2:
	print('expecting at least 2 args, aborting')
	sys.exit(1)
from pathlib import Path
inputs = []
tmps = []
for i, a in enumerate(args):
	p = Path(a)
	if not p.is_file():
		print(f'{p} does not exist, aborting')
		sys.exit(1)
	if Path(f'tmp{i}.ts').exists():
		print(f'tmp{i}.ts exists, aborting')
		sys.exit(1)
	inputs.append(p)
	tmps.append(f'tmp{i}.ts')
if Path('out.mp4').exists():
	print('out.mp4 already exists, aborting')
	sys.exit(1)
import subprocess as sp
for i, inp in enumerate(inputs):
	cmd = f'ffmpeg -i {inp} -c copy -bsf:v h264_mp4toannexb -f mpegts tmp{i}.ts'.split()
	excode = sp.call(cmd)
	if excode: 
		# not 0
		print(f'failed with input: {inp}, index: {i}. aborting')
		sys.exit(1)
time.sleep(0.5)
joined = '|'.join(tmps)
cmd = f'ffmpeg -i concat:{joined} -c copy -bsf:a aac_adtstoasc out.mp4'.split()
print(f'\nrunning cmd: ',cmd,sep='\n',end='\n')
excode = sp.call(cmd)
if excode: 
	print(f'failed concat command, aborting')
	sys.exit(1)
if input(f'rm {len(tmps)} tmps? y/n\t').lower() == 'y':
	for tmp in tmps:
		cmd = f'rm {tmp}'.split()
		excode = sp.call(cmd)
		if excode: 
			print(f'failed rm {tmp}, aborting')
			sys.exit(1)
print('success')
	"

}

function __ext(){
  local bname="$(basename "$1")"
  echo -n "${bname/*./}"
}
function __stem(){
  local bname="$(basename "$1")"
  local ext="${bname/*./}"
  echo -n "${bname/.${ext}/}"
}

# # ffmpeg._calc_dur <START: hh:mm:ss> <STOP: hh:mm:ss>
function ffmpeg._calc_dur(){
  if [[ -z "$2" ]]; then
    log.fatal "ffmpeg._calc_dur <START: hh:mm:ss> <STOP: hh:mm:ss>"
    return 1
  fi
  local start="$1"
  local stop="$2"
  shift 2
  ! type py.eval &>/dev/null && source <(wget -qO- https://raw.githubusercontent.com/giladbarnea/land/master/pyfns.sh --no-check-certificate)
  echo -n "$start" "$stop" | py.eval 'start, stop = words
    start_h, start_m, start_s = map(int, start.split(":"))
    stop_h, stop_m, stop_s = map(int, stop.split(":"))
    if start_h > stop_h:
        sys.exit(f"Error: start_h > stop_h | {start_h} > {stop_h}")
    # print(f"{start_h = }, {start_m = }, {start_s = }")
    # print(f"{stop_h = }, {stop_m = }, {stop_s = }")
    dur_h = stop_h - start_h
    dur_m = stop_m - start_m
    dur_s = stop_s - start_s
    # print(f"{dur_h = }, {dur_m = }, {dur_s = }")
    if dur_s < 0:
      dur_m -= 1
      dur_s += 60
    if dur_m < 0:
      dur_h -= 1
      dur_m += 60      
    # print(f"{dur_h = }, {dur_m = }, {dur_s = }")
    print(f"{str(dur_h).zfill(2)}:{str(dur_m).zfill(2)}:{str(dur_s).zfill(2)}", end="")
  '
}

# # ffmpeg.get-fps <INPUT_PATH>
function ffmpeg.get-fps() {
  ffprobe "$1" 2>&1 | grep -Po '[\d.]+(?= fps)'
}

# # ffmpeg.get-duration <INPUT_PATH>
function ffmpeg.get-duration(){
  ffprobe "$1" 2>&1 | grep -Po '(?<=Duration: )[^,]+'
}

# # ffmpeg.get-resolution <INPUT_PATH>
function ffmpeg.get-resolution(){
  ffprobe "$1" 2>&1 | grep -Po '(\d{2,}x\d{2,})'
}

# # ffmpeg.get-kbps <INPUT_PATH>
function ffmpeg.get-kbps(){
  ffprobe "$1" 2>&1 | grep -Po '(?<=bitrate: )\d+(?= kb/s)'
}

# # ffmpeg.get-vid-kbps <INPUT_PATH>
function ffmpeg.get-vid-kbps(){
  ffprobe "$1" 2>&1 | grep -Po 'Stream .+\: Video\:.+, (\d+)(?= kb/s)' | grep -Po '\d+$'
}

# # ffmpeg.get-aud-kbps <INPUT_PATH>
function ffmpeg.get-aud-kbps(){
  ffprobe "$1" 2>&1 | grep -Po 'Stream .+\: Audio\:.+, (\d+)(?= kb/s)' | grep -Po '\d+$'
}

# # ffmpeg.inc-rate <INPUT_PATH> <OUTPUT_PATH> <INCREASE_FACTOR: int> [ffmpeg...]
function ffmpeg.inc-rate() {
  if [[ ! "$3" ]]; then
    log.fatal "$0: not enough args (got $#)"
    docstring -p "$0"
    return 1
  fi

  local inpath="$1"
  local outpath="$2"
  local inc_factor="$3"
  shift 3
  local fps=$(ffmpeg.get-fps "$inpath")
  local points=$(py.print "round(1/$inc_factor, 2)")
  local target_fps=$(py.print "round($fps * $inc_factor, 2)")
  confirm "fps: $fps -> $target_fps, points: $points. Continue?" || return 3
  # -vf is filter_graph. mutex with -c copy
  vex ffmpeg -i "$inpath" -vf "'setpts=${points}*PTS'" -r "$target_fps" "$@" "$outpath"
}


# # ffmpeg.concat <INPUT_1...> <INPUT_N> <OUTPATH>
function ffmpeg.concat(){
  if [[ ! "$3" ]]; then
    log.fatal "$0: not enough args (got $#)"
    docstring -p "$0"
    return 1
  fi
  local tmps=()
  log.info "args: $*"
  local tmp
  while [[ $# -gt 1 ]]; do
    tmp=__"$(__stem "$1")".ts
    if ! vex ffmpeg -i "$1" -c copy -bsf:v h264_mp4toannexb -f mpegts "$tmp"; then
      log.fatal "$0 failed converting $1 -> $tmp"
      return 1
    fi
    tmps+=("$tmp")
    shift
  done
  
  local outpath="$1"
  shift
  local tmpstr="${tmps[*]}"
  tmpstr="${tmpstr// /|}"
  local exitcode
  vex ffmpeg -i "\"concat:${tmpstr}\"" -c copy -bsf:a aac_adtstoasc "$outpath"
  exitcode=$?
  if confirm "rm ${tmps[*]}?"; then rm "${tmps[@]}"; fi
  return $exitcode
}



# # ffmpeg.slice.get <INPUT_PATH> <OUTPUT_PATH> <START: hh:mm:ss> [STOP: hh:mm:ss] [ffmpeg...]
function ffmpeg.slice.get(){
  if [[ ! "$3" ]]; then
    log.fatal "$0: not enough args (got $#)"
    docstring -p "$0"
    return 1
  fi
  local inpath="$1"
  local outpath="$2"
  local start="$3"
  local ffmpeg_args=()
  if [[ "$4" && "$4" != -* ]]; then
    ffmpeg_args+=(-to "$4")
    shift 4
  else
    shift 3
  fi
  # async is audio sync. -async 1 is correct the start of audio to timestamp
  ffmpeg_args+=(-async 1 -c copy "$@" "$outpath")
  vex ffmpeg -ss "$start" -i "$inpath" "${ffmpeg_args[@]}"
}

# # ffmpeg.slice.remove <INPUT_PATH> <OUTPUT_PATH> <START: hh:mm:ss> <STOP: hh:mm:ss>
function ffmpeg.slice.remove(){
  if [[ ! "$4" ]]; then
    log.fatal "$0: not enough args (got $#)"
    docstring -p "$0"
    return 1
  fi
  local inpath="$1"
  local outpath="$2"
  local start_remove="$3"
  local stop_remove="$4"
  shift 4
  # local vid_dur
  # if ! vid_dur=$(ffmpeg.get-duration "$inpath"); then log.fatal "Failed ffmpeg.get-duration" && return 1; fi
  # vid_dur="${vid_dur/.*/}"    # 00:01:23.00 -> 00:01:23
  
  local ext="$(__ext "$inpath")"
  local stem="$(__stem "$inpath")"
  local tmp_before_path=/tmp/__"$stem"__before.${ext}
  local tmp_after_path=/tmp/__"$stem"__after.${ext}
	#  if ! ffmpeg -ss "00:00:00" -i "$inpath" -to "$start_remove" -async 1 -strict -2 "$tmp_before_path"; then log.fatal "Failed slicing before" && return 1; fi
  if ! ffmpeg.slice.get "$inpath" "$tmp_before_path" "00:00:00" "$start_remove"; then log.fatal "Failed slicing before" && return 1; fi

	#  if ! ffmpeg -ss "$stop_remove" -i "$inpath" -async 1 -strict -2 "$tmp_after_path"; then log.fatal "Failed slicing after" && return 1; fi
  if ! ffmpeg.slice.get "$inpath" "$tmp_after_path" "$stop_remove"; then log.fatal "Failed slicing after" && return 1; fi

  local exitcode
  vex ffmpeg.concat "$tmp_before_path" "$tmp_after_path" "$outpath"
  exitcode=$?
  rm "$tmp_before_path" "$tmp_after_path"
  return $exitcode

}

# -----------[ Completion ]-----------

declare fnname
for fnname in _calc_dur get-fps get-duration get-resolution inc-rate concat slice.get slice.remove; do
	eval "function _ffmpeg.${fnname}() {
		[[ \$CURRENT == 2 ]] && _files
		compadd -x \"\$(docstring ffmpeg.$fnname)\"
		}"
	compdef _ffmpeg.${fnname} ffmpeg.${fnname}
done
unset fnname

compdef _gnu_generic ffmpeg # parses --help!
