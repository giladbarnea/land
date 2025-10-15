#!/usr/bin/env zsh

function url2md(){
	local html
	html="$(http --body --ignore-stdin --check-status --pretty=none "$1")" || {
		log.error "Failed to get HTML for '$1'"
		return 1
	}
	local md
	md="$(html2md <<<$html)" || {
		log.error "Failed to convert HTML to MD"
		return 1
	}
	print -- "$md"
	return 0
}

# # firecrawl <URL/STDIN> [-o,--output FILE] [firecrawl options...]
# Converts a URL to text using firecrawl.
# Available options:
# - formats:=["markdown"]  # Available formats: markdown, html, rawHtml, screenshot, links, json
# - onlyMainContent:=true
# - includeTags: string[]
# - excludeTags: string[]    # E.g. 'excludeTags:=["a", "svg", "img"]'
# - maxAge:=0. Increase to enable caching.
# - waitFor:=4000
# - timeout:=30000
# - removeBase64Images:=true
# - jsonOptions:={"prompt": "Extract the content of the page."}  # Only used if formats includes json.
# - parsePdf:=true
# Examples:
# firecrawl ${url} 'formats:=["markdown","json"]' 'jsonOptions:={"prompt": "Store the URLs of all the images in the webpage in a ‘images’ array"}' -o foo.json
function firecrawl() {
	setopt localoptions pipefail
	local url
	local -a firecrawl_options=(
		'onlyMainContent:=true'
		'removeBase64Images:=true'
		'waitFor:=4000'
		'timeout:=30000'
		'location:={"country": "US", "languages": ["en-US"]}'
	)
	local default_formats='formats:=["markdown"]'
	local output_file
	
	# Parse arguments
	while [[ "$#" -gt 0 ]]; do
		case "$1" in
			-o|--output) output_file="$2"; shift ;;
			-o=*|--output=*) output_file="${1#*=}" ;;
			-) url="$(<&0)" ;;
			-*) firecrawl_options+=("$1") ;;
			*)
				if [[ ! "$url" ]]; then
					url="${1%/}"
				else
					firecrawl_options+=("$1")
				fi
				;;
		esac
		shift
	done
	if [[ ! "${firecrawl_options[(r)formats:=*]}" ]]; then
		firecrawl_options+=("$default_formats")
	fi
	
	
	if [[ ! "$url" ]] && is_piped; then
		url="$(<&0)"
	fi
	
	[[ ! "$url" ]] && { log.error "$0: No URL provided"; return 1; }
	
	
	# Convert the URL using firecrawl
	local firecrawl_api_key_path="$HOME/.firecrawl-api-key"
	log.debug "Using firecrawl to convert '$url' to markdown. $(typeset url firecrawl_options)"
	setopt localoptions errreturn pipefail
	local raw_response
	raw_response="$(
		http --body --ignore-stdin --check-status POST "https://api.firecrawl.dev/v1/scrape" \
			"Authorization: Bearer $(<"$firecrawl_api_key_path")" \
			'Content-Type: application/json' \
			"url=$url" \
			"${firecrawl_options[@]}"
		)" || {
		log.error "Failed to convert '$url' to text with firecrawl"
		return 1
	}
	if [[ "$output_file" ]]; then
		jq -r <<< "$raw_response" > "$output_file"
		log.success "Saved scraped data to $output_file"
		local -i backslash_at_endofline_count
		backslash_at_endofline_count=$(rg --count '^.*\\$' "$output_file")
		if (( backslash_at_endofline_count > 5 )); then
			confirm "There are $backslash_at_endofline_count backslashes at the end of lines in $output_file. Remove them?" || return 0
			sed -E -i '' 's/\\$//' "$output_file"
			backslash_at_endofline_count=$(rg --count '^.*\\$' "$output_file")
			log.prompt "Lines with backslashes at the end of line after removal: $backslash_at_endofline_count"
		fi
	else
		jq -r <<< "$raw_response"
		log.success "Successfully converted '$url' to text with firecrawl"
	fi
	return 0
}

