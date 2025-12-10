#!/usr/bin/env bash
#########################################################################
# Deploy function app resources on cloud infrastructure.
# Usage: devops_provision_func_app.sh
# Globals:
#   SUBSCRIPTION_ID
#   ENVIRONMENT
#   LOCATION
# Optional Globals:
# Params
#    -k, shared_key_vault_name
#    -s, APP_STORAGE_CONNECTION
#    -c, APP_STORAGE_CONTAINER
#    -i, APP_STORAGE_INPUT_PATH
#    -o, APP_STORAGE_OUTPUT_PATH
#########################################################################

# Stop on errors
set -e

# Parameters
while getopts "k:s:c:i:o:" opt; do
  case $opt in
    k)
        shared_key_vault_name="$OPTARG"
        ;;
    s)
        app_storage_connection="$OPTARG"
        ;;
    c)
        app_storage_container="$OPTARG"
        ;;
    i)
        app_storage_input_path="$OPTARG"
        ;;
    o)
        app_storage_output_path="$OPTARG"
        ;;
    *)
      echo "Usage: $0 -k shared_key_vault_name"
      exit 1
      ;;
  esac
done

project_root="$(git rev-parse --show-toplevel)"
env_file="${project_root}/.env"
project_name=$(grep -oP '(?<=^name = ")[^"]+' "${project_root}/pyproject.toml"  | tr -d '\n')
short_name=$(grep -oP '(?<=^short_name = ")[^"]+' "${project_root}/pyproject.toml"  | tr -d '\n')
resource_token=$(echo -n "${SUBSCRIPTION_ID}${project_name}${LOCATION}" | sha1sum | awk '{print $1}' | cut -c1-8)
short_env=$(echo "${ENVIRONMENT:0:1}" | tr '[:upper:]' '[:lower:]')
tags="asn=tbd project=$project_name owner=tbd environment=$ENVIRONMENT servicetier=tier3"

isa_date_utc=$(date -u +'%Y-%m-%dT%H:%M:%SZ')

base_name="${short_name}-${ENVIRONMENT}-${LOCATION}"
rg_name="rg-${base_name//_/-}"

funcapp_storage_account_name="st${short_name}func${short_env}"
funcapp_storage_account_name=$(echo "$funcapp_storage_account_name" | tr '[:upper:]' '[:lower:]')
funcapp_storage_account_name="${funcapp_storage_account_name//[^a-z0-9]/}"
funcapp_storage_account_name="${funcapp_storage_account_name:0:24}"

application_insights_name="appi-${short_name}-${short_env}-${resource_token}"

funcapp_name="func-${short_name}-${short_env}-${resource_token}"
funcapp_name="${funcapp_name:0:24}"


#  Storage account is used to store important app data, sometimes including the application code itself. You should limit access from other apps and users to the storage account.
echo "Creating Function App Storage Account: $funcapp_storage_account_name"

set +e
resource=$(az storage account show --name "$funcapp_storage_account_name" --only-show-errors 2>/dev/null)
exit_code=$?
set -e

if [[ $exit_code -eq 0 && -n "$resource" ]]; then
    echo "$funcapp_storage_account_name already exists" >&2
    func_app_storage_name=$(jq -r '.name' <<< "$resource")
else
    results=$(az storage account create \
        --name "$funcapp_storage_account_name" \
        --location "$LOCATION" \
        --resource-group "$rg_name" \
        --sku Standard_LRS \
        --allow-blob-public-access false \
        --tags "$tags")
    func_app_storage_name=$(echo "$results" | jq -r '.name')
fi

if [ -z "$shared_key_vault_name" ]; then
    echo "Error: shared_key_vault_name is not set." >&2
    exit 1
fi

# Read log_analytics_id from key vault
echo "Retrieving Log Analytics Workspace ID from Key Vault: $shared_key_vault_name"
log_analytics_id=$(az keyvault secret show \
    --name "SharedLogAnalyticsId" \
    --vault-name "$shared_key_vault_name" \
    --query "value" \
    -o tsv)

# App insights
echo "Creating Application Insights: $application_insights_name"
results=$(az monitor app-insights component create \
    --app "$application_insights_name" \
    --location "$LOCATION" \
    --resource-group "$rg_name" \
    --workspace "$log_analytics_id" \
    --application-type web \
    --tags "$tags")
# APPLICATION_INSIGHTS_ID=$(echo "$results" | jq -r '.id')
application_insights_key=$(echo "$results" | jq -r '.instrumentationKey')

# Function App
echo "Creating Function App: $funcapp_name"

set +e
resource=$(az functionapp show --name "$funcapp_name" --resource-group "$rg_name" --only-show-errors 2>/dev/null)
exit_code=$?
set -e

if [[ $exit_code -eq 0 && -n "$resource" ]]; then
    echo "$funcapp_name already exists" >&2
else

    az functionapp create \
        --resource-group "$rg_name" \
        --name "$funcapp_name" \
        --storage-account "$func_app_storage_name" \
        --flexconsumption-location "$LOCATION" \
        --runtime python \
        --runtime-version 3.12 \
        --os-type Linux \
        --app-insights "$application_insights_name" \
        --app-insights-key "$application_insights_key" \
        --workspace "$log_analytics_id" \
        --functions-version 4 \
        --instance-memory 2048 \
        --https-only true \
        --tags "$tags"
fi

# Configure Function App Application Settings
echo "Configuring Function App Application Settings"
az functionapp config appsettings set \
    --name "$funcapp_name" \
    --resource-group "$rg_name" \
    --settings \
        "APP_STORAGE_CONNECTION=$app_storage_connection" \
        "APP_STORAGE_CONTAINER=$app_storage_container" \
        "APP_STORAGE_INPUT_PATH=$app_storage_input_path" \
        "APP_STORAGE_OUTPUT_PATH=$app_storage_output_path"


# Deploy Function App Code
echo "Deploying Function App Code"
source_folder="${project_root}/functions"
destination_dir="${project_root}/.dist"
timestamp=$(date -u +'%Y%m%d%H%M%SZ')
zip_file_name="${short_name}_functions_${ENVIRONMENT}_${timestamp}.zip"
zip_file_path="${destination_dir}/${zip_file_name}"

# Create the destination directory if it doesn't exist
mkdir -p "$(dirname "$zip_file_path")"

pushd "$source_folder"

zip -r "$zip_file_path" ./*.py host.json requirements.txt

az functionapp deployment source config-zip \
    --src "$zip_file_path" \
    --name "$funcapp_name" \
    --resource-group "$rg_name" \
    --build-remote true \
    --timeout 120

popd

# Get function key
echo "Retrieving functionapp Key to test: event_grid_trigger"
func_key_master=$(az functionapp keys list \
    --name "$funcapp_name" \
    --resource-group "$rg_name" \
    --query "masterKey" \
    -o tsv)

echo "Retrieving Function Key for function: event_grid_trigger"
func_key=$(az functionapp keys list \
    --name "$funcapp_name" \
    --resource-group "$rg_name" \
    --query "systemKeys.eventgrid_extension" \
    -o tsv)

# Save output variables to .env file
echo "Save output variables to ${env_file}" >&2
{
    echo ""
    echo "# devops_provision_func_app.sh Provision output variables"
    echo "# Generated on ${isa_date_utc}"
    echo "FUNC_APP_NAME=$funcapp_name"
    echo "FUNC_NAME=event_grid_trigger"
    echo "FUNC_KEY_MASTER=\"$func_key_master\""
    echo "FUNC_KEY=\"$func_key\""
}>> "$env_file"
