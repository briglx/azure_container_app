#!/usr/bin/env bash
#########################################################################
# Onboard and manage application on cloud infrastructure.
# Usage: devops_provision.sh 
# Globals:
#   SUBSCRIPTION_ID
#   ENVIRONMENT
#   LOCATION
#   KEY_VAULT_NAME
# Optional Globals:
#   APP_STORAGE_CONTAINER
#   APP_STORAGE_KEY
#   APP_STORAGE_INPUT_PATH
#   APP_STORAGE_OUTPUT_PATH
# Params
#    -d, Debug mode
#########################################################################

# Stop on errors
set -e

# Validate required environment variables
if [ -z "$SUBSCRIPTION_ID" ]; then
    echo "Error: SUBSCRIPTION_ID is not set. Please set the Azure Subscription ID." >&2
    exit 1
fi
if [ -z "$ENVIRONMENT" ]; then
    echo "Error: ENVIRONMENT is not set. Please set the deployment environment (e.g., dev, test, prod)." >&2
    exit 1
fi
if [ -z "$LOCATION" ]; then
    echo "Error: LOCATION is not set. Please set the Azure region/location." >&2
    exit 1
fi
if [ -z "$KEY_VAULT_NAME" ]; then
    echo "Error: KEY_VAULT_NAME is not set. Please set the Key Vault name." >&2
    exit 1
fi

# Parameters
while getopts "d" opt; do
  case $opt in
    d)
      debug=1
      ;;
    *)
      echo "Usage: $0 [-d]"
      exit 1
      ;;
  esac
done

# Globals
project_root="$(git rev-parse --show-toplevel)"
env_file="${project_root}/.env"
project_name=$(grep -oP '(?<=^name = ")[^"]+' "${project_root}/pyproject.toml"  | tr -d '\n')
short_name=$(grep -oP '(?<=^short_name = ")[^"]+' "${project_root}/pyproject.toml"  | tr -d '\n')
application_service_number=$(grep -oP '(?<=^application_service_number = ")[^"]+' "${project_root}/pyproject.toml" | tr -d '\n')
application_owner=$(grep -oP '(?<=^application_owner = ")[^"]+' "${project_root}/pyproject.toml" | tr -d '\n')
short_env=$(echo "${ENVIRONMENT:0:1}" | tr '[:upper:]' '[:lower:]')
tags="asn=$application_service_number project=$project_name owner=$application_owner environment=$ENVIRONMENT"

# Variables
debug=${debug:-0}
base_name="${short_name}-${ENVIRONMENT}-${LOCATION}"
rg_name="rg-${base_name//_/-}"
app_storage_account_name="st${short_name}primary${short_env}"
app_storage_account_name=$(echo "$app_storage_account_name" | tr '[:upper:]' '[:lower:]')
app_storage_account_name="${app_storage_account_name//[^a-z0-9]/}"
app_storage_account_name="${app_storage_account_name:0:24}"

eventgrid_system_topic_name="evgst-${short_name}-pri-strg-${short_env}"
eventgrid_system_topic_name=$(echo "$eventgrid_system_topic_name" | tr '[:upper:]' '[:lower:]')
eventgrid_system_topic_name="${eventgrid_system_topic_name//[^a-z0-9]/}"
eventgrid_system_topic_name="${eventgrid_system_topic_name:0:24}"  

eventgrid_event_subscription_name="evgs-${short_name}-blob2func-${short_env}"
eventgrid_event_subscription_name=$(echo "$eventgrid_event_subscription_name" | tr '[:upper:]' '[:lower:]')
eventgrid_event_subscription_name="${eventgrid_event_subscription_name//[^a-z0-9]/}"
eventgrid_event_subscription_name="${eventgrid_event_subscription_name:0:24}" 

if [ -z "$APP_STORAGE_CONTAINER" ]; then
    APP_STORAGE_CONTAINER="pipeline-files"
fi

if [ -z "$APP_STORAGE_INPUT_PATH" ]; then
    APP_STORAGE_INPUT_PATH="incoming"