# # firecrawls <URL...> [-o,--output DIR=PWD] [-x,--fail (default false)] [firecrawl options...]
# Wrapper around for url in urls; do firecrawl "$url" "$@"; done. 
# If -x is provided, fail if any of the firecrawls fail.
# Returns failed requests count.
function firecrawls(){
	# TODO: consider /batch/scrape endpoint
	local -a urls
	local -a firecrawl_options
	local output_dir="${PWD}"
	local fail=false
	while [[ $# -gt 0 ]]; do
		case "$1" in
			-o|--output) output_dir="$2"; shift ;;
			-o=*|--output=*) output_dir="${1#*=}" ;;
			-x|--fail) fail=true ;;
			-*=*) firecrawl_options+=("$1") ;;
			-*) firecrawl_options+=("$1" "$2"); shift ;;
			http*|www*|*.*) urls+=("$1") ;;
			*) firecrawl_options+=("$1") ;;
		esac
		shift
	done

	if [[ -z "$urls" ]]; then
		log.error "$0: No URLs provided"
		docstring -p "$0"
		return 1
	fi
	
	mkdir -p "$output_dir"
	local url
	local clean_url
	local -i exit_code=0
	local -i failed_count=0
	local response
	for url in "${urls[@]}"; do
		clean_url="${url%/}"
		log.notice "Scraping $clean_url into $output_dir/${clean_url##*/}.json"
		response="$(firecrawl "$clean_url" "${firecrawl_options[@]}")"
		exit_code=$?
		if [[ "$fail" = true && "$exit_code" -ne 0 ]]; then
			log.error "Firecrawl failed for $clean_url with exit code $exit_code"
			return $exit_code
		fi
		if [[ "$fail" = false && "$exit_code" -ne 0 ]]; then
			log.warn "Firecrawl failed for $clean_url with exit code $exit_code. Continuing..."
		fi
		[[ "$fail" = true ]] && ((failed_count++))
		[[ "$fail" = false ]] && jq -r <<< "$response" > "$output_dir/${clean_url##*/}.json"
	done
	log.notice "Done with ${failed_count} failures"
	return $failed_count
}

# # firecrawl-map <URL> [-n, --dry-run]
# Wrapper for the vanilla /map endpoint.
# Available options:
# - search:=string    # Filter URLs
function firecrawl-map(){
	local url
	local dry_run=false
	local -a firecrawl_options
	while [[ $# -gt 0 ]]; do
		case "$1" in
			-n|--dry-run) dry_run=true ;;
			*) 
			if [[ ! "$url" ]]; then
				url="${1%/}"
			else
				firecrawl_options+=("$1")
			fi
			;;
		esac
		shift
	done
	local firecrawl_api_key_path="$HOME/.firecrawl-api-key"
	if [[ "$dry_run" = true ]]; then
		log.notice "Would have run:"
		echo "http --body --ignore-stdin --check-status POST https://api.firecrawl.dev/v1/map
			'Authorization: Bearer $(<"$firecrawl_api_key_path")'
			'Content-Type: application/json'
			'url=$url'
			${(@qq)firecrawl_options[*]}"
		return 0
	fi
	local raw_response
	raw_response="$(
		http --body --ignore-stdin --check-status POST https://api.firecrawl.dev/v1/map \
			"Authorization: Bearer $(<"$firecrawl_api_key_path")" \
			"Content-Type: application/json" \
			"url=$url" \
			"${firecrawl_options[@]}"
		)" || {
		log.error "Failed to map '$url' with firecrawl"
		return 1
	}
	jq -r <<< "$raw_response"
}

# # firecrawl-map-smart <URL> [-n, --dry-run]
function firecrawl-map-smart(){
	local firecrawl_api_key_path="$HOME/.firecrawl-api-key"
	local url
	local dry_run=false
	while [[ $# -gt 0 ]]; do
		case "$1" in
			-n|--dry-run) dry_run=true ;;
			*) url="$1" ;;
		esac
		shift
	done
	
	if [[ "$dry_run" = true ]]; then
		log.notice "Would have run:"
		echo "http --body --ignore-stdin --check-status POST https://api.firecrawl.dev/v1/scrape
			'Authorization: Bearer $(<"$firecrawl_api_key_path")'
			'Content-Type: application/json'
			'url=$url'
			'formats:=["markdown", "links"]'
			'onlyMainContent:=false'
			'waitFor:=2000'"
		return 0
	fi
	local raw_response
	raw_response="$(http --body --ignore-stdin --check-status POST https://api.firecrawl.dev/v1/scrape \
		"Authorization: Bearer $(<"$firecrawl_api_key_path")" \
		'Content-Type: application/json' \
		"url=$url" \
		'formats:=["markdown", "links"]' \
		'onlyMainContent:=false' \
		'waitFor:=2000')" || {
		log.error "Failed to convert '$url' to text with firecrawl"
		return 1
	}
	setopt localoptions pipefail errreturn
	notif.info "Passing scraped url to LLM to extract all the links."
	echo "$raw_response" \
		| llm -m flash -st 'scraping result' 'list the links to all the pages of the website' \
		| sed -n 's/.*\(https[^)]*\).*/\1/p'
}

