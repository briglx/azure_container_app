#!/bin/bash

# Enable strict mode.
set -euo pipefail

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
format_print "APP_RUNTIME_CONFIG_FILE = ${APP_RUNTIME_CONFIG_FILE:-undefined}"
format_print "APP_EXPORT_CONFIG_FILE = ${APP_EXPORT_CONFIG_FILE:-undefined}"
format_print "APP_LOG_FILE = ${APP_LOG_FILE:-undefined}"
format_print ""

if [ "$1" = "debug" ]; then
    format_print "Debug mode enabled, starting bash shell..."
    exec /bin/bash
fi

format_print "Verify application..."
format_print "${APP_FILE} -help"
${APP_FILE} -help | head -n 1
format_print ""

format_print "Watch log file..."
tail -n 0 -f "$APP_LOG_FILE" | tee -a "/mnt/azurefiles/log_${build_number}.log" >&2 &
sleep 5

# format_print "Build runtime args..."
APP_RUNTIME_ARGS_STRING=$(./build_args.sh "$APP_RUNTIME_CONFIG_FILE")
RUNTIME_ARGS_WITH_FILENAME="${APP_RUNTIME_ARGS_STRING//__OUTPUT__/output_${build_number}.acgd}"

eval "set -- $RUNTIME_ARGS_WITH_FILENAME"
APP_RUNTIME_ARGS_ARRAY=("$@")

printf 'Parsed %d args:\n' "${#APP_RUNTIME_ARGS_ARRAY[@]}"
printf '  [%s]\n' "${APP_RUNTIME_ARGS_ARRAY[@]}"

format_print "Starting batch run..."
format_print "$APP_FILE ${APP_RUNTIME_ARGS_ARRAY[*]}"
"$APP_FILE" "${APP_RUNTIME_ARGS_ARRAY[@]}" 2>&1

format_print "Export data to file..."

format_print "Build export args..."
APP_EXPORT_ARGS_STRING=$(./build_args.sh "$APP_EXPORT_CONFIG_FILE")
EXPORT_ARGS_WITH_FILENAME="${APP_EXPORT_ARGS_STRING//__OUTPUT__/output_${build_number}.acgd}"
EXPORT_ARGS_WITH_FILENAME="${EXPORT_ARGS_WITH_FILENAME//__EXPORT__/export_${build_number}.txt}"

eval "set -- $EXPORT_ARGS_WITH_FILENAME"
EXPORT_ARGS_ARRAY=("$@")

printf 'Parsed %d args:\n' "${#EXPORT_ARGS_ARRAY[@]}"
printf '  [%s]\n' "${EXPORT_ARGS_ARRAY[@]}"

format_print "$APP_FILE ${EXPORT_ARGS_ARRAY[*]}"
"$APP_FILE" "${EXPORT_ARGS_ARRAY[@]}" 2>&1

format_print "Copy file to share."
format_print "cp export_${build_number}.txt /mnt/azurefiles/scoredata/export_${build_number}.txt"
cp "export_${build_number}.txt" "/mnt/azurefiles/scoredata/export_${build_number}.txt"
