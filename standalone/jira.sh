#!/usr/bin/env bash


# # jira.issue <ISSUE> [shamrg]
# Does GET to `ISSUE`
# ## Examples:
# ```bash
# jira.issue
# ```
function jira.issue(){
	# https://developer.atlassian.com/cloud/jira/platform/rest/v2/api-group-issues/#api-rest-api-2-issue-issueidorkey-put
	# git reflog --all --date=local | grep ASM-16598 | grep -Po '\{.+\}' | sort -u         # or --date=format:'%Y-%m-%d %T'
	# git reflog --date=format:'%Y-%m-%d %T' --author='Gilad Barnea' --branches --until=2022-03-16 --after=2022-13-15
  if [[ -z "$1" ]]; then
		log.fatal "$0 requires at least one arg"
		docstring -p "$0"
		return 1
  fi
  local issue="$1"
  shift
	#  if ! source "$HOME/.jira"; then
	#	log.fatal "failed sourcing $HOME/.jira"
	#	return 1
	#  fi
  
  if [[ -z "$JIRA_USER" || -z "$JIRA_PASS" ]]; then
		log.fatal '$JIRA_USER or $JIRA_PASS env vars do not exist. check $HOME/.jira file.'
		return 1
  fi
  vex curl --request GET -s \
  	--silent \
  	--user "${JIRA_USER}":"${JIRA_PASS}" \
  	--header '"Accept: application/json"' \
  	--header '"Content-Type: application/json"' \
  	"https://jira.<subdomain>.com/rest/api/2/issue/${issue}" | syspy -m json.tool --sort-keys
	# Interesting fields (fields.):
	# created: str, subtasks: [], summary: str, timeestimate: int, timeoriginalestimate: int, timespent: int, timetracking: {}
	# timetracking:
	# originalEstimate: str, originalEstimateSeconds: int, remainingEstimate: str, remainingEstimateSeconds: int, timeSpent: str, timeSpentSeconds: int
	# summary bean field: jq '.fields' | grep -Po '(?<=").+(?=": "{summaryBean)'
	# devSummaryJson: jq '.fields' | grep -Po '(?<=devSummaryJson=).+' | tr -d '\\' | rev | cut -c 4- | rev | jq '.cachedValue.summary'
	# date '+%Y-%m-%d %H:%M' -d $(cat /tmp/jira.ASM-16567.json | jq -r '.fields.created')
	# jq -r '.fields | {summary,created,updated,resolution: {name: .resolution.name, date: .resolutiondate},timespent,timeestimate,timeoriginalestimate,timetracking: {remaining: .timetracking.remainingEstimate, spent: .timetracking.timeSpent}}' <(cat /tmp/jira.ASM-16573.format.json)
}


# # jira.tasks [OPTIONS...] [jira-cli OPTIONS...]
# Shows tasks assigned to me which are not subtasks
# ## Options
# --subtasks[=BOOL]			Default false
# --status=STR					
# --resolution=STR				
# --andjql=STR				
# --orjql=STR				
function jira.tasks(){
	local show_subtasks=false
	local jql='assignee=<username>\u0040<domain>.com'
	local andjql
	local orjql
	local taskstatus
	local resolution
	local args=()
	while [[ "$#" -gt 0 ]]; do
	  case "$1" in
		--subtasks | --subtasks=[Tt]rue | --subtasks=[Ff]alse)
		  if [[ "$1" == --subtasks || "$1" =~ --subtasks=[Tt]rue ]]; then
			show_subtasks=true
		  else
			show_subtasks=false
		  fi
		  log.debug "show_subtasks: $show_subtasks"
		  shift ;;
		--resolution=*)
		  resolution="'${1#*=}'"
		  log.debug "resolution: $resolution"
		  shift ;;
		--status=*)
		  taskstatus="'${1#*=}'"
		  log.debug "taskstatus: $taskstatus"
		  shift ;;
		--andjql=*)
		  andjql="${1#*=}"
		  log.debug "andjql: $andjql"
		  shift ;;
		--orjql=*)
		  orjql="${1#*=}"
		  log.debug "orjql: $orjql"
		  shift ;;
		
		*)
		  args+=("$1")
		  shift ;;
	  esac
	done
	set -- "${args[@]}"
	[[ -n "$args" ]] && log.debug "args: ${args[*]}"
	
	if [[ -n "$andjql" ]]; then
	  jql="$jql AND $andjql"
	fi
	
	if [[ -n "$orjql" ]]; then
	  jql="$jql OR $orjql"
	fi
	
	if [[ -n "$taskstatus" ]]; then
	  jql="$jql AND status = $taskstatus"
	fi
	
	if [[ -n "$resolution" ]]; then
	  jql="$jql AND resolution = $resolution"
	fi
	
	if ! $show_subtasks; then
		jql="$jql AND issueLinkType NOT IN ('Child of','is blocked by')"
	fi
	jql="$jql ORDER BY status ASC"
	log.debug "jql: $jql"
	jira-cli view --search-jql="$jql" "${args[@]}"
}
function jira.unresolved(){
	jira.tasks --resolution='Unresolved'
}
# # jira.inprogress [OPTIONS...] [jira-cli OPTIONS...]
# Convenience for `jira.tasks --status='In Progress'`
function jira.inprogress(){
	jira.tasks --status='In Progress' "$@"
}
