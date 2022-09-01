#!/usr/bin/env bash

set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT

cleanup() {
  trap - SIGINT SIGTERM ERR EXIT
  # script cleanup here
}

msg() {
  echo >&2 -e "${1-}"
}

die() {
  local msg=$1
  local code=${2-1} # default exit status 1
  msg "$msg"
  exit "$code"
}

# Script logic begin

codedir=$1
gitbranch=$2
filename="dirlist.txt"
    
# Get list of subdirectories with .git folders (external plugins)
sudo find $codedir -name ".git" -type d > $filename

while read line; do
# Change directory and move one down. 
cd $line && cd ..
# Checkout branch specified by user.
sudo git fetch origin && git checkout -b $gitbranch origin/$gitbranch
done < $filename