fi
if [ -z "$APP_STORAGE_OUTPUT_PATH" ]; then
    APP_STORAGE_OUTPUT_PATH="outgoing"
fi

# Resource Group
echo "Creating resource group: $rg_name" >&2
az group create \
    --name "$rg_name" \
    --location "$LOCATION" \
    --tags "$tags"

# Primary Storage Account - Application Working Files
echo "Creating storage account: $app_storage_account_name" >&2

set +e
resource=$(az storage account show --name "$app_storage_account_name" --only-show-errors 2>/dev/null)
exit_code=$?
set -e

if [[ $exit_code -eq 0 && -n "$resource" ]]; then
    echo "$app_storage_account_name already exists" >&2
    app_storageid=$(jq -r '.id' <<< "$resource")
else

    results=$(az storage account create \
        --name "$app_storage_account_name" \
        --location "$LOCATION" \
        --resource-group "$rg_name" \
        --sku Standard_LRS \
        --allow-blob-public-access true \
        --tags "$tags")
    app_storageid=$(echo "$results" | jq -r '.id')
fi

echo "Retrieving storage account key for: $app_storage_account_name" >&2
if [ -z "$APP_STORAGE_KEY" ]; then
    APP_STORAGE_KEY=$(az storage account keys list \
        --account-name "$app_storage_account_name" \
        --resource-group "$rg_name" \
        --query "[0].value" -o tsv)
fi

# Create container
echo "Creating storage container: $APP_STORAGE_CONTAINER" >&2
az storage container create \
    --name "$APP_STORAGE_CONTAINER" \
    --account-name "$app_storage_account_name" \
    --account-key "$APP_STORAGE_KEY"


# Create default directories
echo "Creating default directories in storage container: $APP_STORAGE_CONTAINER" >&2
touch emptyfile
az storage blob upload \
    --container-name "$APP_STORAGE_CONTAINER" \
    --file emptyfile \
    --name "${APP_STORAGE_INPUT_PATH}/emptyfile" \
    --account-name "$app_storage_account_name" \
    --account-key "$APP_STORAGE_KEY" \
    --overwrite

az storage blob upload \
    --container-name "$APP_STORAGE_CONTAINER" \
    --file emptyfile \
    --name "${APP_STORAGE_OUTPUT_PATH}/emptyfile" \
    --account-name "$app_storage_account_name" \
    --account-key "$APP_STORAGE_KEY" \
    --overwrite
rm emptyfile

# File Share
echo "Creating file share: share" >&2
# set +e
# resource=$(az storage share show --name share --account-name "$app_storage_account_name" --account-key "$APP_STORAGE_KEY" --only-show-errors 2>/dev/null)
# exit_code=$?
# set -e

az storage share create \
    --account-name "$app_storage_account_name" \
    --account-key "$APP_STORAGE_KEY" \
    --name share


# Create Event Grid
echo "Creating Event Grid to trigger Function on new Blob creation" >&2

# Event Grid
echo "Registering Event Grid resource provider" >&2
az provider register --namespace Microsoft.EventGrid
az provider show --namespace Microsoft.EventGrid --query "registrationState"

echo "Creating Event Grid System Topic: $eventgrid_system_topic_name" >&2
az eventgrid system-topic create \
    --name "$eventgrid_system_topic_name" \
    --resource-group "$rg_name" \
    --source "$app_storageid" \
    --topic-type Microsoft.Storage.StorageAccounts \
    --location "$LOCATION"

echo "Get storage account connection string for: $app_storage_account_name" >&2
app_storage_connection_string=$(az storage account show-connection-string \
    --name "$app_storage_account_name" \
    --resource-group "$rg_name" \
    --query "connectionString" -o tsv)

"${project_root}/script/devops_provision_func_app.sh" \
    -k "$KEY_VAULT_NAME" \
    -s "$app_storage_connection_string" \
    -c "$APP_STORAGE_CONTAINER" \
    -i "$APP_STORAGE_INPUT_PATH" \
    -o "$APP_STORAGE_OUTPUT_PATH"

