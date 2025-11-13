#!/usr/bin/env bash
#########################################################################
# Onboard and manage application on cloud infrastructure.
# Usage: provision_shared.sh 
# Globals:
#   SUBSCRIPTION_ID
#   ENVIRONMENT
#   LOCATION
# Optional Globals:
#   ARTIFACT_STORAGE_ACCOUNT
#   CONTAINER_REGISTRY_NAME
#   CONTAINER_REGISTRY_USERNAME
#   LOG_ANALYTICS_ID
# Params
#    -d, Debug mode
#########################################################################

# Stop on errors
set -e

validate_provision_parameters(){

    if [ -z "$SUBSCRIPTION_ID" ]
    then
        echo "SUBSCRIPTION_ID name is required" >&2
        exit 1
    fi

    if [ -z "$ENVIRONMENT" ]
    then
        echo "ENVIRONMENT is required" >&2
        exit 1
    fi

    if [ -z "$LOCATION" ]
    then
        echo "LOCATION is required" >&2
        exit 1
    fi
}

provision_rg(){
    echo "Provisioning Resource Group for shared resources" >&2

    set +e
    results=$(az group create \
        --name "$rg_common_name" \
        --location "$LOCATION" \
        --tags "$tags" \
        --only-show-errors 2>&1)
    set -e

    if [ "$debug" -eq 1 ]; then
        echo "$results" >> .deploy_log/az_group_create.json
    fi

    # Check for errors in the results
    if grep -q "ERROR" <<< "$results"; then
        echo "Deployment failed due to an error."
        echo "$results"
        exit 1
    fi

    # Check the provisioning state
    is_valid=$(jq -r '.properties.provisioningState' <<< "$results")
    if [ "$is_valid" != "Succeeded" ]
    then
        echo "Deployment failed. Provisioning state is not 'Succeeded'."
        echo "$results"
        exit 1
    fi

    echo "Resource Group $rg_common_name created successfully." >&2

}

provision_artifact_storage(){
    echo "Provisioning Artifact Store for shared resources" >&2

    if [ -z "$ARTIFACT_STORAGE_ACCOUNT" ]; then
        echo "ARTIFACT_STORAGE_ACCOUNT is not set. Creating a new one $storage_account_name" >&2

        # Check if the resource already exists
        set +e
        resource=$(az storage account show --name "$storage_account_name" --only-show-errors 2>/dev/null)
        exit_code=$?
        set -e

        if [[ $exit_code -eq 0 && -n "$resource" ]]; then
            echo "$storage_account_name already exists" >&2
        else

            # Create if not exists
            set +e
            results=$(az storage account create \
                --name "$storage_account_name" \
                --location "$LOCATION" \
                --resource-group "$rg_common_name" \
                --sku Standard_LRS \
                --allow-blob-public-access false \
                --tags "$tags" \
                --only-show-errors 2>&1)
            set -e

            if [ "$debug" -eq 1 ]; then
                echo "$results" >> "${project_root}/.deploy_log/az_storage_account_create.json"
            fi

            # Check for errors in the results
            if grep -q "ERROR" <<< "$results"; then
                echo "Storage Account deployment failed due to an error."
                echo "$results"
                exit 1
            fi

            # Check the provisioning state
            is_valid=$(jq -r '.provisioningState' <<< "$results")
            if [ "$is_valid" != "Succeeded" ]
            then
                echo "Storage Account Deployment failed. Provisioning state is not 'Succeeded'."
                echo "$results"
                exit 1
            fi
        fi
    else
        echo "ARTIFACT_STORAGE_ACCOUNT already exists" >&2
        storage_account_name="$ARTIFACT_STORAGE_ACCOUNT"
    fi

    # Create Artifact Container
    echo "Creating Artifact Container $artifact_container in Storage Account $storage_account_name" >&2
    app_storage_key=$(az storage account keys list \
        --resource-group "$rg_common_name" \
        --account-name "$storage_account_name" \
        --query '[0].value' \
        --output tsv)

    set +e
    results=$( az storage container create \
        --name "$artifact_container" \
        --account-name "$storage_account_name" \
        --account-key "$app_storage_key" \
        --only-show-errors 2>&1)
    set -e

    if [ "$debug" -eq 1 ]; then
        echo "$results" >> "${project_root}/.deploy_log/az_storage_container_create.json"
    fi

    # Check for errors in the results
    if grep -q "ERROR" <<< "$results"; then
        echo "Container deployment failed due to an error."
        echo "$results"
        exit 1
    fi

    echo "Save output variables to ${env_file}" >&2
    {
        echo ""
        echo "# devops_provision_shared.sh Provision output variables"
        echo "# Generated on ${isa_date_utc}"
        echo "ARTIFACT_STORAGE_ACCOUNT=$storage_account_name"
        echo "ARTIFACT_STORAGE_ACCOUNT_KEY=$app_storage_key"
        echo "ARTIFACT_CONTAINER=$artifact_container"
    }>> "$env_file"

}

