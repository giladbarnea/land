#!/usr/bin/env bash

################################################################################
# BitBucket
################################################################################

function bb.view.pr(){
  local pr_number
  local file
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -f|--file) file="$2"; shift 2;;
      *)
        if [[ "$pr_number" ]]; then
          log.fatal "too many positional arguments: $1"
          return 1
        fi
        pr_number="$1"
        shift 1 ;;
    esac
  done
  if [[ ! "$pr_number" ]]; then
    log.fatal "not enough positional arguments, expects at least 1"
    return 1
  fi
  local url="https://bitbucket.<domain>/projects/<project>/repos/<repo>/pull-requests/${pr_number}"
  if [[ "$file" ]]; then
    url+="/diff#${file}"
  fi
  background xdg-open "$url"
}


function bb.view.compare(){
  local target="$1"
  local source="$2"
  shift 2 || return 1
  [[ "$target" =~ ^[a-f0-9]{10,32}$ ]] || target="refs/heads/$target"
  [[ "$source" =~ ^[a-f0-9]{10,32}$ ]] || source="refs/heads/$source"

  local url="https://bitbucket.<domain>/projects/<project>/repos/<repo>/compare/diff?targetBranch=${target}&sourceBranch=${source}&targetRepoId=182"
  background xdg-open "$url"
}

function bb.view.commit(){
  local commit="$1"
  shift 1 || return 1

  local url="https://bitbucket.<domain>/projects/<project>/repos/<repo>/commits/$commit"
  background xdg-open "$url"
}

function bb.view.branch(){
  local branch="${1//\//%2F}"
  shift 1 || return 1

  local url="https://bitbucket.<domain>/projects/<project>/repos/<repo>/branches?base=refs%2Fheads%2F${branch}"
  background xdg-open "$url"
}

function bb.browse.branch(){
  local branch="${1//\//%2F}"
  shift 1 || return 1

  local url="https://bitbucket.<domain>/projects/<project>/repos/<repo>/browse?at=refs%2Fheads%2F${branch}"
  background xdg-open "$url"
}


function bb.view.tag(){
  local tag="${1//\//%2F}"
  shift 1 || return 1

  local url="https://bitbucket.<domain>/projects/<project>/repos/<repo>/branches?base=${tag}"
  background xdg-open "$url"
}

function bb.browse.tag(){
  local tag="${1//\//%2F}"
  shift 1 || return 1

  local url="https://bitbucket.<domain>/projects/<project>/repos/<repo>/browse?at=refs%2Ftags%2F${tag}"
  background xdg-open "$url"
}