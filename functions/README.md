# File Processing Pipeline - Function App

The fuction app receives the trigger to spin up a container instance.

## Provision Resources

Prerequisites
* LOG_ANALYTICS_ID
* APP_STORAGE_CONNECTION - Primary Storage Account

Resources
* Application Storage Account
* Function App Storage Account
* Applicatin Insights
* Function App
* Function App Config Settings

```bash
# vars
project_root=$(pwd) # Running in project root
project_name=$(cat "${project_root}/pyproject.toml" | grep -oP '(?<=^name = ")[^"]+' | tr -d '\n')
short_name=$(cat "${project_root}/pyproject.toml" | grep -oP '(?<=^short_name = ")[^"]+' | tr -d '\n')
project_version=$(cat "${project_root}/pyproject.toml" | grep -oP '(?<=^version = ")[^"]+' | tr -d '\n')
resource_token=$(echo -n "${SUBSCRIPTION_ID}${project_name}${LOCATION}" | sha1sum | awk '{print $1}' | cut -c1-8)
short_env=$(echo "${ENVIRONMENT:0:1}" | tr '[:upper:]' '[:lower:]')
tags="asn=tbd project=$project_name owner=tbd environment=$ENVIRONMENT servicetier=tier3"

base_name="${short_name}-${ENVIRONMENT}-${LOCATION}"
rg_name="rg-${base_name//_/-}"

funcapp_storage_account_name="st${short_name}func${short_env}"
funcapp_storage_account_name=$(echo "$funcapp_storage_account_name" | tr '[:upper:]' '[:lower:]')
funcapp_storage_account_name="${funcapp_storage_account_name//[^a-z0-9]/}"
funcapp_storage_account_name="${funcapp_storage_account_name:0:24}"

application_insights_name="appi-${short_name}-${short_env}-${resource_token}"

funcapp_plan_name="plan-${short_name}-${short_env}-${resource_token}"

funcapp_name="func-${short_name}-${short_env}-${resource_token}"
funcapp_name="${funcapp_name:0:24}"

# Resource Group
az group create \
    --name "$rg_name" \
    --location "$LOCATION"

#  Storage account is used to store important app data, sometimes including the application code itself. You should limit access from other apps and users to the storage account.
results=$(az storage account create \
    --name "$funcapp_storage_account_name" \
    --location "$LOCATION" \
    --resource-group "$rg_name" \
    --sku Standard_LRS \
    --allow-blob-public-access false \
    --tags "$tags")
FUNC_APP_SA=$(echo "$results" | jq -r '.name')

# App insights
results=$(az monitor app-insights component create \
    --app "$application_insights_name" \
    --location "$LOCATION" \
    --resource-group "$rg_name" \
    --workspace "$LOG_ANALYTICS_ID" \
    --application-type web \
    --tags "$tags")
APPLICATION_INSIGHTS_ID_ID=$(echo "$results" | jq -r '.id')
APPLICATION_INSIGHTS_ID_KEY=$(echo "$results" | jq -r '.instrumentationKey')

# Function App
az functionapp create \
    --resource-group "$rg_name" \
    --name "$funcapp_name" \
    --storage-account "$FUNC_APP_SA" \
    --flexconsumption-location "$LOCATION" \
    --runtime python \
    --runtime-version 3.12 \
    --os-type Linux \
    --app-insights "$application_insights_name" \
    --app-insights-key "$APPLICATION_INSIGHTS_ID_KEY" \
    --workspace "$LOG_ANALYTICS_ID" \
    --functions-version 4 \
    --instance-memory 2048 \
    --https-only true \
    --tags "$tags"

# Confgiure App Settings
az functionapp config appsettings set \
    --name "$funcapp_name" \
    --resource-group "$rg_name" \
    --settings \
        "APP_STORAGE_CONNECTION=$APP_STORAGE_CONNECTION" \
        "APP_STORAGE_CONTAINER=$APP_STORAGE_CONTAINER" \
        "APP_STORAGE_INPUT_PATH=$APP_STORAGE_INPUT_PATH" \
        "APP_STORAGE_OUTPUT_PATH=$APP_STORAGE_OUTPUT_PATH"
```

## Build and Deploy
```bash
project_root=$(pwd) # Running in project root
project_name=$(cat "${project_root}/pyproject.toml" | grep -oP '(?<=^name = ")[^"]+' | tr -d '\n')
short_name=$(cat "${project_root}/pyproject.toml" | grep -oP '(?<=^short_name = ")[^"]+' | tr -d '\n')
project_version=$(cat "${project_root}/pyproject.toml" | grep -oP '(?<=^version = ")[^"]+' | tr -d '\n')

source_folder="${project_root}/functions"
destination_dir="${project_root}/.dist"
timestamp=$(date +'%Y%m%d%H%M%S')
zip_file_name="${short_name}_functions_${ENVIRONMENT}_${timestamp}.zip"
zip_file_path="${destination_dir}/${zip_file_name}"

# Create the destination directory if it doesn't exist
mkdir -p "$(dirname "$zip_file_path")"

cd "$source_folder"
zip -r "$zip_file_path" *.py host.json requirements.txt

az functionapp deployment source config-zip \
    --src "$zip_file_path" \
    --name "$funcapp_name" \
    --resource-group "$rg_name" \
    --build-remote true
```

## References
* https://learn.microsoft.com/en-us/azure/azure-functions/flex-consumption-plan
* https://learn.microsoft.com/en-us/azure/azure-functions/functions-event-grid-blob-trigger?pivots=programming-language-python
* https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-event-grid-trigger?tabs=python-v2%2Cisolated-process%2Cnodejs-v4%2Cextensionv3&pivots=programming-language-python
* https://learn.microsoft.com/en-us/azure/azure-functions/flex-consumption-how-to?source=recommendations&tabs=azure-cli%2Cazure-cli-publish&pivots=programming-language-python