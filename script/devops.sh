#!/usr/bin/env bash
#########################################################################
# Manage DevOps actions for deployment pipelines.
# Usage: devops_build_deploy_pipeline_app.sh [COMMAND]
# Globals:
# Optional Globals:
# Commands
#    upload_artifact
# Params
#########################################################################


# Stop on errors
set -e

get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

log_info() {
    if [[ $log_level -ge $LOG_INFO ]]; then
        echo -e "$(get_timestamp) ${GREEN}[INFO]${NC} $*" >&2
    fi
}

log_error() {
    if [[ $log_level -ge $LOG_ERROR ]]; then
        echo -e "$(get_timestamp) ${RED}[ERROR]${NC} $*" >&2
    fi
    
}

log_debug() {
    if [[ $log_level -ge $LOG_DEBUG ]]; then
        echo -e "$(get_timestamp) ${GRAY}[DEBUG]${NC} $*" >&2
    fi
}

show_help() {
    echo "$0 : Manage DevOps actions for deployment pipelines"
    echo "Usage: devops.sh [OPTIONS] [COMMAND] [ARGS]"
    echo "Globals"
    echo
    echo "Options:"
    echo "  -h, --help       Show this message and get help for a command."
    echo "Commands"
    echo ""
    echo "  upload_artifact Upload an artifact to Azure Blob Storage."
    echo "      -a, --account-name     Storage account name"
    echo "      -k, --account-key      Storage account key"
    echo "      -c, --container-name   (Optional) Blob container name. Default: $DEFAULT_ARTIFACT_CONTAINER"
    echo "      -f, --file             Local file path to upload"
    echo "      -n, --name             (Optional) Target name in blob storage. Default: ${SHORT_NAME}/artifact.zip"
    echo ""
    echo "  fetch_artifact Fetch an artifact from Azure Blob Storage."
    echo "      -a, --account-name     Storage account name"
    echo "      -k, --account-key      Storage account key"
    echo "      -c, --container-name   (Optional) Blob container name. Default: $DEFAULT_ARTIFACT_CONTAINER"
    echo "      -n, --name             (Optional) Target name in blob storage. Default: ${SHORT_NAME}/artifact.zip"
    echo ""
    echo "   build_image Build a Docker image for the application."
    echo "      -n, --name             Name of the Docker image to build."
    echo "      -l, --channel          Release channel (dev or release). Default: $CHANNEL_DEV"
    echo ""
    echo "   publish_image Publish a Docker image to Azure Container Registry."
    echo "      -v, --version          Version tag for the Docker image."
    echo "      -l, --channel          Release channel (dev or release). Default: $CHANNEL_DEV"
    echo ""
    echo "   upload_pipeline_config Upload pipeline configuration to Azure Blob Storage."
    ecoh ""
    echo "   deploy_container_instance Deploy the Docker image to Azure Container Instances."
    echo "      -v, --version          Version tag for the Docker image."
    echo ""
    echo "Example usage:"
    echo "  $0 upload_artifact -a mystorageaccount -k myaccountkey -c mycontainer -f ./local/artifact.zip -n myfolder/myartifact.zip"
    echo "  $0 fetch_artifact -a mystorageaccount -k myaccountkey -c mycontainer -n myfolder/myartifact.zip"
    echo "  $0 build_image -n myappimage -l dev"
    echo "  $0 publish_image -v 1.0.0"
    echo "  $0 upload_pipeline_config"
    echo "  $0 deploy_container_instance -v 1.0.0"
}

validate_parameters(){
    # Check command
    if [ -z "$1" ]
    then
        log_error "COMMAND is required." >&2
        show_help
        exit 1
    fi
}

validate_upload_artifact_parameters(){

    if [ -z "$account_name" ]
    then
        log_error "usage error: --account-name is required." >&2
        show_help
        exit 1
    fi

    if [ -z "$account_key" ]
    then
        log_error "usage error: --account-key is required." >&2
        show_help
        exit 1
    fi

    if [ -z "$container_name" ]
    then
        log_error "usage error: --container-name is required." >&2
        show_help
        exit 1
    fi

    if [ -z "$file" ]
    then
        log_error "usage error: --file is required." >&2
        show_help
        exit 1
    fi

}