provision_container_registry(){
    echo "Provisioning Container Registry for shared resources" >&2

    if [ -z "$CONTAINER_REGISTRY_NAME" ]; then
        echo "CONTAINER_REGISTRY_NAME is not set. Creating a new one" >&2

        # Check if the resource already exists
        set +e
        resource=$(az acr show --name "$container_registry_name" --only-show-errors 2>/dev/null)
        exit_code=$?
        set -e

        if [[ $exit_code -eq 0 && -n "$resource" ]]; then
            echo "$container_registry_name already exists" >&2
        else

            # Create if not exists
            set +e
            results=$(az acr create \
                --resource-group "$rg_common_name" \
                --name "$container_registry_name" \
                --sku Basic \
                --location "$LOCATION" \
                --tags "$tags" \
                --only-show-errors 2>&1)
            set -e
            
            if [ "$debug" -eq 1 ]; then
                echo "$results" >> "${project_root}/.deploy_log/az_acr_create.json"
            fi

            # Check for errors in the results
            if grep -q "ERROR" <<< "$results"; then
                echo "Container Registry Deployment failed due to an error."
                echo "$results"
                exit 1
            fi

            # Check the provisioning state
            is_valid=$(jq -r '.provisioningState' <<< "$results")
            if [ "$is_valid" != "Succeeded" ]
            then
                echo "Container Registry Deployment failed. Provisioning state is not 'Succeeded'."
                echo "$results"
                exit 1
            fi
        fi
    else
        echo "CONTAINER_REGISTRY_NAME already exists" >&2
        container_registry_name="$CONTAINER_REGISTRY_NAME"
    fi

    echo "Save Container Registry output variables to ${env_file}" >&2
    {
        echo ""
        echo "# devops_provision_shared.sh Container Registry Provision output variables"
        echo "# Generated on ${isa_date_utc}"
        echo "CONTAINER_REGISTRY_NAME=$container_registry_name"
        
    }>> "$env_file"
    

    # Configure Repo Permissions

    if [ -z "$CONTAINER_REGISTRY_USERNAME" ]; then
        echo "CONTAINER_REGISTRY_USERNAME is not set. Creating a new one" >&2

        # Check if the resource already exists
        set +e
        resource=$(az keyacr token show --name "$container_registry_username" --registry "$container_registry_name" --only-show-errors 2>/dev/null)
        exit_code=$?
        set -e

        if [[ $exit_code -eq 0 && -n "$resource" ]]; then
            echo "$container_registry_username already exists" >&2
        else
    
            set +e
            results=$(az acr token create \
                --name "$container_registry_username" \
                --registry "$container_registry_name" \
                --scope-map _repositories_push_metadata_write \
                --output json \
                --only-show-errors 2>&1)
            set -e

            if [ "$debug" -eq 1 ]; then
                echo "$results" >> "${project_root}/.deploy_log/az_acr_token_create.json"
            fi

            # Check for errors in the results
            if grep -q "ERROR" <<< "$results"; then
                echo "Container Registry Deployment failed due to an error."
                echo "$results"
                exit 1
            fi

            # Check the provisioning state
            is_valid=$(jq -r '.provisioningState' <<< "$results")
            if [ "$is_valid" != "Succeeded" ]
            then
                echo "Container Registry Token Deployment failed. Provisioning state is not 'Succeeded'."
                echo "$results"
                exit 1
            fi

            CONTAINER_REGISTRY_PASSWORD=$(echo "$results" | jq -r '.credentials.passwords[0].value')
            echo "Save Container Registry Token output variables to ${env_file}" >&2
            {
                echo ""
                echo "# devops_provision_shared.sh Container Registry Token Provision output variables"
                echo "# Generated on ${isa_date_utc}"
                echo "CONTAINER_REGISTRY_PASSWORD=$CONTAINER_REGISTRY_PASSWORD"
            }>> "$env_file"
        fi
    else
        echo "CONTAINER_REGISTRY_USERNAME already exists" >&2
    fi

    echo "Save Container Registry output variables to ${env_file}" >&2
    {
        echo ""
        echo "# devops_provision_shared.sh Container Registry Token Provision output variables"
        echo "# Generated on ${isa_date_utc}"
        echo "CONTAINER_REGISTRY_USERNAME=$container_registry_username"
    }>> "$env_file"
}

