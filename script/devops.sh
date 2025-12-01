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
    echo "      -c, --container-name   (Optional) Blob container name. Default: "$DEFAULT_ARTIFACT_CONTAINER""
    echo "      -f, --file             Local file path to upload"
    echo "      -n, --name             (Optional) Target name in blob storage. Default: "${SHORT_NAME}/artifact.zip""
    echo ""
    echo "  fetch_artifact Fetch an artifact from Azure Blob Storage."
    echo "      -a, --account-name     Storage account name"
    echo "      -k, --account-key      Storage account key"
    echo "      -c, --container-name   (Optional) Blob container name. Default: "$DEFAULT_ARTIFACT_CONTAINER""
    echo "      -n, --name             (Optional) Target name in blob storage. Default: "${SHORT_NAME}/artifact.zip""
    echo ""
    echo "   build_image Build a Docker image for the application."
    echo "      -n, --name             Name of the Docker image to build."
    echo "      -l, --channel          Release channel (dev or release). Default: "$CHANNEL_DEV""
    echo ""
    echo "   publish_image Publish a Docker image to Azure Container Registry."
    echo "      -v, --version          Version tag for the Docker image."
    echo ""
    echo "Example usage:"
    echo "  $0 upload_artifact -a mystorageaccount -k myaccountkey -c mycontainer -f ./local/artifact.zip -n myfolder/myartifact.zip"
    echo "  $0 fetch_artifact -a mystorageaccount -k myaccountkey -c mycontainer -n myfolder/myartifact.zip"
    echo "  $0 build_image -n myappimage -l dev"
    echo "  $0 publish_image -v 1.0.0"
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

