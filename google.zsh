# google QUERY [RESULT_INDEX]
function google(){
  local query="$1"
  local result_index
  [[ "$2" ]] && result_index="$2"
  local search_results="$(curl --location --request POST https://google.serper.dev/search \
                              --data-raw "{\"q\":\"${query}\"}" \
                              --header "X-API-KEY: $(<~/.serpapi-api-key)" \
                              --header 'Content-Type: application/json' 2>/dev/null)"
  if [[ -n "$result_index" ]]; then
    jq '.organic[0].link' -r 2>/dev/null <<< "$search_results"
  else
    pym312 json.tool <<< "$search_results"
  fi
}