provision_monitoring(){
    echo "Provisioning Monitoring for shared resources" >&2

    if [ -z "$LOG_ANALYTICS_ID" ]; then
        echo "LOG_ANALYTICS_ID is not set. Creating a new one $log_analytics_name" >&2

        # Check if the resource already exists
        set +e
        resource=$(az monitor log-analytics workspace show --name "$log_analytics_name" --only-show-errors 2>/dev/null)
        exit_code=$?
        set -e

        if [[ $exit_code -eq 0 && -n "$resource" ]]; then
            echo "$log_analytics_name already exists" >&2
        else

            set +e
            results=$(az monitor log-analytics workspace create \
                --resource-group "$rg_common_name" \
                --workspace-name "$log_analytics_name" \
                --location "$LOCATION" \
                --sku PerGB2018 \
                --tags "$tags" \
                --only-show-errors 2>&1)
            set -e
            
            if [ "$debug" -eq 1 ]; then
                echo "$results" >> "${project_root}/.deploy_log/az_monitor_loganalytics_workspace_create.json"
            fi

            # Check for errors in the results
            if grep -q "ERROR" <<< "$results"; then
                echo "Deployment failed due to an error."
                echo "$results"
                exit 1
            fi

            # Check the provisioning state
            is_valid=$(jq -r '.provisioningState' <<< "$results")
            if [ "$is_valid" != "Succeeded" ]
            then
                echo "Deployment failed. Provisioning state is not 'Succeeded'."
                echo "$results"
                exit 1
            fi

            LOG_ANALYTICS_ID=$(echo "$results" | jq -r '.id')
            echo "Save output variables to ${env_file}" >&2
            {
                echo ""
                echo "# devops_provision_shared.sh Provision output variables"
                echo "# Generated on ${isa_date_utc}"
                echo "LOG_ANALYTICS_ID=\"$LOG_ANALYTICS_ID\""
            }>> "$env_file"
        fi
       
    else
        echo "LOG_ANALYTICS_ID already exists" >&2
    fi
}

provision_key_vault(){
    echo "Provisioning Key Vault for shared resources" >&2

    if [ -z "$KEY_VAULT_NAME" ]; then
        echo "KEY_VAULT_NAME is not set. Creating a new one $key_vault_name" >&2

        # Check if the resource already exists
        set +e
        resource=$(az keyvault show --name "$key_vault_name" --only-show-errors 2>/dev/null)
        exit_code=$?
        set -e

        if [[ $exit_code -eq 0 && -n "$resource" ]]; then
            echo "$key_vault_name already exists" >&2
        else
            
            set +e
            results=$(az keyvault create \
                --name "$key_vault_name" \
                --resource-group "$rg_common_name" \
                --location "$LOCATION" \
                --tags "$tags" \
                --only-show-errors 2>&1)
            set -e

            if [ "$debug" -eq 1 ]; then
                echo "$results" >> "${project_root}/.deploy_log/az_keyvault_create.json"
            fi

            # Check for errors in the results
            if grep -q "ERROR" <<< "$results"; then
                echo "Deployment failed due to an error."
                echo "$results"
                exit 1
            fi
        fi
    else
        echo "KEY_VAULT_NAME already exists" >&2
        key_vault_name="$KEY_VAULT_NAME"
    fi

    echo "Save output variables to ${env_file}" >&2
    {
        echo ""
        echo "# devops_provision_shared.sh Provision output variables"
        echo "# Generated on ${isa_date_utc}"
        echo "KEY_VAULT_NAME=$key_vault_name"
    }>> "$env_file"
}

