#!/usr/bin/env zsh

# sourced before tools.sh, after python.sh

# # str.has_newline <STRING / stdin>
function str.has_newline(){
  local string
  if [[ ! "$1" ]] && is_piped; then
    string="$(<&0)"
  else
    string="$1"
    shift || return 1
  fi
  [[ "$string" = *'\n'* || "$string" = *$'\n'* ]]

}

# # str.has_space <STRING / stdin>
# True for space and \t, not \n
function str.has_space(){
  local string
  if [[ ! "$1" ]] && is_piped; then
    string="$(<&0)"
  else
    string="$1"
    shift || return 1
  fi
  # todo: consider:
  #  [[ $string = *[!\ ]* ]]		# has non-space
  #  [[ $string = *[^[:space:]]* ]]
  #  [[ $string = *[$' \t\n']* ]]
  #  or even:
  #  whitespace=$(printf '\n\t '); case "$string" in *[!$whitespace]*)
  #  https://unix.stackexchange.com/a/147109/528898
  if [[ "$string" = *" "* || "$string" = *$(printf '\t')* ]]; then
    return 0
  else
    return 1
  fi
}

# # str.has_wildcard_at_ends <STRING / stdin>
# 0 if starts or ends with '.*'
function str.has_wildcard_at_ends(){
  local string
  if [[ ! "$1" ]] && is_piped; then
    string="$(<&0)"
  else
    string="$1"
    shift || return 1
  fi
  [[ "$string" = ".*"* || "$string" = *".*" ]]
}


function str.is_whitespace(){
	local string
	if [[ ! "$1" ]] && is_piped; then
		string="$(<&0)"
	else
		string="$1"
		shift || return 1
	fi
	[[ "$string" == $'\t' || string == $'\n' || "$string" =~ '^[ \n\v\t\r]*$' ]]
}

# # upper <STRING / stdin>
function upper(){
  if [[ ! "$1" ]]; then
    is_piped && {
      printf "%s" "${(U)$(<&0)}"
      return $?
    }
    log.error "$0 $(docstring "$0"): not enough args"
    return 1
  fi
  printf "%s" "${(U)1}"
  return $?
}

# # lower <STRING / stdin>
function lower(){
  if [[ ! "$1" ]]; then
    is_piped && {
      printf "%s" "${(L)$(<&0)}"
      return $?
    }
    log.error "$0 $(docstring "$0"): not enough args"
    return 1
  fi
  printf "%s" "${(L)1}"
  return $?
}

# # islower <STRING / stdin>
function islower(){
    local string
    if [[ ! "$1" ]] && is_piped; then
      string="$(<&0)"
    else
      string="$1"
      shift
    fi
    [[ "$string" == "$(lower "$string")" ]]
}

# # isupper <STRING / stdin>
function isupper(){
    local string
    if [[ ! "$1" ]] && is_piped; then
      string="$(<&0)"
    else
      string="$1"
      shift
    fi
    [[ "$string" == "$(upper "$string")" ]]
}

# # isnum <VAL>
# true for signed ints. false for floats.
function isnum() {
  [[ "$1" =~ ^[-\+]?[0-9]+$ ]]
}

# # ispathlike <STRING / STDIN> [-f,--file]
# True if STRING is a pathlike string.
# If -f is given, disallow / in the string.
function ispathlike(){
  local source_path
  local pathlike="$(topathlike "$@")"
  local should_confirm=true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      (-*) : ;;
      (*) [[ -n "$source_path" ]] && { 
        log.error "Multiple source paths: $source_path, $1"
        return 1 
      } 
      source_path="$1" ;;
    esac
    shift
  done
  [[ -z "$source_path" ]] && is_piped && source_path="$(<&0)"
  [[ -z "$source_path" ]] && {
    log.error "No source path provided"
    docstring "$0" -p
    return 1
  }
  [[ "$source_path" == "${pathlike}" ]]
}

