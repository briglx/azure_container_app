#!/bin/bash

# Enable strict mode.
set -euo pipefail

SCRIPT_PATH=$(dirname $(realpath -s "$0"))


format_print () {
    echo "$(date -uIns) | entrypoint | $1"
}

echo "$(date -uIns) - entrypoint.sh $*"

format_print ""
format_print "######################################################"
format_print "Runtime Information"
format_print "######################################################"
format_print ""
format_print "RELEASE_VERSION = ${RELEASE_VERSION:-undefined}"
format_print "APP_FILE = ${APP_FILE:-undefined}"
format_print ""
format_print "${APP_FILE} -help"
${APP_FILE} -help
format_print ""

format_print "Waiting for 10 minutes to allow for inspection..."
sleep 600
