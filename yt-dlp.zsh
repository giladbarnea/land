#!/usr/bin/env zsh

# # yt-dlp.info <URL / STDIN>
function yt-dlp.info(){
	local url
	if [[ ! "$1" ]] && is_piped; then
		url="$(<&0)"
	else
		url="$1"
		shift || { log.error "$0: Not enough args (expected 1, got ${#$}). Usage:\n$(docstring "$0")"; return 2; }
	fi
	[[ "$url" ]] || { log.error "$0: Not enough args (expected 1, got ${#$}). Usage:\n$(docstring "$0")"; return 2; }
	setopt localoptions errreturn
	local info_file_name
	info_file_name="$(yt-dlp "$url" --restrict-filenames --no-mark-watched --write-info-json --no-download --clean-info-json --no-write-comments --console-title \
		| eee | grep -Eo '\b[^ ]+\.json\b')"
	[[ -f "$info_file_name" ]] || { log.error "Info file not found: $info_file_name"; return 1; }
	log.success "Info file: $info_file_name"
	jq --arg file_path "$info_file_name" '
		# Helper function to pad a number to two digits with a leading zero
		def pad_two_digits:
				. as $num |
				if $num < 10 then "0" + ($num|tostring) else ($num|tostring) end;

		# Helper function to convert seconds to hh:mm:ss format
		def to_hhmmss:
				floor as $seconds_total | # Ensure we are working with whole seconds
				($seconds_total / 3600 | floor) as $h |
				(($seconds_total % 3600) / 60 | floor) as $m |
				($seconds_total % 60) as $s |
				( ($h | pad_two_digits) + ":" +
						($m | pad_two_digits) + ":" +
						($s | pad_two_digits) );

		{
				title: .title,
				file_path: $file_path,
				description: .description,
				subtitles: .subtitles,
				# Create a flat list of numbered chapter titles
				chapters: (
						.chapters // [] | # Handle null or missing chapters array
						to_entries | # Converts array to [{key:0, value:...}, {key:1, value:...}]
						map(
								((.key) | pad_two_digits) + ". [" + (.value.start_time | to_hhmmss) + "-" + (.value.end_time | to_hhmmss) + "] " + (.value.title // "N/A Chapter Title")
						)
				),
				automatic_captions: [ (.automatic_captions // {}) | keys[] | select(startswith("en")) ],
				top_3_heatmap: (
						(.heatmap // []) |
						sort_by(.value) |
						reverse |
						.[0:3] |
						map(
								{
										start_time: (.start_time | to_hhmmss),
										end_time: (.end_time | to_hhmmss),
										value: .value
								}
						)
				),
				duration_string: .duration_string
		}
	' "$info_file_name"
	
}

# # yt-dlp.subs <URL / STDIN>
function yt-dlp.subs(){
	local url
	if [[ ! "$1" ]] && is_piped; then
		url="$(<&0)"
	else
		url="$1"
		shift || { log.error "$0: Not enough args (expected 1, got ${#$}). Usage:\n$(docstring "$0")"; return 2; }
	fi
	[[ "$url" ]] || { log.error "$0: Not enough args (expected 1, got ${#$}). Usage:\n$(docstring "$0")"; return 2; }
	
	
	# --- Get title and available subtitles
	local title="$(yt-dlp "$url" --ignore-config --get-title)" || { log.error "Failed getting title"; return 1; }
	local title_path_appropriate="$(topathlike "$title" -f)"
	mkdir -p "./${title_path_appropriate}" || { log.error "Failed creating directory: ./${title_path_appropriate}"; return 1; }
	local subtitle_list_raw="$(yt-dlp "$url" --ignore-config --no-mark-watched --list-subs)"
	
	command grep -q 'has no subtitles' <<< "$subtitle_list_raw" && {
		log.warn "Listing subtitles also outputted that there are no subtitles available. Continuing anyway.";
	}
	
	.dl-subs(){
		vex ---just-run yt-dlp --restrict-filenames --no-mark-watched --skip-download "$@" 1>&2
	}
	local subtitle_lang
	local any_subtitles_downloaded_succesfully=false
	local -a available_eng_subtitles=( $(echo "$subtitle_list_raw" | awk '/^en/{print $1}') )
	
	if [[ ${available_eng_subtitles} ]]; then
		log.info "English subtitles available: ${available_eng_subtitles[*]}"
		if [[ ${available_eng_subtitles[(r)en-orig]} ]]; then
			subtitle_lang=en-orig
		elif [[ ${available_eng_subtitles[(r)en-US]} ]]; then
			subtitle_lang=en-US
		elif [[ ${available_eng_subtitles[(r)en]} ]]; then
			subtitle_lang=en
		else
			subtitle_lang="$(input "Sub languages 'en-orig', 'en-US' and 'en' are unavailable. Choose subtitle language:" --choices="( "${available_eng_subtitles[*]}" )")"
		fi
		log.info "Title: ${title}. Downloading proper subtitles into ./${title_path_appropriate}/subtitles..."
		
		# --- Download real subtitles
		.dl-subs "$url" --write-subs --sub-langs="${subtitle_lang}" --sub-format=srv1 --output "./${title_path_appropriate}/subtitles"

		[[ -n ./${title_path_appropriate}/subtitles*.srv1(#qN) ]] \
			&& any_subtitles_downloaded_succesfully=true
	else
		log.warn "No english subtitles available. Counting on auto-generated.";
	fi
	
	if [[ "$any_subtitles_downloaded_succesfully" = false ]]; then
	    # --- Download auto generated subtitles
		log.warn "No real subtitles downloaded. Attempting to download auto-generated subtitles..."
		.dl-subs "$url" --write-auto-subs --sub-langs="${subtitle_lang}" --sub-format=srv1 --output "./${title_path_appropriate}/subtitles"
	fi
	
	
	
	any_subtitles_downloaded_succesfully=false
	[[ -n ./${title_path_appropriate}/subtitles*.srv1(#qN) ]] \
		&& any_subtitles_downloaded_succesfully=true
	
	if [[ "$any_subtitles_downloaded_succesfully" = false ]]; then
		# --- Download real subtitles without specifying language
		log.warn "No auto-generated subtitles downloaded. Attempting to download real subtitles without specifying language..."
		.dl-subs "$url" --write-subs --sub-format=srv1 --output "./${title_path_appropriate}/subtitles"
	fi
	
	any_subtitles_downloaded_succesfully=false
	[[ -n ./${title_path_appropriate}/subtitles*.srv1(#qN) ]] \
		&& any_subtitles_downloaded_succesfully=true
	
	if [[ "$any_subtitles_downloaded_succesfully" = false ]]; then
	# --- Download auto generated subtitles without specifying language
		log.warn "No real subtitles downloaded even without specifying language. Attempting to download auto-generated subtitles without specifying language..."
		.dl-subs "$url" --write-auto-subs --sub-format=srv1 --output "./${title_path_appropriate}/subtitles"
	fi
	
	[[ -n ./${title_path_appropriate}/subtitles*.srv1(#qN) ]] || { log.error "Failed to download subtitles"; return 1; }
	
	log.success "Downloaded subtitles to ./${title_path_appropriate}/subtitles. Processing subtitles into Markdown..."

	setopt localoptions errreturn
	
	yt-dlp.info "$url" > "./${title_path_appropriate}/short-info.json"
	
	# Create chapters markdown files
	python3 "$SCRIPTS"/standalone/yt_dlp_xml_to_md.py ./${title_path_appropriate}/subtitles*.srv1([1]) "./${title_path_appropriate}/short-info.json" --split -o "./${title_path_appropriate}/chapters"
	
	local file	
	# Punctuation
	log.title "Punctuating and summarizing chapters..."
	for file in ./${title_path_appropriate}/chapters/*.md; do
		( 
			cat "$file" | llm "The attached markdown file, ${file##*/}, contains a chapter of a YouTube video. Punctuate the text so that it makes sense, then join the lines and break them according to the text's meaning. Keep the original text unchanged except for formatting. Think as much as you need, but your final response should simply be the punctuated text, nothing else." --stdin-tag "chapter '${${file##*/}%.*}' of a YouTube video" --no-md -m flash > "${file%.*}.punctuated.md" ;
			mv "${file%.*}.punctuated.md" "$file" ;
			cat "${file}" | llm "The attached markdown file, ${file##*/}, contains a chapter of a YouTube video. Summarize it succinctly and directly, without fluff, but DENSELY. By densely I mean: high signal-to-noise ratio / low entropy / and exhaustive coverage but far from verbose. The summary should be pleasant to read, have a #title, separated to sections if needed for readability, nicely formatted, have bullets if needed, high-quality, captures the high-value takeaways of the chapter, but not verbose. Think as much as you need, but your final response should simply be your summary. If you need to, refer to the text as 'this chapter'." --stdin-tag "chapter '${${file##*/}%.*}' of a YouTube video" --no-md -m flash > "${file%.*}.summary.md" ;
		) &
	done
}


# # yt-dlp.concurrent-playlist <URL> [yt-dlp options...]
function yt-dlp.concurrent-playlist(){
	local positional=()
	local url
	while [[ $# -gt 0 ]]; do
		case "$1" in
			-*) positional+=("$1"); shift ;;
			*) url="$1"; shift ;;
		esac
	 done
	 set -- "${positional[@]}"
	 log.debug "url: $url | @: $*"
	 local vidcount
	 vidcount="$(yt-dlp "$url" --ignore-config --flat-playlist --get-filename | wc -l)" || { log.fatal Failed; return 1; }
	 log.info "vidcount: $vidcount"
	 local i
	 local via=normal
	 isdefined kitty && confirm "Use ${Cc}kitty @launch --type=tab --dont-take-focus --cwd=current --hold --copy-env${Cc0} for each command?" && via=kitty
	 for i in $(seq $vidcount); do
	 		if [ $via = kitty ]; then
	 			kitty @launch --type=tab --dont-take-focus --cwd=current --hold --copy-env zsh -i -c "yt-dlp \"${url}\" --playlist-items=$i $*"
	 		else
	 			(
	 				_title="${url}:${i}/${vidcount}"
	 				log.megatitle "$_title starting"
	 				yt-dlp "$url" --playlist-items "$i" "$@" && log.megasuccess "$_title" || log.megaerror "$_title"
	 			) &
	 		fi
	 done
}