# Load environment variables
if [ -f "$env_file" ]; then
    echo "Loading environment variables from $env_file" >&2
    set -o allexport
    # shellcheck disable=SC1090
    source "$env_file"
    set +o allexport
else
    echo "Warning: Environment file $env_file not found. Skipping loading environment variables." >&2
fi

# Check that FUNC_APP_NAME are set
if [ -z "$FUNC_APP_NAME" ]; then
    echo "Error: FUNC_APP_NAME is not set. Please set the Azure Function App name." >&2
    exit 1
fi
if [ -z "$FUNC_NAME" ]; then
    echo "Error: FUNC_NAME is not set. Please set the Azure Function name." >&2
    exit 1
fi
if [ -z "$FUNC_KEY" ]; then
    echo "Error: FUNC_KEY is not set. Please set the Azure Function name." >&2
    exit 1
fi
if [ -z "$FUNC_KEY_MASTER" ]; then
    echo "Error: FUNC_KEY_MASTER is not set. Please set the Azure Function name." >&2
    exit 1
fi

# It is expected that the destination endpoint to be already created and available for use before executing any Event Grid command.
# az eventgrid system-topic event-subscription create \
#     --name "$eventgrid_event_subscription_name" \
#     --resource-group "$rg_name" \
#     --system-topic-name "$eventgrid_system_topic_name" \
#     --endpoint "https://${FUNC_APP_NAME}.azurewebsites.net/runtime/webhooks/blobs?functionName=Host.Functions.${FUNC_NAME}&code=${FUNC_BLOB_EXT_KEY}" \
#     --endpoint-type webhook \
#     --included-event-types Microsoft.Storage.BlobCreated


# echo "Waiting for Function App to be ready..."
# while true; do
#     state=$(az functionapp show \
#         --name "$FUNC_APP_NAME" \
#         --resource-group "$rg_name" \
#         --query "state" -o tsv 2>/dev/null)

#     if [[ "$state" == "Running" ]]; then
#         echo "Function App is running."
#         break
#     fi

#     echo "State: $state. Sleeping..."
#     sleep 10
# done

test_webhook_url="https://$FUNC_APP_NAME.azurewebsites.net/admin/functions/$FUNC_NAME?code=${FUNC_KEY_MASTER}"
webhook_url="https://${FUNC_APP_NAME}.azurewebsites.net/runtime/runtime/webhooks/EventGrid?functionName=${FUNC_NAME}&code=${FUNC_KEY}"

echo "Checking webhook readiness..."
for i in {1..10}; do
    response=$(curl -s -w "\n%{http_code}" "$test_webhook_url")
    code=$(echo "$response" | tail -n 1)

    if [[ "$code" == "200" || "$code" == "202" ]]; then
        echo "Webhook endpoint is ready ($code)."
        break
    fi

    echo "Webhook not ready yet (HTTP $code). Attempt $i..."
    sleep 5
done

echo "Done setting up Function App webhook."

# # Depends on the Function App being already deployed and available
echo "Creating Event Grid Event Subscription: $eventgrid_event_subscription_name" >&2
az eventgrid system-topic event-subscription create \
    --name "$eventgrid_event_subscription_name" \
    --resource-group "$rg_name" \
    --system-topic-name "$eventgrid_system_topic_name" \
    --endpoint "$webhook_url" \
    --endpoint-type webhook \
    --included-event-types Microsoft.Storage.BlobCreated

# # Test
# timestamp=$(date +'%Y%m%d%H%M%S')
# test_file="test_$timestamp"
# touch "$test_file"
# az storage blob upload \
#     --container-name "$APP_STORAGE_CONTAINER" \
#     --file "$test_file" \
#     --name "${APP_STORAGE_INPUT_PATH}/${test_file}" \
#     --account-name "$APP_STORAGE_ACCOUNT_NAME" \
#     --account-key "$APP_STORAGE_KEY"