validate_fetch_artifact_parameters(){

    if [ -z "$account_name" ]
    then
        log_error "usage error: --account-name is required." >&2
        show_help
        exit 1
    fi

    if [ -z "$account_key" ]
    then
        log_error "usage error: --account-key is required." >&2
        show_help
        exit 1
    fi

    if [ -z "$container_name" ]
    then
        log_error "usage error: --container-name is required." >&2
        show_help
        exit 1
    fi

}

validate_build_image_parameters(){

    if [ -z "$APP_INSTALLER_FILE" ]
    then
        log_error "usage error: APP_INSTALLER_FILE is required." >&2
        show_help
        exit 1
    fi

    if [ -z "$APP_FILE" ]
    then
        log_error "usage error: APP_FILE is required." >&2
        show_help
        exit 1
    fi

    if [ -z "$APP_SETUP_ARGS" ]
    then
        log_error "usage error: APP_SETUP_ARGS is required." >&2
        show_help
        exit 1
    fi

}

validate_deploy_container_instance_parameters(){

    if [ -z "$version" ]
    then
        log_error "usage error: --version is required." >&2
        show_help
        exit 1
    fi

}


upload_artifact(){
    local local_file="$1"
    local account_name="$2"
    local account_key="$3"
    local container_name="$4"
    local target_name="$5"

    log_info "Upload artifact."
    log_debug "Upload artifact $local_file to ${account_name}/${container_name}/${target_name}."

    set +e
    result=$(az storage blob upload \
        --account-name "$account_name" \
        --container-name "$container_name" \
        --file "$local_file" \
        --name "${target_name}" \
        --account-key "$account_key" \
        --overwrite true \
        --only-show-errors \
        --no-progress 2>&1)
    set -e

    log_debug "$result"
    
    # Save file if LOG_DEBUG is enabled
    if [[ $log_level -ge $LOG_DEBUG ]]; then
        log_debug "Saving result to az_storage_blob_upload.log."
        echo "$result" >> "${PROJECT_ROOT}/.deploy_log/az_storage_blob_upload.log"
    fi

    # Check for errors in the result
    if grep -q "ERROR" <<< "$result"; then
        log_error "${command^} failed due to an error."
        log_error "$result"
        exit 1
    fi

    # Check if success message is present
    last_modified=$(echo "$result" | jq -r '.lastModified')
    if [[ -z "$last_modified" || "$last_modified" == "null" ]]; then
        log_error "${command^} failed. No lastModified timestamp found."
        log_error "$result"
        exit 1
    fi
    
    log_info "Successfully uploaded artifact." 
    log_debug "Successfully uploaded artifact ${artifact_name} uploaded to ${account_name}/${container_name}/${target_name}." 

}