# Save output variables to keyvault
save_outputs_to_keyvault(){
    echo "Saving output variables to Key Vault ${key_vault_name}" >&2

    # Load environment variables
    source "$env_file"

    declare -A secrets=(
        ["SharedArtifactStorageAccount"]="$ARTIFACT_STORAGE_ACCOUNT"
        ["SharedArtifactStorageAccountKey"]="$ARTIFACT_STORAGE_ACCOUNT_KEY"
        ["SharedArtifactContainer"]="$ARTIFACT_CONTAINER"
        ["SharedContainerRegistryName"]="$CONTAINER_REGISTRY_NAME"
        ["SharedContainerRegistryUsername"]="$CONTAINER_REGISTRY_USERNAME"
        ["SharedContainerRegistryPassword"]="$CONTAINER_REGISTRY_PASSWORD"
        ["SharedLogAnalyticsId"]="$LOG_ANALYTICS_ID"
    )

    # Loop through secrets and set each one
    for secret_name in "${!secrets[@]}"; do
        secret_value="${secrets[$secret_name]}"
        
        if [[ -z "$secret_value" ]]; then
            echo "  Skipping $secret_name — value is empty"
            continue
        fi

        echo "  Setting secret: $secret_name"
       
        set +e
        results=$(az keyvault secret set \
            --vault-name "$key_vault_name" \
            --name "$secret_name" \
            --value "$secret_value" \
            --only-show-errors 2>&1)
        set -e
        
        if [ "$debug" -eq 1 ]; then
            echo "$results" >> "${project_root}/.deploy_log/az_keyvault_secret_set_$secret_name.json"
        fi

        # Check for errors in the results
        if grep -q "ERROR" <<< "$results"; then
            echo "Setting secret $secret_name failed due to an error."
            echo "$results"
            exit 1
        fi

        echo "  Secret $secret_name set successfully."
        
    done

    echo "Output variables saved to Key Vault ${key_vault_name}" >&2
}

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
application_service_number=$(grep -oP '(?<=^application_service_number = ")[^"]+' "${project_root}/pyproject.toml" | tr -d '\n')
application_owner=$(grep -oP '(?<=^application_owner = ")[^"]+' "${project_root}/pyproject.toml" | tr -d '\n')
resource_token=$(echo -n "${SUBSCRIPTION_ID}${project_name}${LOCATION}" | sha1sum | awk '{print $1}' | cut -c1-8)
short_env=$(echo "${ENVIRONMENT:0:1}" | tr '[:upper:]' '[:lower:]')
tags="asn=$application_service_number project=$project_name owner=$application_owner environment=$ENVIRONMENT"

run_date=$(date +%Y%m%dT%H%M%S)
isa_date_utc=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
deployment_name="${project_name}.Provisioning-Shared.${run_date}"

# Variables
debug=${debug:-0}
rg_common_name="rg-common-${ENVIRONMENT}-${LOCATION}"
log_analytics_name="log-common-${ENVIRONMENT}-${LOCATION}-${resource_token}"
storage_account_name="startifacts-${resource_token}-${short_env}"
storage_account_name=$(echo "$storage_account_name" | tr '[:upper:]' '[:lower:]')
storage_account_name="${storage_account_name//[^a-z0-9]/}"
storage_account_name="${storage_account_name:0:24}"
artifact_container=shared-artifacts
container_registry_name="crcommon${resource_token}${short_env}"
container_registry_username="ci-build-pullpush"
key_vault_name="kv-common-${ENVIRONMENT}"

# Configure debug logging
if [ "$debug" -eq 1 ]; then

    echo "Deployment ${deployment_name}" >&2
    echo "SUBSCRIPTION_ID=${SUBSCRIPTION_ID:-<not set>}" >&2
    echo "ENVIRONMENT=${ENVIRONMENT:-<not set>}" >&2
    echo "LOCATION=${LOCATION:-<not set>}" >&2
    echo "debug=${debug:-<not set>}" >&2

    rm -Rf .deploy_log
    mkdir -p .deploy_log
fi

# Validate required parameters
validate_provision_parameters

# Provision Resources ----------------------------------------------------------
provision_rg
provision_container_registry
provision_artifact_storage
provision_monitoring
provision_key_vault
save_outputs_to_keyvault