# # topathlike <STRING / STDIN> [-f,--file] [-l,--lower]
# Replace all characters that are not valid in a path with '-'.
# If -f is given, also remove / from the string.
# If -l is given, also convert the string to lowercase.
function topathlike(){
  # shellcheck disable=SC1112
  local punctuation='\!"#$%&'"'"'()*+,:;<=>?@[\]^`{|}[:cntrl:][:blank:]”“‘’′″״׳_‗ ̲︳ǀ∣❘⏐￨｜＿    ˜∼⁓–—−‒'  # No ~ on purpose.
  local string
  local is_file=false
  local tolower=false
  local -a args
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -f|--file) is_file=true ;;
      -l|--lower) tolower=true ;;
      *) [[ "$string" ]] && {
        log.error "$0: Too many args (expected 0-1, got $#). Usage:\n$(docstring "$0")"
        return 1
      }
      string="$1" ;;
    esac
    shift
  done
  if [[ ! "$string" ]] && is_piped; then
    string="$(<&0)"
  fi
  [[ ! "$string" ]] && {
    log.error "$0: No path given"
    return 1
  }
  if [[ "$is_file" == true ]]; then
    punctuation+='/'
  fi
  
  [[ -o magic_equal_subst && "$string" = "~"* ]] && string="$HOME${string:1}"
  # Replace all characters that are not valid in a path with '-' with param expansion
  
  .cleanup(){
    local _string="$1"
    
    _string="${_string//[${~punctuation}]/-}"
    _string="${_string//--/-}"
    _string="${_string//__/_}"
    _string="${_string//-_/-}"
    _string="${_string//_-/-}"
    _string="${_string//.-/-}"
    _string="${_string//-./-}"
    _string="${_string%%-}"
    _string="${_string##-}"
    
    # Handle cases with more than 2 separators in a row
    if [[ "$1" != "$_string" ]]; then .cleanup "$_string"; return; fi
    printf "%s" "$_string"
  }
  
  local extension="${string##*.}"
  
  local looks_like_extension=false
  [[ "$extension" =~ ^[a-zA-Z0-9]+$ ]] && looks_like_extension=true
  
  
  if [[ "$looks_like_extension" == true ]]; then
    local stem="${string%.*}"
    stem="$(.cleanup "$stem")"
    string="${stem}.${extension}"
  else
    # Assuming it's part of the string, e.g. 'Dr. Seuss'
    string="$(.cleanup "$string")"
  fi
  if [[ "$tolower" == true ]]; then
    string="${(L)string}"
  fi
  printf "%s" "$string"
}

# # is_regex_pattern <STRING>
# Returns 0 if STRING looks like a regex pattern and not a simple glob,
# by checking if if it:
# 1. Starts with ^ or ends with $
# 2. Contains {n}, {n,}, {,m}, {n,m}, or +, *, ? preceded by a character
# 3. Contains [[:digit:]], [[:space:]], [[:alnum:]], [[:punct:]], [[:print:]], [[:graph:]], [[:lower:]], [[:upper:]], [[:alpha:]], [[:ascii:]], [[:cntrl:]], [[:xdigit:]], [[:blank:]]
# 4. Contains [...] or (...)
# 5. Contains \d, \D, \s, \S, \w, \W
function is_regex_pattern(){
  # Requires brew-installed zsh because of the pcre module.
  setopt REMATCH_PCRE  # https://github.com/zthxxx/jovial/issues/12
  local string="$1"
  # Starts with ^ or ends with $
  if [[ "$string" = "^"* || "$string" = *"$" ]]; then
    return 0
  fi

  # Literal common regex patterns
  if [[ "$string" = ?*+* || "$string" = ?*'?'* || "$string" = ?*"*"* || "$string" =~ \{[0-9]+\} || "$string" =~ \{[0-9]+,\} || "$string" =~ \{[0-9]+,[0-9]+\} || "$string" =~ \{,[0-9]+\} ]]; then
    return 0
  fi

  # Literal character classes
  if [[ "$string" == *"[:digit:]"* || "$string" == *"[:space:]"* || "$string" == *"[:alnum:]"* || "$string" == *"[:punct:]"* || "$string" == *"[:print:]"* || "$string" == *"[:graph:]"* || "$string" == *"[:lower:]"* || "$string" == *"[:upper:]"* || "$string" == *"[:alpha:]"* || "$string" == *"[:ascii:]"* || "$string" == *"[:cntrl:]"* || "$string" == *"[:xdigit:]"* || "$string" == *"[:blank:]"* ]]; then
    return 0
  fi

  # Literal [...]
  if [[ "$string" = *\[?*\]* || "$string" = *\(?*\)* ]]; then
    return 0
  fi

  # \d, \D, \s, \S, \w, \W
  if [[ "$string" = *\\[dDsSwW]* ]]; then
    return 0
  fi

  return 1
}