fetch_artifact(){
    local account_name="$1"
    local account_key="$2"
    local container_name="$3"
    local artifact_name="$4"
    local result
    local artifact_sas_token
    local artifact_path

    log_info "Fetch artifact."
    log_debug "Fetch artifact from ${account_name}/${container_name}/${artifact_name}."

    # Fetch Artifact
    set +e
    result=$(az storage container generate-sas \
        --name "${container_name}" \
        --auth-mode key \
        --account-key "${account_key}" \
        --account-name "${account_name}" \
        --permission r \
        --expiry "$(date -u -d "5 minutes" '+%Y-%m-%dT%H:%MZ')" \
        --only-show-errors \
        --output tsv 2>&1)
    set -e

    log_debug "$result"

    # Save file if LOG_DEBUG is enabled
    if [[ $log_level -ge $LOG_DEBUG ]]; then
        log_debug "Saving result to az_storage_container_generate_sas.log."
        echo "$result" >> "${PROJECT_ROOT}/.deploy_log/az_storage_container_generate_sas.log"
    fi

    # Check for errors in the result
    if grep -q "ERROR" <<< "$result"; then
        log_error "${command^} failed due to an error."
        log_error "$result"
        exit 1
    fi

    # Check if valid sas token
    if [[ "$result" == *"sig="* && "$result" == *"se="* ]]; then
        log_debug "SAS token generated successfully."
    else
        log_error "${command^} failed. Invalid SAS token generated."
        log_error "$result"
        exit 1
    fi

    artifact_sas_token="$result"
    artifact_path="https://${account_name}.blob.core.windows.net/${container_name}/${artifact_name}"
    
    # Create temp directory and download artifact
    log_info "Downloading artifact."
    log_debug "Downloading artifact from ${artifact_path} to temp.zip."
    mkdir -p .artifact_cache
    curl -fsSL "${artifact_path}?${artifact_sas_token}" -o "temp.zip"

    log_info "Unzipping artifact to .artifact_cache."
    unzip -qo "temp.zip" -d .artifact_cache
    rm -f "temp.zip"

    log_info "Successfully fetched artifact." 
    log_debug "Successfully fetched artifact from ${account_name}/${container_name}/${artifact_name}." 

}

# Retrieve secret from Azure Key Vault
get_keyvault_secret() {
    local vault_name="$1"
    local secret_name="$2"
    local secret_value

    log_info "Retrieving secret '$secret_name' from vault '$vault_name'"

    if ! secret_value=$(az keyvault secret show \
        --name "$secret_name" \
        --vault-name "$vault_name" \
        --query "value" \
        --output tsv 2>/dev/null); then
        log_error "Failed to retrieve secret '$secret_name' from vault '$vault_name'"
        return 2
    fi
    
    if [[ -z "$secret_value" ]]; then
        log_error "Secret '$secret_name' is empty in vault '$vault_name'"
        return 2
    fi
    
    echo "$secret_value"
}

login_acr(){

    # Validate input
    if [[ -z "$KEY_VAULT_NAME" ]]; then
        log_error "Key Vault name not provided. set KEY_VAULT_NAME"
        return 1
    fi

    log_info "Authenticating to Azure Container Registry"
    log_info "Using Key Vault: $KEY_VAULT_NAME"

    local registry_name
    local registry_username
    local registry_password

    if ! registry_name=$(get_keyvault_secret "$KEY_VAULT_NAME" "SharedContainerRegistryName"); then
        return 2
    fi

    if ! registry_username=$(get_keyvault_secret "$KEY_VAULT_NAME" "SharedContainerRegistryUsername"); then
        return 2
    fi

    if ! registry_password=$(get_keyvault_secret "$KEY_VAULT_NAME" "SharedContainerRegistryPassword"); then
        return 2
    fi

    log_info "Logging into registry: $registry_name"

    if ! echo "$registry_password" | docker login \
        --username "$registry_username" \
        --password-stdin \
        "${registry_name}.azurecr.io" 2>/dev/null; then
        log_error "Docker login failed for registry '$registry_name'"
        return 3
    fi

    log_info "Successfully authenticated to $registry_name"
    return 0

}

build_image(){
    local channel="$1"

    log_info "Building image for ${channel}"

    # Determine build version
    if [ "$channel" == "$CHANNEL_RELEASE" ]; then
        version="${PROJECT_VERSION}"
    else
        version="${PROJECT_VERSION}.dev${BUILD_NUMBER}"
    fi

    image_name="${IMAGE}:${version}"

    log_debug "Building image: $image_name for dockerfile_path: $DOCKERFILE."

    # Build image
    DOCKER_BUILDKIT=1 docker buildx build \
        --platform linux/amd64 \
        --build-arg "RELEASE_VERSION=$version" \
        --build-arg "APP_INSTALLER_FILE=$APP_INSTALLER_FILE" \
        --build-arg "APP_FILE=$APP_FILE" \
        --build-arg "APP_SETUP_ARGS=$APP_SETUP_ARGS"  \
        --build-arg "APP_ALIAS=$APP_ALIAS" \
        -t "$image_name" -f "${DOCKERFILE}" "${PROJECT_ROOT}"


    # Record build version
    # Get the output variables from the deployment
    log_info "Save output variables to ${ENV_FILE}"
    {
        echo ""
        echo "# Script $SCRIPT_NAME - build_image - output variables."
        echo "# Generated on ${ISO_DATE_UTC}"
        echo "IMAGE_VERSION=${version}"
    }>> "$ENV_FILE"

    log_info "Successfully built image: $image_name"

    # Return version
    echo "$version"

}

