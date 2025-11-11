#!/usr/bin/env bash
#########################################################################
# Deterministic CMDB-style Application Service Number Generator
# Usage: generate_app_service_number.sh
# Globals:
#########################################################################

# Stop on errors
set -e

project_root="$(git rev-parse --show-toplevel)"
project_name=$(grep -oP '(?<=^name = ")[^"]+' "${project_root}/pyproject.toml"  | tr -d '\n')
project_version=$(grep -oP '(?<=^version = ")[^"]+' "${project_root}/pyproject.toml"| tr -d '\n')

echo  "Creating app number for: ${project_name} ${project_version}" >&2

NAME_UPPER=$(echo "$project_name" | tr '[:lower:]' '[:upper:]' | sed 's/[^A-Z0-9]//g')
VER_UPPER=$(echo "$project_version" | tr '[:lower:]' '[:upper:]' | sed 's/[^A-Z0-9]//g')

echo "Normalized name: ${NAME_UPPER}${VER_UPPER}" >&2

resource_token=$(echo -n "${NAME_UPPER}${VER_UPPER}" | sha1sum | awk '{print $1}' | cut -c1-8)

echo "Resource token: ${resource_token}" >&2

run_date=$(date +%Y%m%d)

echo "APP${run_date}${resource_token}"