# # firecrawl-crawl <URL>
# Wrapper for the /crawl endpoint.
# Available options:
# - limit:=int    # Maximum number of pages to crawl. Default: 10.
# - scrapeOptions:={"formats":["markdown", "html"], "maxAge": 604800000}  # Default format: markdown, maxAge for cache: 1 week.
#   * 5 minutes: 300000    For semi-dynamic content
#   * 1 hour: 3600000      For content that updates hourly
#   * 1 day: 86400000      For daily-updated content
#   * 1 week: 604800000    For relatively static content
function firecrawl-crawl(){
	local url
	local -a firecrawl_options=(
		'limit:=10'
		'scrapeOptions:={"formats":["markdown"], "maxAge": 604800000}'
	)
	local dry_run=false
	while [[ $# -gt 0 ]]; do
		case "$1" in
			-n|--dry-run) dry_run=true ;;
			*) 
			if [[ ! "$url" ]]; then
				url="${1%/}"
			else
				firecrawl_options+=("$1")
			fi
			;;
		esac
		shift
	done
	local firecrawl_api_key_path="$HOME/.firecrawl-api-key"
	if [[ "$dry_run" = true ]]; then
		log.notice "Would have run:"
		echo "http --body --ignore-stdin --check-status POST https://api.firecrawl.dev/v1/crawl
			'Authorization: Bearer $(<"$firecrawl_api_key_path")'
			'Content-Type: application/json'
			'url=$url'
			${(@qq)firecrawl_options[*]}"
		return 0
	fi
	local raw_response
	raw_response="$(http --body --ignore-stdin --check-status POST https://api.firecrawl.dev/v1/crawl \
		"Authorization: Bearer $(<"$firecrawl_api_key_path")" \
		"Content-Type: application/json" \
		"url=$url" \
		"${firecrawl_options[@]}")" || {
		log.error "Failed to crawl '$url' with firecrawl"
		return 1
	}
	[[ "$(jq -r '.success' <<< "$raw_response")" = true ]] || {
		log.error "Failed to start crawl for '$url' with firecrawl. Job status:"
		jq -r <<< "$raw_response"
		return 1
	}
	local jobs_status_url="$(jq -r '.url' <<< "$raw_response")"
	local jobs_status_response
	jobs_status_response="$(
		http --body --ignore-stdin --check-status GET "$jobs_status_url" \
			"Authorization: Bearer $(<"$firecrawl_api_key_path")" \
			"Content-Type: application/json"
		)" || {
		log.error "Failed to get jobs status for '$url' with firecrawl"
		return 1
	}
	# Schema:
	# completed: int
	# creditsUsed: int
	# expiresAt: "YYYY-MM-DDTHH:MM:SSZ"
	# next: url
	# status: "scraping" | "completed"
	# success: bool
	# total: int
	# data: [ $format: ... ]
	[[ "$(jq -r '.success' <<< "$jobs_status_response")" = true ]] || {
		log.error "Failed to poll jobs status for '$url' with firecrawl. Job status:"
		jq -r <<< "$jobs_status_response"
		return 1
	}
	jq -r <<< "$jobs_status_response"
	local -i total_jobs="$(jq -r '.total' <<< "$jobs_status_response")"
	local -i credits_used="$(jq -r '.creditsUsed' <<< "$jobs_status_response")"
	log.notice "Waiting for $total_jobs jobs to complete..."
	local -i last_completed_jobs=0
	local -i previous_completed_jobs=0
	local -i no_progress_count=0
	local -i sleep_time=4
	local -i max_no_progress_time=12
	while [[ "$(jq -r '.status' <<< "$jobs_status_response")" != "completed" ]]; do
		sleep $sleep_time
		jobs_status_response="$(
			http --body --ignore-stdin --check-status GET "$jobs_status_url" \
				"Authorization: Bearer $(<"$firecrawl_api_key_path")" \
				"Content-Type: application/json"
		)" || {
			log.error "Failed to get jobs status for '$url' with firecrawl"
			return 1
		}
		last_completed_jobs=$(jq -r '.completed' <<< "$jobs_status_response")
		
		# Heuristic to detect if the crawl is stuck: expecting progress at least every 12 seconds.
		if (( last_completed_jobs == previous_completed_jobs )); then
			((no_progress_count++))
			if (( no_progress_count*sleep_time > max_no_progress_time )); then
				log.error "No progress for $((no_progress_count*sleep_time)) seconds; Job status:"
				jq -r <<< "$jobs_status_response"
				return 1
			fi
			log.notice "No progress for $((no_progress_count*sleep_time)) seconds; will abort if persists over $max_no_progress_time seconds"
		else
			no_progress_count=0
			log.notice "Completed $last_completed_jobs/$total_jobs jobs. Credits used: $credits_used"
		fi
		previous_completed_jobs=$last_completed_jobs
	done
	log.success "Crawl completed. Credits used: $credits_used"
	jq -r <<< "$jobs_status_response"
}