# # str.fill <STRING / stdin> <PAD_TYPE (s/d)> <WIDTH>
# Fills STR with either whitespace (s) or zeroes (d) from the left until it reaches WIDTH.
# If STR's width is already >= WIDTH, returns as-is.
# Examples:
# ```bash
# str.fill 123 s 4  # " 123"
# str.fill 123 d 4  # "0123"
# ```
function str.fill(){
  # TODO: Use zsh typeset -L or -R or -Z
  local string
  local -i width
  local pad_type
  if is_piped && [[ ! "$2" ]]; then
    string="$(<&0)"
    pad_type="$1"
    width="$2"
    shift 2 || {
      log.fatal "$0: Not enough args"
      docstring -p "$0"
      return 1
    }
  else
    string="$1"
    pad_type="$2"
    width="$3"
    shift 3 || {
      log.fatal "$0: Not enough args"
      docstring -p "$0"
      return 1
    }
  fi

  if [[ "$pad_type" != "s" && "$pad_type" != "d" ]] || ! isnum "$width"; then
    log.error "$0: Invalid padding type or width; $(typeset pad_type width)"
    docstring -p "$0"
    return 1
  fi

	local -i string_len=${#string}
	if ((string_len >= width)); then
	  echo -n "$string"
	  return $?
	fi
	if [[ "$pad_type" == "s" ]]; then
	  # Space-padding accounts for the string length; no need to subtract it from the width.
    printf "%${width}s%s" "$string"
    return $?
  fi
  if [[ "$pad_type" == "d" ]]; then
    # 0-padding does not account for the string length, for some reason. We specify the padding length explicitly.
    local -i padding=$((width - string_len))
    printf "%0${padding}d%s" "" "$string"  # Not sure why the first empty string but otherwise it doesn't work.
    return $?
  fi
	log.error "Invalid padding type: $(typeset pad_type)"
	return 1
}

# # str.unquote <STRING / stdin>
function str.unquote(){
	local string
	if [[ ! "$1" ]] && is_piped; then
		string="$(<&0)"
	else
		string="$1"
	fi
	# (q) fails some complex tests, this doesn't
	printf "%s" "$string" | sed -e "s/^'//" -e "s/'$//" -e "s/^\"//" -e "s/\"$//"
}

function str.singlequote(){
	local string
	if [[ ! "$1" ]] && is_piped; then
		string="$(<&0)"
	else
		string="$1"
	fi
	printf "'%s'" "$(str.unquote "$string")"
}

function str.doublequote(){
	local string
	if [[ ! "$1" ]] && is_piped; then
		string="$(<&0)"
	else
		string="$1"
	fi
	printf '"%s"' "$(str.unquote "$string")"
}

# # str.isinglequoted <STRING / stdin>
# Returns whether surrounded by either single or double qoutes
function str.isinglequoted(){
  local string
  if [[ ! "$1" ]] && is_piped; then
    string="$(<&0)"
  else
    string="$1"
  fi
  if [[ "$string" =~ ^\'.*\'$ || "$string" =~ ^\".*\"$ ]]; then
    return 0
  else
    return 1
  fi
}

# # str.count <STRING / stdin> <SEARCH>
function str.count(){
  local string
  if is_piped && [[ ! "$2" ]]; then
    string="$(<&0)"
  else
    string="$1"
    shift || {
			log.fatal "$0: Not enough args (got $#). Usage:\n$(docstring -p "$0")"
	  	return 1
    }
  fi
  local search="$1"
	shift || {
    log.fatal "$0: Not enough args (got $#). Usage:\n$(docstring -p "$0")"
		return 1
	}
	local only_searched_string
  only_searched_string="${string//[^"${(qq)search}"]/}"
  echo "${#only_searched_string}"
}

# # str.repeat_char <CHAR / stdin> <TIMES>
# str.repeat_char X 4  # XXXX
function str.repeat_char(){
  local char
  if is_piped && [[ ! "$2" ]]; then
    char="$(<&0)"
  else
    char="$1"
    shift
  fi
  if [[ ${#char} != 1 ]]; then
    log.error "$0 can repeat a single char, not a full string. Got $(typeset char). Aborting."
    return 1
  fi
  local times="$1"
  shift || return 1
  seq -f '%g' -s '' "$times" | tr '0-9' "$char"
}


# # strip <STRING / stdin>
# Strips surrounding whitespce with var expansion. Keeps whitespace in the middle.
# shellcheck disable=SC2120
function strip(){
	local string
  if [[ ! "$1" ]]; then
    string="$(<&0)"
  else
    string="$1"
    shift || {
      log.error "$0: Not enough args (expected 1, got $#). Usage:\n$(docstring "$0")"
      return 2
    }
  fi
  [[ "$string" ]] || {
    log.error "$0: Not enough args (expected 1, got $#). Usage:\n$(docstring "$0")"
    return 2
  }

	# shellcheck disable=SC2299  # Parameter expansions can't be nested.
	printf "%s" "${${string##[\\n ]##}%%[\\n ]##}"
}

# # stomp <text / stdin>
# Replaces newlines with spaces, and squeezes all repeated spaces to a single space.
function stomp(){
  local text
  if [[ ! "$1" ]] && is_piped; then
    text="$(<&0)"
  else
    text="$1"
    shift || { log.error "$0: Not enough args (expected 1, got ${#$}). Usage:\n$(docstring "$0")"; return 2; }
  fi
  [[ "$text" ]] || { log.error "$0: Not enough args (expected 1, got ${#$}). Usage:\n$(docstring "$0")"; return 2; }
  text="${text//[$'\n']/ }"
  text="${text//[$'\t']/ }"
  while [[ "$text" = *'  '* ]]; do
    text="${text//  / }"
  done
  strip "$text"
}

# # shorten <STRING / stdin> [[-m ]MAX_LENGTH (Default: $COLUMNS or 120)]
# Show beginning and end of string with ellipsis in between if longer than MAX_LENGTH chars.
# Use -m to avoid ambiguity.
function shorten(){
	setopt localoptions force_float
  local string
  local -i UNSPECIFIED=-1
	local -i max_length="$UNSPECIFIED"
  local -i default_max_length=${COLUMNS:-120}
  
  local -a args
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --max-length=*) max_length="${1#*=}"; shift; continue;;
      -m|--max-length) max_length="$2" ; shift 2 ; continue ;;
    esac
    if [[ -z "$string" ]]; then
      string="$1"
      shift
      continue
    fi
    if [[ "$max_length" = "$UNSPECIFIED" ]]; then
      max_length="$1"
      shift
      continue
    fi
    log.error "$0: Too many arguments. Current=$1\n$(typeset string max_length)\nUsage:\n$(docstring "$0")"
    return 1
  done
  [[ "$max_length" == "$UNSPECIFIED" ]] && max_length="$default_max_length"
  [[ -z "$string" ]] && is_piped && string="$(<&0)"
  [[ -z "$string" ]] && {
    log.error "$0: Not enough args.\n$(typeset string max_length)\nUsage:\n$(docstring "$0")"
    return 2
  }
	
  
  local -i str_length=${#string}
	# Return as-is if the string length <= max_length
	[[ "$str_length" -le "$max_length" ]] && {
		print -- "$string"
		return 0
	}
  local -i max_prefix_length=$(((max_length-7)*(2/3)))
	local -i max_suffix_length=$(((max_length-7)*(1/3)))
	# shellcheck disable=SC2079
	local -i prefix_length=$(((str_length*1.5) - 7 < max_prefix_length ? str_length : max_prefix_length))
	local -i suffix_length=$(((str_length*3) - 7 < max_suffix_length ? str_length : max_suffix_length))
	local prefix="${string[1,${prefix_length}]}"
	local rsuffix_length="$((-suffix_length))"
	local suffix="${string[${rsuffix_length},-1]}"
	if [[ "$string" == *$'\n'* || "$suffix" == *$'\n'* ]]; then
		print -- "${prefix}\n[...]\n${suffix}"
	else
		print -- "${prefix} [...] ${suffix}"
	fi
}

# # shortarr <ARRAY_TYPESET_EXPRESSION / ITEM...> [-m, --max-length=MAX_LENGTH (Default: $COLUMNS or 120)] [-d, --delimiter=DELIMITER (Default: " ")]
# Shortens each item in the array to MAX_LENGTH chars.
# Prints the result in the form of `("shortened_item1" "shortened_item2")`.
# If only one item is passed, assumes the caller passes an array in the form of `shortarr 'array_name=("item1" "item2")'`, e.g. via `shortarr "$(typeset array_name)"`.
# This is crucial to tell apart separate items, even if each is multi-line, within the array.
# If multiple items are passed, handles them as distinct array items.
function shortarr(){
  local -i UNSPECIFIED=-1
  local -i max_length="$UNSPECIFIED"
  local delimiter=" "
  local -a args
  local literal_typeset_expression
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --max-length=*) max_length="${1#*=}";;
      -m|--max-length) max_length="$2" ; shift ;;
      --delimiter=*) delimiter="${1#*=}";;
      -d|--delimiter) delimiter="$2" ; shift ;;
      *) args+=("$1");;
    esac
    shift
  done
  [[ "$delimiter" = "$UNSPECIFIED" ]] && delimiter=" "
  local -a array
  if [[ "${#args[@]}" -eq 1 ]]; then
    literal_typeset_expression="${args[1]}"
    local array_name="${literal_typeset_expression%%=*}"
    array=(${(P)array_name})
  else
    array=( "${args[@]}" )
  fi
  local -a shortened_array=()
  local item shortened_item
  printf "%s=(" "$array_name"
  for item in ${array[@]}; do
    shortened_item="$(shorten "$item" -m "$max_length")"
    # shellcheck disable=SC2300
    printf "${delimiter}%s" "${$(typeset shortened_item)#*=}"
    shortened_array+=("$shortened_item")
  done
  # shellcheck disable=SC2059  # Using %s prints the '\n' literally for some reason.
  printf "${delimiter})\n"
}