publish_image(){
    local version="$1"
    local channel="$2"
    local dev_tags=("${version}" "dev")
    local release_tags=("${version}" "latest")

    if [ "$channel" == "$CHANNEL_RELEASE" ]
    then
        tags=("${release_tags[@]}")
    else
        tags=("${dev_tags[@]}")
    fi

    # Tag images with extra tags
    for tag in "${tags[@]}"; do
        docker tag "${IMAGE}:${version}" "${IMAGE}:${tag}"
    done

    if ! registry_name=$(get_keyvault_secret "$KEY_VAULT_NAME" "SharedContainerRegistryName"); then
        return 2
    fi

    # Push Images
    for tag in "${tags[@]}"; do
        docker tag "${IMAGE}:${tag}" "${registry_name}.azurecr.io/${CONTAINER_REGISTRY_NAMESPACE}/${IMAGE}:${tag}"
        docker push "${registry_name}.azurecr.io/${CONTAINER_REGISTRY_NAMESPACE}/${IMAGE}:${tag}"
    done

    log_info "Successfully published image: ${IMAGE} with tags: ${tags[*]}"

}

upload_pipeline_config(){
    local app_storage_key
    local config_files
    local result
    local last_modified

    log_info "Starting upload pipeline configuration task."

    # Get storage account key
    log_info "Retrieving storage account key for account: ${APP_STORAGE_ACCOUNT_NAME}."
    set +e
    app_storage_key=$(az storage account keys list \
        --resource-group "$RG_NAME" \
        --account-name "$APP_STORAGE_ACCOUNT_NAME" \
        --query "[0].value" \
        --output tsv 2>&1)
    set -e

    config_files=(
        "$LOCAL_APP_RUNTIME_CONFIG_FILE"
        "$LOCAL_APP_EXPORT_CONFIG_FILE"
        "$LOCAL_APP_STATS_CONFIG_FILE"
    )
    for config_file in "${config_files[@]}"; do
        log_info "Uploading configuration file: $config_file to Azure File Share."

        set +e
        result=$(az storage file upload \
            --source "$config_file" \
            --share-name share \
            --account-key "$app_storage_key" \
            --account-name "$APP_STORAGE_ACCOUNT_NAME" \
            --only-show-errors \
            )
        set -e

        # Save file if LOG_DEBUG is enabled
        if [[ $log_level -ge $LOG_DEBUG ]]; then
            log_debug "Saving result to az_storage_file_upload_$(basename "$config_file").json."
            echo "$result" >> "${PROJECT_ROOT}/.deploy_log/az_storage_file_upload_$(basename "$config_file").json"
        fi

        # Check for errors in the result
        if grep -q "ERROR" <<< "$result"; then
            log_error "${command^} failed due to an error."
            log_error "$result"
            exit 1
        fi

        # Check if success message is present
        last_modified=$(echo "$result" | jq -r '.last_modified')
        if [[ -z "$last_modified" || "$last_modified" == "null" ]]; then
            log_error "${command^} failed. No last_modified timestamp found."
            log_error "$result"
            exit 1
        fi

        log_info "Successfully uploaded configuration file: $config_file."
    done

    log_info "Successfully completed pipeline configuration task."

}

