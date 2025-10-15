#!/bin/bash

#######################################
# Configuration of Jira server access #
#######################################
# https://developer.atlassian.com/server/jira/platform/jira-rest-api-examples/
# https://docs.atlassian.com/software/jira/docs/api/REST/7.6.1/
# https://github.com/c9s/jira.sh/blob/master/jira.sh

JIRA_HOST=https://jira.allot.com
JIRA_REST=$JIRA_HOST/rest/api/2

JIRA_USER=
JIRA_PASS=

OFFSET=0

while getopts :d:no: OPT; do
    case $OPT in
	d) day="$OPTARG" ;;
	n) DRY_RUN=1 ;;
	o) OFFSET="$OPTARG" ;;
	*)
	    echo "Usage: ${0##*/} [-n] [-d day] [-o offset] ARGS..."
	    exit 2
    esac
done
shift $(( OPTIND - 1 ))
OPTIND=1

input="$1"

if [ $# -lt 1 ]; then
    cat <<-EOF
	Reading input from standard input (paste your lines here):
	Path in org-mode | jira-id | Description | hh:mm | Start DateTime

EOF
    input="/dev/stdin"
fi

shopt -s expand_aliases
for g in "" e f; do
    alias ${g}grep="LC_ALL=C ${g}grep"	# speed-up grep commands by not considering locale.
done
CURL_OPTS="-s --user '$JIRA_USER:$JIRA_PASS' --header 'Accept: application/json' --header 'Content-Type: application/json'"
alias curlGET="curl  --request GET  $CURL_OPTS"
alias curlPOST="curl --request POST $CURL_OPTS"
alias curlPUT="curl  --request PUT  $CURL_OPTS"

function Trim() {
    #Turn on extended globbing
    shopt -s extglob
    #Trim leading and trailing whitespace from a variable
    x=${1##+([[:space:]])}; x=${x%%+([[:space:]])}
    #Turn off extended globbing
    shopt -u extglob
    echo "$x"
}

function TimeToFractionRedmine() {
    local steps=( 7 0   22 0.25   35 0.5   50 0.75    61 1.0 )
    local fraction=${1%:*}
    local minute
    minute=$(sed -nr 's/.*:([0-9]{1,2})/\1/p' <<<"$1")

    min=0
    while [ $min -le ${#steps[*]} ]; do
	if [ "${minute:-0}" -lt "${steps[$min]}" ]; then
	    (( min++ ))
	    fraction=$(bc <<<"${fraction:-0} + ${steps[$min]}")
	    break
	fi
	(( min+=2 ))
    done
    echo "$fraction"
}

function TimeToFraction() {
    bc <<<"scale=2 ; ${1%:*} + ${1#*:} / 60"
}

function TimeToJiraFormat() {
    echo "${1%:*}h ${1#*:}m"
}

# Issue Id
# Comment
# Time spend
# Day
function ReportTime() {
    if [ -z "$DRY_RUN" ]; then
	local return
	return=$(curlPOST "${JIRA_REST}/issue/$1/worklog?notifyUsers=false" --data "
		{
		    \"timeSpent\": \"$3\",
		    \"comment\": \"$2\",
		    \"started\": \"$4.000+0100\"
		}
		"
	      )
    else
	local return="ok"
    fi
    echo -n "($1,${2:0:20}...,$3),$4) .:. "

    if [ ${#return} -eq 0 ]; then
	echo "ERROR : Connection problem"
    elif grep -Fq "\"errors\":" <<<"$return"; then
	sed -r 's/\{"errors":\[(.+)\]\}/ERROR : \1/' <<<"$return"
    else
	echo "OK"
    fi
}

IFS="|"
total=0
while read -r -a fields ; do
    if [ "${fields[$OFFSET]}" = "#" ]; then
	if [ "$total" != 0 ]; then echo "    Total time ($day) = $total" ; fi
	day=${fields[$((OFFSET + 1))]}
	total=0
    elif [ "${fields[$OFFSET]:0:2}" = "//" ] || [ -z "${fields[$OFFSET]}" ]; then
	continue 		# just skip C++ comments
    else
	ReportTime "$(Trim "${fields[$OFFSET]}")"	\
		   "$(Trim "${fields[$((OFFSET + 1))]}")"		\
		   "$(TimeToJiraFormat "${fields[$((OFFSET + 2))]}")"	\
		   "$(Trim "${fields[$((OFFSET + 3))]}")"

	total=$(bc <<<"$total + $(TimeToFraction "${fields[$((OFFSET + 2))]}")")
	[ -z "$DRY_RUN" ] && sleep 0.5
    fi
done < "$input"

echo "    Total time ($day) = $total hours"
