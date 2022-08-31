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

if [ -d "/mnt/code/www/moodle_sand" ]
then
    msg "Purging existing sandbox..."
    sudo /rlscripts/moodle/moodle_purge -f /mnt/code/www/moodle_sand &> /dev/null
else
    msg "Purging existing sandbox..."
    sudo mkdir /mnt/code/www/moodle_sand
    sudo /rlscripts/moodle/moodle_purge -f /mnt/code/www/moodle_sand &> /dev/null
fi

msg "Purging any leftover sandbox directories just in case..."
sudo rm -rf /mnt/code/www/moodle_sand &> /dev/null
sudo rm -rf /mnt/data/moodledata_sand &> /dev/null

msg "Cloning production code to sandbox code directory..."
rsync -avv /mnt/code/www/moodle_prod/ /mnt/code/www/moodle_sand &> /dev/null

msg "Changing wwwroot in sandbox config.php file..."
prodwwwroot=$(/rlscripts/moodle/moodle_list -p wwwroot | head -n 1)
prodwwwroot+="/sandbox"
sudo sed -i "s#CFG->wwwroot = .*#CFG->wwwroot = '$prodwwwroot';#" /mnt/code/www/moodle_sand/config.php

msg "Syncing production data to sandbox..."
sudo /rlscripts/moodle/moodle_sandbox_refresh_data --dirsrc=/mnt/data/moodledata_prod --dirdest=/mnt/data/moodledata_sand --excludes=sessions,cache,localcache,muc,lock -y &> /dev/null

msg "Creating sandbox database..."
sudo mysqladmin create moodle_sand &> /dev/null

msg "Optimizing production database..."
sudo mysqlcheck -o moodle_prod &> /dev/null

msg "Syncing production database to sandbox without logstore and grade history..."
sudo bash -c "sudo mysqldump -v moodle_prod --no-data --max-allowed-packet=1073741824 | sudo mysql moodle_sand && sudo mysqldump --max-allowed-packet=1073741824 -v moodle_prod --no-create-info --ignore-table=moodle_prod.mdl_logstore_standard_log --ignore-table=moodle_prod.mdl_grade_grades_history --ignore-table=moodle_prod.mdl_grade_items_history | sudo mysql moodle_sand" &> /dev/null

msg "Fixing sandbox permissions..."
sudo /rlscripts/moodle/moodle_fix_permissions /mnt/code/www/moodle_sand &> /dev/null

msg "Purging sandbox caches..."
sudo -u apache nice php -d opcache.enable_cli=0 /mnt/code/www/moodle_sand/admin/cli/purge_caches.php &> /dev/null