# # firecrawl2speech <URL>
# Scrapes a URL with firecrawl, extracts the markdown, downloads the screenshot and images, prepends with a TTS prompt, and converts to speech with OpenAI.
function firecrawl2speech(){
	setopt localoptions errreturn pipefail
	local url="$1"
	[[ -z "$url" ]] && {
		log.error "Usage: firecrawl2speech <URL>"
		return 1
	}
	
	local firecrawl_api_key_path="$HOME/.firecrawl-api-key"
	[[ ! -f "$firecrawl_api_key_path" ]] && {
		log.error "Firecrawl API key not found at $firecrawl_api_key_path"
		return 1
	}
	
	local openai_api_key_path="$HOME/.openai-api-key"
	[[ ! -f "$openai_api_key_path" ]] && {
		log.error "OpenAI API key not found at $openai_api_key_path"
		return 1
	}
	
	
	# Step 1: Scrape the URL with firecrawl
	log.info "Scraping URL with firecrawl..."
	cached firecrawl "$url" \
		'excludeTags:=["a", "svg"]' \
		'actions:=[{"type":"screenshot", "fullPage":true,"quality":100}, {"type":"executeJavascript", "script":"[...document.querySelectorAll('"'"'img'"'"')].map(img=>img.src)"}]' \
		-f 'markdown,screenshot@fullPage' \
		> page.json
	
	log.success "Saved scraped data to page.json"
	
	# Step 2: Extract markdown to file
	log.info "Extracting markdown..."
	jq -r '.data.markdown' page.json > page.md
	log.success "Saved markdown to page.md"
	
	# Step 3: Download screenshot
	log.info "Downloading screenshot..."
	local screenshot_url
	screenshot_url="$(jq -r '.data.screenshot' page.json)"
	if [[ "$screenshot_url" != "null" && -n "$screenshot_url" ]]; then
		curl -o screenshot.png "$screenshot_url"
		log.success "Downloaded screenshot to screenshot.png"
	else
		log.warn "No screenshot available"
	fi
	
	# Step 4: Download images with gemini
	# log.info "Using gemini to download and name images..."
	# if jq -e '.data.actions.javascriptReturns[0].value' page.json > /dev/null 2>&1; then
	# 	gemini --yolo -p '
	# 	The following task is meant to be executed idempotently (hence the "if exists, skip" instructions).
	# 	1. First, list the current directory entries.
	# 	2. Download each of the pngs listed in the `.data.actions.javascriptReturns[0].value` field in page.json to the current directory. Use `jq` to extract the urls. If the current directory already contains png files corresponding to the urls, skip this straight to step 4 (the last step).
	# 	3. Read the image files and look at them to understand their purpose and message. Rename the downloaded image files with a fitting kebab-case name, based on their content. If they are already renamed, skip this step.
	# 	4. Replace the URL references of the images in page.md with the existing relative file paths and write an informative but succinct description of each image by adding a ![alt <informative description>] to the image reference in the markdown. If the references are already replaced in page.md, there is nothing else to do; say that you are done.'
	# 	log.success "Downloaded images via gemini"
	# else
	# 	log.warn "No images found to download"
	# fi
	
	local page_content="$(<page.md)"
	local to_tts_prompt="$(llm-template readable)"
	
	# Step 5: Convert markdown to literal text for TTS
	log.info "Converting markdown to literal text for TTS..."
	gemini --yolo -p "$to_tts_prompt" "$page_content"
	
	# Step 6: Convert to speech with Hume AI
	log.info "Converting to speech with Hume AI..."

	api_key="$(<"$HOME/.hume-api-key")"
	output_file="page-readable-hume.mp3"

	escaped_text=$(printf "%s" "${page_content}" | jq -Rs .)

	curl -X POST "https://api.hume.ai/v0/tts/file" \
		-H "X-Hume-Api-Key: ${api_key}" \
		-H "Content-Type: application/json" \
		-d '{
				"utterances": [{
						"text": '"${escaped_text}"',
						"description": "An intelligent, interesting voice with academic erudition and a deep understanding of the content.",
						"voice": { "name": "Vince Douglas", "provider": "HUME_AI" }
				}],
				"format": {
						"type": "mp3"
				},
				"num_generations": 1
		}' \
		--output "${output_file}" \
		--fail

	echo "Audio saved to: ${output_file}"
	
	
	log.success "Speech generated and saved to page.mp3"
}

function jina(){
	cached http POST "https://r.jina.ai/$1" \
		--body \
		--ignore-stdin \
		--check-status \
		"Authorization: Bearer $(<"${HOME}/.jina-api-key")"
}