deploy_container_instance(){
    local version="$1"
    local registry_name
    local registry_username
    local registry_password
    local app_storage_key

    log_info "Deploying container instance for image version: $version"

    # Delete existing container instance if it exists
    log_info "Checking for existing container instance: ${ACI_NAME} in resource group: ${RG_NAME}."
    if az container show --resource-group "$RG_NAME" --name "${ACI_NAME}" &>/dev/null; then
        log_info "Deleting existing container instance: ${ACI_NAME}"

        set +e
        result=$(az container delete \
            --resource-group "$RG_NAME" \
            --name "$ACI_NAME" \
            --yes \
            --only-show-errors 2>&1)
        set -e

        if [[ $log_level -ge $LOG_DEBUG ]]; then
            log_debug "Saving result to az_container_delete.json."
            echo "$result" >> "${PROJECT_ROOT}/.deploy_log/az_container_delete.json"
        fi

        # Check for errors in the result
        if grep -q "ERROR" <<< "$result"; then
            log_error "${command^} failed due to an error."
            log_error "$result"
            exit 1
        fi

        log_info "Successfully deleted existing container instance: ${ACI_NAME}."
    else
        log_info "No existing container instance found: ${ACI_NAME}."
    fi


    # Get ACR credentials from Key Vault
    if ! registry_name=$(get_keyvault_secret "$KEY_VAULT_NAME" "SharedContainerRegistryName"); then
        return 2
    fi

    if ! registry_username=$(get_keyvault_secret "$KEY_VAULT_NAME" "SharedContainerRegistryUsername"); then
        return 2
    fi

    if ! registry_password=$(get_keyvault_secret "$KEY_VAULT_NAME" "SharedContainerRegistryPassword"); then
        return 2
    fi

    # Get storage account key
    log_info "Retrieving storage account key for account: ${APP_STORAGE_ACCOUNT_NAME}."
    set +e
    app_storage_key=$(az storage account keys list \
        --resource-group "$RG_NAME" \
        --account-name "$APP_STORAGE_ACCOUNT_NAME" \
        --query "[0].value" \
        --output tsv 2>&1)
    set -e

    # Deploy to Azure Container Instances
    log_info "Creating container instance: ${ACI_NAME} in resource group: ${RG_NAME}."
    set +e
    result=$(az container create \
        --resource-group "$RG_NAME" \
        --name "$ACI_NAME" \
        --image "${registry_name}.azurecr.io/${CONTAINER_REGISTRY_NAMESPACE}/${IMAGE}:${version}" \
        --cpu 2 --memory 4 \
        --restart-policy Never \
        --os-type Linux \
        --registry-login-server "${registry_name}.azurecr.io" \
        --registry-username "$registry_username" \
        --registry-password "$registry_password" \
        --azure-file-volume-account-name "$APP_STORAGE_ACCOUNT_NAME" \
        --azure-file-volume-account-key "$app_storage_key" \
        --azure-file-volume-share-name "share" \
        --azure-file-volume-mount-path /mnt/azurefiles \
        --environment-variables \
            APP_RUNTIME_CONFIG_FILE="$APP_RUNTIME_CONFIG_FILE" \
            APP_EXPORT_CONFIG_FILE="$APP_EXPORT_CONFIG_FILE" \
            APP_STATS_CONFIG_FILE="$APP_STATS_CONFIG_FILE" \
            APP_LOG_FILE="$APP_LOG_FILE" \
        --only-show-errors 2>&1)
    set -e

    # Save file if LOG_DEBUG is enabled
    if [[ $log_level -ge $LOG_DEBUG ]]; then
        log_debug "Saving result to az_container_create.json."
        echo "$result" >> "${PROJECT_ROOT}/.deploy_log/az_container_create.json"
    fi

    # Check for errors in the result
    if grep -q "ERROR" <<< "$result"; then
        log_error "${command^} failed due to an error."
        log_error "$result"
        exit 1
    fi

    # Check if success message is present
    container_status=$(echo "$result" | jq -r '.containers[0].instanceView.detailStatus')
    if [[ -z "$container_status" || "$container_status" == "Error" ]]; then
        log_error "${command^} failed. Container instance not created successfully."
        log_error "$result"
        exit 1
    fi

    # Check provisioning State
    provisioning_state=$(echo "$result" | jq -r '.provisioningState')
    if [[ -z "$provisioning_state" || "$provisioning_state" != "Succeeded" ]]; then
        log_error "${command^} failed. Provisioning state is not Succeeded."
        log_error "$result"
        exit 1
    fi

    log_info "Successfully deployed container instance for image version: $version"

}

