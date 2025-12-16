#!/usr/bin/env bash
#########################################################################
# Create a test file to trigger the function app.
# Globals:
#   ENVIRONMENT
#   LOCATION
# Optional Globals:
#   APP_STORAGE_CONTAINER
#   APP_STORAGE_INPUT_PATH
#########################################################################
# Stop on errors
set -e

# Environment variables
if [ -z "$APP_STORAGE_CONTAINER" ]; then
    APP_STORAGE_CONTAINER="pipeline-files"
fi
if [ -z "$APP_STORAGE_INPUT_PATH" ]; then
    APP_STORAGE_INPUT_PATH="incoming"
fi
if [ -z "$ENVIRONMENT" ]; then
    ENVIRONMENT="dev"
fi
if [ -z "$LOCATION" ]; then
    LOCATION="westus3"
fi


# Globals
project_root="$(git rev-parse --show-toplevel)"
short_name=$(grep -oP '(?<=^short_name = ")[^"]+' "${project_root}/pyproject.toml"  | tr -d '\n')
short_env=$(echo "${ENVIRONMENT:0:1}" | tr '[:upper:]' '[:lower:]')

# Variables
base_name="${short_name}-${ENVIRONMENT}-${LOCATION}"
rg_name="rg-${base_name//_/-}"
app_storage_account_name="st${short_name}primary${short_env}"
app_storage_account_name=$(echo "$app_storage_account_name" | tr '[:upper:]' '[:lower:]')
app_storage_account_name="${app_storage_account_name//[^a-z0-9]/}"
app_storage_account_name="${app_storage_account_name:0:24}"

# Create test file
epoch_time=$(date +%s)
timestamp=$(date -u -d "@${epoch_time}" +'%Y%m%d%H%M%SZ')
test_file="test_job_config_${timestamp}.json"
touch "$test_file"
jq -n \
    --arg runtime_config "/mnt/azurefiles/runtime-config.json" \
    --arg export_config "/mnt/azurefiles/input/file2.txt" \
    --arg stats_config "/mnt/azurefiles/stats-config.json" \
    --arg log_file "/path/to/log" \
    --arg timestamp "${timestamp}" \
  '{
    env_vars: [
      {name: "APP_RUNTIME_CONFIG_FILE", value: $runtime_config},
      {name: "APP_EXPORT_CONFIG_FILE", value: $export_config},
      {name: "APP_STATS_CONFIG_FILE", value: $stats_config},
      {name: "APP_LOG_FILE", value: $log_file}
    ],
    files: [
      "path/to/secondary_source/file",
      ("incoming/test_job_config_" + $timestamp + ".json"),
      "incoming/emptyfile"
    ]
  }' > "${test_file}"

# Validate test file
jq -n \
    --arg runtime_config "/mnt/azurefiles/runtime-config.json" \
    --arg export_config "/mnt/azurefiles/input/file2.txt" \
    --arg stats_config "/mnt/azurefiles/stats-config.json" \
    --arg log_file "/path/to/log" \
    --arg timestamp "${timestamp}" \
  '{
    env_vars: [
      {name: "APP_RUNTIME_CONFIG_FILE", value: $runtime_config},
      {name: "APP_EXPORT_CONFIG_FILE", value: $export_config},
      {name: "APP_STATS_CONFIG_FILE", value: $stats_config},
      {name: "APP_LOG_FILE", value: $log_file}
    ],
    files: [
      ("incoming/test_job_config_" + $timestamp + ".json")
    ]
  }' > "${test_file}"

echo "Get storage key for: $app_storage_account_name" >&2
app_storage_key=$(az storage account keys list \
        --account-name "$app_storage_account_name" \
        --resource-group "$rg_name" \
        --query "[0].value" -o tsv)

az storage blob upload \
    --container-name "$APP_STORAGE_CONTAINER" \
    --file "$test_file" \
    --name "${APP_STORAGE_INPUT_PATH}/${test_file}" \
    --account-name "$app_storage_account_name" \
    --account-key "$app_storage_key"

# rm "$test_file"

echo "Uploaded test test file."
