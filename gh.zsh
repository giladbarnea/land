function _remove_surrounding_slashes(){
  local value="$1"
  [[ "$value" = */ ]] && value="${value%/}"
  [[ "$value" = /* ]] && value="${value#/}"
  printf "%s" "$value"
}

# _is_url VALUE
# Slashes >= 2 and dots >= 1.
function _is_url(){
   local slashes="${1//[^\/]/}"
   local slash_count="${#slashes}"
   local dots="${1//[^.]/}"
   local dot_count="${#dots}"
   (( slash_count >= 2 && dot_count >= 1 ))
}

# _is_gh_api_url VALUE
# Returns 0 if it's an api.github.com url.
function _is_gh_api_url(){
  [[ "$1" && "$1" == *api.github.com* ]]
}

# _is_gh_repo_url VALUE
# Returns 0 if it's a github.com but not an api.github.com url.
function _is_gh_repo_url(){
  [[ "$1" && "$1" == *github.com* ]] && ! _is_gh_api_url "$1"
}

# # _extract_repo_name VALUE
# Whether it's a github.com, api.github.com or a simple owner/repo string, returns the owner/repo string.
function _extract_repo_name(){
  local value="$1"
  value="$(_remove_surrounding_slashes "$value")"
  awk -F/ '{print $(NF-1) "/" $NF}' <<< "$value"
  return $?
}

# # _build_url BASE_URL PATH
# E.g. _build_url https://api.github.com/repos naresh-datanut/pyspark-easy
function _build_url(){
  local url="$1"
  local path="$2"
  url="$(_remove_surrounding_slashes "$url")"
  path="$(_remove_surrounding_slashes "$path")"
  printf "%s" "${url}/${path}"
}


# # gh.repo REPOOWNER/FULL_API_URL/FULL_REPO_URL
# Prints the json data of a github repo.
function gh.repo(){
  setopt local_options errreturn
  local url value
  value="$(_extract_repo_name "$1")"
  url="$(_build_url https://api.github.com/repos "$value")"
  http "$url" -j --body --pretty=none --check-status | pym312 json.tool
  return $?
}

# # gh.readme ARG [FOO]
# Prints the raw README.md of a github repo.
function gh.readme(){
  setopt local_options errreturn
  local url value readme_path
  value="$(_extract_repo_name "$1")"
  url="$(_build_url https://raw.githubusercontent.com "$value")"
  readme_path="refs/heads/main/README.md"
  http "${url}/${readme_path}" --body --check-status \
    || http "${url}/refs/heads/$(gh.repo "$url" | jq .default_branch -r)/README.md" --body --check-status
#    || http "${url}/refs/heads/master/README.md" --body --check-status
}