#########################################################################
# ENVIRONMENT VARIABLES (external, may be set by user)
# - ALL_CAPS with underscores
#########################################################################
# SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-}"
MODEL_NAME="${MODEL_NAME:-}"
MODEL_VERSION="${MODEL_VERSION:-}"
APP_INSTALLER_FILE="${APP_INSTALLER_FILE:-}"
APP_FILE="${APP_FILE:-}"
APP_SETUP_ARGS="${APP_SETUP_ARGS:-}"
APP_ALIAS="${APP_ALIAS:-}"
KEY_VAULT_NAME="${KEY_VAULT_NAME:-}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
LOCATION="${LOCATION:-westus3}"
APP_LOG_FILE="${APP_LOG_FILE:-}"

#########################################################################
# SCRIPT CONSTANTS (internal, read-only)
# - ALL_CAPS with underscores
# - ALWAYS use 'readonly' keyword
#########################################################################
# General
PROJECT_ROOT="$(git rev-parse --show-toplevel)" || {
    echo "Error: Not in a git repository" >&2
    exit 1
}
readonly PROJECT_ROOT
SHORT_NAME="$(grep -oP '(?<=^short_name = ")[^"]+' "${PROJECT_ROOT}/pyproject.toml"  | tr -d '\n')" || {
    echo "Error: Could not extract short_name from pyproject.toml" >&2
    exit 1
}
readonly SHORT_NAME
PROJECT_VERSION="$(grep -oP '(?<=^version = ")[^"]+' "${PROJECT_ROOT}/pyproject.toml"  | tr -d '\n')" || {
    echo "Error: Could not extract version from pyproject.toml" >&2
    exit 1
}
readonly PROJECT_VERSION
SCRIPT_NAME="$(basename "$0")" || {
    echo "Error: Could not determine script name" >&2
    exit 1
}
readonly SCRIPT_NAME
readonly IMAGE="${MODEL_NAME}_v${MODEL_VERSION}"
BUILD_NUMBER="$(date -u +%Y%m%dT%H%MZ)" || {
    echo "Error: Could not generate build number" >&2
    exit 1
}
readonly BUILD_NUMBER
readonly DOCKERFILE="${PROJECT_ROOT}/pipeline_app/Dockerfile"
readonly CONTAINER_REGISTRY_NAMESPACE="aimodelserving"
readonly ENV_FILE="${PROJECT_ROOT}/.env"
readonly LOCAL_APP_RUNTIME_CONFIG_FILE="./pipeline_app/runtime-config.json"
readonly LOCAL_APP_EXPORT_CONFIG_FILE="./pipeline_app/export-config.json"
readonly LOCAL_APP_STATS_CONFIG_FILE="./pipeline_app/stats-config.json"
SHORT_ENV="$(echo "${ENVIRONMENT:0:1}" | tr '[:upper:]' '[:lower:]')" || {
    echo "Error: Could not determine short environment" >&2
    exit 1
}
readonly SHORT_ENV
readonly BASE_NAME="${SHORT_NAME}-${ENVIRONMENT}-${LOCATION}"
readonly RG_NAME="rg-${BASE_NAME//_/-}"
readonly ACI_NAME="acg-${SHORT_NAME}-ondemand-${SHORT_ENV}"
APP_STORAGE_ACCOUNT_NAME="st${SHORT_NAME}primary${SHORT_ENV}"
APP_STORAGE_ACCOUNT_NAME=$(echo "$APP_STORAGE_ACCOUNT_NAME" | tr '[:upper:]' '[:lower:]')
APP_STORAGE_ACCOUNT_NAME="${APP_STORAGE_ACCOUNT_NAME//[^a-z0-9]/}"
APP_STORAGE_ACCOUNT_NAME="${APP_STORAGE_ACCOUNT_NAME:0:24}"
readonly APP_STORAGE_ACCOUNT_NAME
readonly APP_RUNTIME_CONFIG_FILE="/mnt/azurefiles/config/runtime_config.json"
readonly APP_EXPORT_CONFIG_FILE="/mnt/azurefiles/export-config.json"
readonly APP_STATS_CONFIG_FILE="/mnt/azurefiles/stats-config.json"
# Log levels
readonly LOG_ERROR=0
readonly LOG_INFO=1
readonly LOG_DEBUG=2
# Release Channels
readonly CHANNEL_DEV="dev"
readonly CHANNEL_RELEASE="release"
# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly GRAY='\033[0;90m'
readonly NC='\033[0m'
# Defaults
readonly DEFAULT_ARTIFACT_NAME="${SHORT_NAME}/artifact.zip"
readonly DEFAULT_ARTIFACT_CONTAINER=shared-artifacts
# Command-line options
readonly LONGOPTS=account-name:,account-key:,channel:,container-name:,file:,name:,version:,debug,help
readonly OPTIONS=a:k:l:c:f:n:v:dh

#########################################################################
# SCRIPT GLOBAL VARIABLES (internal, mutable)
# - lowercase with underscores
# - Set during argument parsing or initialization
#########################################################################
# Command-line arguments
account_name=""
account_key=""
channel="$CHANNEL_DEV"
container_name=""
file=""
log_level="$LOG_INFO"
name=""
version=""

log_info "Starting $SCRIPT_NAME"

# Parse arguments
temp=$(getopt --options=$OPTIONS \
    --longoptions=$LONGOPTS \
    --name "$0" \
    -- "$@") || exit 1
eval set -- "$temp"
unset temp
while true; do
    case "$1" in
        -a|--account-name)
            account_name="$2"
            shift 2
            ;;
        -k|--account-key)
            account_key="$2"
            shift 2
            ;;
        -l|--channel)
            channel="$2"
            shift 2
            ;;
        -c|--container-name)
            container_name="$2"
            shift 2
            ;;
        -f|--file)
            file="$2"
            shift 2
            ;;
        -n|--name)
            name="$2"
            shift 2
            ;;
        -d|--debug)
            log_level="$LOG_DEBUG"
            shift
            ;;
        -h|--help)
            show_help
            exit
            ;;
        -v|--version)
            version="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Unknown parameters"
            show_help
            exit 1
            ;;
    esac
done

# Apply defaults with precedence: CLI arg > ENV var > default
container_name="${container_name:-${DEFAULT_ARTIFACT_CONTAINER}}"
name="${name:-${DEFAULT_ARTIFACT_NAME}}"

validate_parameters "$@"
command=$1
case "$command" in
    upload_artifact)
        validate_upload_artifact_parameters "$@"
        upload_artifact "$file" "$account_name" "$account_key" "$container_name" "$name"
        exit 0
        ;;
    fetch_artifact)
        validate_fetch_artifact_parameters "$@"
        fetch_artifact "$account_name" "$account_key" "$container_name"  "$name"
        exit 0
        ;;
    build_image)
        validate_build_image_parameters "$@"
        build_image "$channel"
        exit 0
        ;;
    publish_image)
        login_acr
        publish_image "$version" "$channel"
        exit 0
        ;;
    upload_pipeline_config)
        upload_pipeline_config
        exit 0
        ;;
    deploy_container_instance)
        validate_deploy_container_instance_parameters "$@"
        deploy_container_instance "$version"
        exit 0
        ;;
    *)
        echo "Unknown command"
        show_help
        exit 1
        ;;
esac
