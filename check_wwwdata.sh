#!/usr/bin/env bash

function permission() {

if [[ $(find ${APP_DOCROOT} ! -perm 755 -type d | wc -l) -gt 0 ]] || [[ $(find /html ! -perm 644 -type f | wc -l) -gt 0 ]]; then
    echo "ERROR: There are permissions issues with directories and/or files within ${APP_DOCROOT}"
    exit 1
 else
    echo "OK: Permissions 755 (dir) and 644 (files) look correct on ${APP_DOCROOT}"
fi

}

function owner() {

if [[ $(find ${APP_DOCROOT} ! -user www-data | wc -l) -gt 0 ]]; then
    echo "ERROR: Incorrect user:group are set within ${APP_DOCROOT}"
    exit 1
 else
    echo "OK: www-date (user:group) ownership looks corect on ${APP_DOCROOT}"
fi

}

"$@"