# # dedent <stdin / string>
function dedent(){
  local string
  if [[ ! "$1" ]] && is_piped; then
    string="$(<&0)"
  else
    string="$1"
  fi
  [[ "$string" ]] || { log.error "$0: Not enough args. Usage:\n$(docstring "$0")"; return 2; }

  py.print -s 'from textwrap import dedent' 'dedent(stdin.replace("\t", "    "))' <<< "$string"
}

# # indent <STRING / stdin> <INDENT=2>
# Indent the string by the given number of spaces. Defaults to 2.
function indent(){
  local string
  local -i indent_length
  if is_piped; then
    if [[ "$2" ]]; then
      log.error "$0: Too many args (expected 0-1, got 2). Usage:\n$(docstring "$0")"
      return 1
    elif [[ "$1" ]]; then
      string="$(<&0)"
      indent_length="$1"
    else
      string="$(<&0)"
      indent_length=2
    fi
  else
    [[ "$1" ]] || { log.error "$0: Not enough args (expected 1-2, got 0). Usage:\n$(docstring "$0")"; return 1; }
    string="$1"
    indent_length="${2:-2}"
  fi

  py.print -s 'from textwrap import indent' "indent(stdin.replace('\t', '    '), ' ' * ${indent_length})" <<< "$string"
}