validate_provision_parameters(){

    # Validate required environment variables
    if [ -z "$SUBSCRIPTION_ID" ]; then
        log_error "SUBSCRIPTION_ID is not set. Please set the Azure Subscription ID." >&2
        exit 1
    fi
    if [ -z "$ENVIRONMENT" ]; then
        log_error "ENVIRONMENT is not set. Please set the deployment environment (e.g., dev, test, prod)." >&2
        exit 1
    fi
    if [ -z "$LOCATION" ]; then
        log_error "LOCATION is not set. Please set the Azure region/location." >&2
        exit 1
    fi
    if [ -z "$MODEL_NAME" ]; then
        log_error "MODEL_NAME is not set. Please set the Key Vault name." >&2
        exit 1
    fi
    if [ -z "$MODEL_VERSION" ]; then
        log_error "MODEL_VERSION is not set. Please set the Key Vault name." >&2
        exit 1
    fi
    if [ -z "$APP_INSTALLER_FILE" ]; then
        log_error "APP_INSTALLER_FILE is not set. Please set the Key Vault name." >&2
        exit 1
    fi
    if [ -z "$APP_FILE" ]; then
        log_error "APP_FILE is not set. Please set the Key Vault name." >&2
        exit 1
    fi
    if [ -z "$APP_SETUP_ARGS" ]; then
        log_error "APP_SETUP_ARGS is not set. Please set the Key Vault name." >&2
        exit 1
    fi
    if [ -z "$APP_ALIAS" ]; then
        log_error "APP_ALIAS is not set. Please set the Key Vault name." >&2
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


upload_artifact(){
    local local_file="$1"
    local account_name="$2"
    local account_key="$3"
    local container_name="$4"
    local target_name="$5"

    log_info "Upload artifact."
    log_debug "Upload artifact $local_file to ${account_name}/${container_name}/${target_name}."

    set +e
    results=$(az storage blob upload \
        --account-name "$account_name" \
        --container-name "$container_name" \
        --file "$local_file" \
        --name "${target_name}" \
        --account-key "$account_key" \
        --overwrite true \
        --only-show-errors \
        --no-progress 2>&1)
    set -e

    log_debug "$results"
    
    # Save file if LOG_DEBUG is enabled
    if [[ $log_level -ge $LOG_DEBUG ]]; then
        log_debug "Saving result to az_storage_blob_upload.log."
        echo $results >> "${PROJECT_ROOT}/.deploy_log/az_storage_blob_upload.log"
    fi

    # Check for errors in the results
    if grep -q "ERROR" <<< "$results"; then
        log_error "${command^} failed due to an error."
        log_error "$results"
        exit 1
    fi

    # Check if success message is present
    last_modified=$(echo "$results" | jq -r '.lastModified')
    if [[ -z "$last_modified" || "$last_modified" == "null" ]]; then
        log_error "${command^} failed. No lastModified timestamp found."
        log_error "$results"
        exit 1
    fi
    
    log_info "Succesfully uploaded artifact." 
    log_debug "Succesfully uploaded artifact ${artifact_name} uploaded to ${account_name}/${container_name}/${target_name}." 

}

fetch_artifact(){
    local account_name="$1"
    local account_key="$2"
    local container_name="$3"
    local artifact_name="$4"
    local results
    local artifact_sas_token
    local artifact_path

    log_info "Fetch artifact."
    log_debug "Fetch artifact from ${account_name}/${container_name}/${artifact_name}."

    # Fetch Artifact
    set +e
    results=$(az storage container generate-sas \
        --name "${container_name}" \
        --auth-mode key \
        --account-key "${account_key}" \
        --account-name "${account_name}" \
        --permission r \
        --expiry "$(date -u -d "5 minutes" '+%Y-%m-%dT%H:%MZ')" \
        --only-show-errors \
        --output tsv 2>&1)
    set -e

    log_debug "$results"

    # Save file if LOG_DEBUG is enabled
    if [[ $log_level -ge $LOG_DEBUG ]]; then
        log_debug "Saving result to az_storage_container_generate_sas.log."
        echo "$results" >> "${PROJECT_ROOT}/.deploy_log/az_storage_container_generate_sas.log"
    fi

    # Check for errors in the results
    if grep -q "ERROR" <<< "$results"; then
        log_error "${command^} failed due to an error."
        log_error "$results"
        exit 1
    fi

    # Check if valid sas token
    if [[ "$results" == *"sig="* && "$results" == *"se="* ]]; then
        log_debug "SAS token generated successfully."
    else
        log_error "${command^} failed. Invalid SAS token generated."
        log_error "$results"
        exit 1
    fi

    artifact_sas_token="$results"
    artifact_path="https://${account_name}.blob.core.windows.net/${container_name}/${artifact_name}"
    
    # Create temp directory and download artifact
    log_info "Downloading artifact."
    log_debug "Downloading artifact from ${artifact_path} to temp.zip."
    mkdir -p .artifact_cache
    curl -fsSL "${artifact_path}?${artifact_sas_token}" -o "temp.zip"

    log_info "Unzipping artifact to .artifact_cache."
    unzip -qo "temp.zip" -d .artifact_cache
    rm -f "temp.zip"

    log_info "Succesfully fetched artifact." 
    log_debug "Succesfully fetched artifact from ${account_name}/${container_name}/${artifact_name}." 

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
    local key_vault_name="${1:-${KEY_VAULT_NAME:-}}"
    
    # Validate input
    if [[ -z "$key_vault_name" ]]; then
        log_error "Key Vault name not provided. Pass as argument or set SHARED_KEY_VAULT_NAME"
        return 1
    fi

    log_info "Authenticating to Azure Container Registry"
    log_info "Using Key Vault: $key_vault_name"

    local registry_name
    local registry_username
    local registry_password

    if ! registry_name=$(get_keyvault_secret "$key_vault_name" "SharedContainerRegistryName"); then
        return 2
    fi

    if ! registry_username=$(get_keyvault_secret "$key_vault_name" "SharedContainerRegistryUsername"); then
        return 2
    fi

    if ! registry_password=$(get_keyvault_secret "$key_vault_name" "SharedContainerRegistryPassword"); then
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
    dockerfile_path="${PROJECT_ROOT}/pipeline_app/Dockerfile"

    log_debug "Building image: $image_name for dockerfile_path: $dockerfile_path."

    # Build image
    DOCKER_BUILDKIT=1 docker buildx build \
        --platform linux/amd64 \
        --build-arg "RELEASE_VERSION=$version" \
        --build-arg "APP_INSTALLER_FILE=$APP_INSTALLER_FILE" \
        --build-arg "APP_FILE=$APP_FILE" \
        --build-arg "APP_SETUP_ARGS=$APP_SETUP_ARGS"  \
        --build-arg "APP_ALIAS=$APP_ALIAS" \
        -t "$image_name" -f "${dockerfile_path}" "${PROJECT_ROOT}"


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

}

publish_image(){
    local version="$1"
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

#########################################################################
# SCRIPT CONSTANTS (internal, read-only)
# - ALL_CAPS with underscores
# - ALWAYS use 'readonly' keyword
#########################################################################
# General
readonly PROJECT_ROOT="$(git rev-parse --show-toplevel)"
readonly SHORT_NAME=$(grep -oP '(?<=^short_name = ")[^"]+' "${PROJECT_ROOT}/pyproject.toml"  | tr -d '\n')
readonly PROJECT_VERSION=$(grep -oP '(?<=^version = ")[^"]+' "${PROJECT_ROOT}/pyproject.toml"  | tr -d '\n')
readonly SCRIPT_NAME="$(basename "$0")"
readonly IMAGE="${MODEL_NAME}_v${MODEL_VERSION}"
readonly BUILD_NUMBER=$(date +%Y%m%dT%H%M)
readonly DOCKERFILE="${PROJECT_ROOT}/pipeline_app/Dockerfile"
readonly CONTAINER_REGISTRY_NAMESPACE="aimodelserving"
readonly ENV_FILE="${PROJECT_ROOT}/.env"
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
        publish_image "$version"
        exit 0
        ;;
    *)
        echo "Unknown command"
        show_help
        exit 1
        ;;
esac
