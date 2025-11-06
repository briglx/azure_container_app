#!/usr/bin/env bash
#######################################################################################
# Build a command-line arg string in the form --key value from parsing a flat JSON file
# Globals: None
#######################################################################################

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 /path/to/config.json"
  exit 1
fi

CONFIG_FILE="$1"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Config file '$CONFIG_FILE' not found."
  exit 1
fi

ARGS=$(jq -r '
  to_entries
  | map(
      if .value == "" then
        "-" + .key
      else
        "-" + .key + " " + (.value | tostring | @sh)
      end
    )
  | join(" ")
' "$CONFIG_FILE")

echo "$ARGS"