# # deunicode <STRING / stdin>
# Removes all non-ASCII characters from the string.
function deunicode() {
  local string
  if [[ ! "$1" ]] && is_piped; then
    string="$(<&0)"
  else
    string="$1"
  fi
  printf "%s" "${string//[^[:ascii:]]/}"
}

# # nuldelim <STDIN...>
# Replaces newlines, tabs, and spaces with NULs.
# If the input already contains a NUL, does nothing.
# If the input contains at least one newline, replaces newlines with NULs.
# Otherwise, replaces tabs and spaces with NULs.
# Examples:
# ```bash
# ❯ printf "foo bar baz"     | nuldelim  # foo\0bar\0baz
# ❯ printf "foo\nbar\nbaz\n" | nuldelim  # foo\0bar\0baz
# ❯ printf "foo\0bar\0baz"   | nuldelim  # unchanged
# ```
# To check if works:
# `printf "hi\nbye" | nuldelim | xargs -0 | nuldelim | xargs -0 -n1 | nuldelim | nuldelim | xargs -0 -n1`
# shellcheck disable=SC2120
function nuldelim() {
  [[ "$1" ]] && { log.error "Does not take args. Usage:\n$(docstring "$0")"; return 1; }
  local s
  s="$(<&0)"
  
  # If it already contains a NUL, do nothing.
  if [[ "$s" == *$'\0'* ]]; then
    printf "%s" "$s"
  
  # If it contains at least one newline, replace newlines with NULs
  elif [[ "$s" == *$'\n'* ]]; then
    printf "%s" "${s//$'\n'/"$(printf '\0')"}"
  
  # Otherwise, replace tabs (\11) and spaces (\40) with NULs
  else
    printf "%s" "${s//[$'\11'$'\40']/"$(printf '\0')"}"
  fi
}

