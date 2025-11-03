#!/bin/bash

# Enable strict mode.
set -euo pipefail

SCRIPT_PATH=$(dirname $(realpath -s "$0"))
build_number=$(date +%Y%m%dT%H%M)

format_print () {
    echo "$(date -uIns) | entrypoint | $1"
}

echo "$(date -uIns) - entrypoint.sh $*"

format_print ""
format_print "######################################################"
format_print "Runtime Information - Build ENVS"
format_print "######################################################"
format_print ""
format_print "RELEASE_VERSION = ${RELEASE_VERSION:-undefined}"
format_print "APP_INSTALLER_FILE = ${APP_INSTALLER_FILE:-undefined}"
format_print "APP_FILE = ${APP_FILE:-undefined}"
format_print "APP_SETUP_ARGS = ${APP_SETUP_ARGS:-undefined}"
format_print "APP_ALIAS = ${APP_ALIAS:-undefined}"
format_print ""
format_print "######################################################"
format_print "Runtime Information - Instance ENVS"
format_print "######################################################"
format_print ""
format_print "APP_RUNTIME_ARGS = ${APP_RUNTIME_ARGS:-undefined}"
format_print "APP_EXPORT_ARGS = ${APP_EXPORT_ARGS:-undefined}"
format_print "APP_LOG_FILE = ${APP_LOG_FILE:-undefined}"
format_print ""

format_print "Verify application..."
format_print "${APP_FILE} -help"
${APP_FILE} -help
format_print ""

format_print "Watch log file..."
tail -n 0 -f "$APP_LOG_FILE" >&2 &

format_print "Starting batch run..."
RUNTIME_ARGS_WITH_FILENAME="${APP_RUNTIME_ARGS//__OUTPUT__/output_${build_number}.acgd}"
format_print "$APP_FILE $RUNTIME_ARGS_WITH_FILENAME"
read -r -a ARGS_ARRAY <<< "$RUNTIME_ARGS_WITH_FILENAME"
"$APP_FILE" "${ARGS_ARRAY[@]}" 2>&1

format_print "Export data to file..."
EXPORT_ARGS_WITH_FILENAME="${APP_EXPORT_ARGS//__OUTPUT__/output_${build_number}.acgd}"
EXPORT_ARGS_WITH_FILENAME="${EXPORT_ARGS_WITH_FILENAME//__EXPORT__/export_${build_number}.txt}"
format_print "$APP_FILE $EXPORT_ARGS_WITH_FILENAME"
read -r -a EXPORT_ARGS_ARRAY <<< "$EXPORT_ARGS_WITH_FILENAME"
"$APP_FILE" "${EXPORT_ARGS_ARRAY[@]}" 2>&1

format_print "Copy file to share."
format_print "cp export_${build_number}.txt /mnt/azurefiles/scoredata/export_${build_number}.txt"
cp "export_${build_number}.txt" "/mnt/azurefiles/scoredata/export_${build_number}.txt"
format_print ""

format_print "Waiting to allow for interactive shell..."
tail -f /dev/null