# # join <STDIN/STRING> DELIMITER
# Joins the input lines with the given delimiter.
# Example: `join "$(<lines.txt)" ' '`
function join(){
  local string
  local delimiter
  case "${#@}" in
    0) log.error "$0: No arguments specified. Usage:"
       docstring "$0"
       return 1
       ;;
    1) is_piped || {
         log.error "$0: Stdin is inaccessible, and only one argument was provided. Usage:"
         docstring "$0"
         return 1
       }
      string="$(<&0)" ; delimiter="$1" ;;
    2) string="$1" ; delimiter="$2" ;;
    *)  log.error "$0: Too many arguments. Usage:"
        docstring "$0"
        return 1
        ;;
  esac
  
  # shellcheck disable=SC2059,SC2300
  printf "%s" "${$(nuldelim <<< "$string")//$'\0'/${delimiter}}"
  
}

# # xmlwrap <CONTENT,STDIN,FILEPATH> -t,--tag,-st,--stdin-tag TAG [-q,--quiet]
# Wraps the string in XML tags.
function xmlwrap(){
	local content tag formatted_content
	local quiet=false
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--tag=*|--stdin-tag=*) tag="${1#*=}" ;;
			-t|--tag|-st|--stdin-tag) tag="$2" ; shift ;;
			-q|--quiet) quiet=true ;;
			*) content="$1" ;;
		esac
		shift
	done
  [[ ! "$tag" ]] && { log.error "No tag provided." ; return 1 ; }
	local piped=false
	is_piped && piped=true
	[[ ! "$content" && $piped = false ]] && { log.error "No content provided." ; return 1 ; }
	[[ "$quiet" = false && "$content" && $piped = true ]] && log.warn "Ignoring piped content because content was also provided positionally."
	[[ ! "$content" && $piped = true ]] && content="$(<&0)"
	
	[[ -f "$content" ]] && content="$(<"$content")"
	
  local tag_space_separated="${tag//_/ }"
  local tag_underscores_separated="${tag// /_}"
  formatted_content="$(printf "<${tag_underscores_separated}>\n%s\n</${tag_underscores_separated}>\n" "$content")"
	[[ "$quiet" = false ]] && log.debug "$(shorten "$formatted_content" -m "$COLUMNS")"
	print -r -- "$formatted_content"
}

# # codeblock <STRING / stdin>
# Extracts the first code block from the string.
function codeblock(){
  local string
  if [[ ! "$1" ]] && is_piped; then
    string="$(<&0)"
  else
    string="$1"
  fi
  [[ "$string" ]] || { log.error "$0: Not enough args. Usage:\n$(docstring "$0")"; return 2; }
  awk '/^```/{p=!p;next} p' <<< "$string"
}