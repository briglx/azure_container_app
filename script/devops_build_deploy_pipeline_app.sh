#!/usr/bin/env bash
#########################################################################
# Deploy function app resources on cloud infrastructure.
# Usage: devops_build_deploy_pipeline_app.sh 
# Globals:
#   SUBSCRIPTION_ID
#   ENVIRONMENT
#   LOCATION
#   MODEL_NAME
#   MODEL_VERSION
#   APP_INSTALLER_FILE
#   APP_FILE
#   APP_SETUP_ARGS
#   APP_ALIAS
#   ARTIFACT_CONTAINER
#   ARTIFACT_STORAGE_KEY
#   ARTIFACT_STORAGE_ACCOUNT
#   ARTIFACT_FOLDER
#   ARTIFACT_NAME
#   CONTAINER_REGISTRY_USERNAME
#   CONTAINER_REGISTRY_PASSWORD
# Optional Globals:
# Params
#########################################################################

# Stop on errors
set -e

log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

validate_provision_parameters(){

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
    if [ -z "$MODEL_NAME" ]; then
        echo "Error: MODEL_NAME is not set. Please set the Key Vault name." >&2
        exit 1
    fi
    if [ -z "$MODEL_VERSION" ]; then
        echo "Error: MODEL_VERSION is not set. Please set the Key Vault name." >&2
        exit 1
    fi
    if [ -z "$APP_INSTALLER_FILE" ]; then
        echo "Error: APP_INSTALLER_FILE is not set. Please set the Key Vault name." >&2
        exit 1
    fi
    if [ -z "$APP_FILE" ]; then
        echo "Error: APP_FILE is not set. Please set the Key Vault name." >&2
        exit 1
    fi
    if [ -z "$APP_SETUP_ARGS" ]; then
        echo "Error: APP_SETUP_ARGS is not set. Please set the Key Vault name." >&2
        exit 1
    fi
    if [ -z "$APP_ALIAS" ]; then
        echo "Error: APP_ALIAS is not set. Please set the Key Vault name." >&2
        exit 1
    fi
}

fetch_artifact(){
    local artifact_sas_token
    local artifact_path
    # Fetch Artifact
    artifact_sas_token=$(az storage container generate-sas \
        --name "${ARTIFACT_CONTAINER}" \
        --auth-mode key \
        --account-key "${ARTIFACT_STORAGE_KEY}" \
        --account-name "${ARTIFACT_STORAGE_ACCOUNT}" \
        --permission r \
        --expiry "$(date -u -d "5 minutes" '+%Y-%m-%dT%H:%MZ')" \
        --output tsv 2>&1)
        
    artifact_path="https://${ARTIFACT_STORAGE_ACCOUNT}.blob.core.windows.net/${ARTIFACT_CONTAINER}/${ARTIFACT_FOLDER}/${ARTIFACT_NAME}?${artifact_sas_token}"
    
    # Create temp directory and download artifact
    mkdir -p .artifact_cache
    curl -fsSL "${artifact_path}" -o "${ARTIFACT_NAME}"
    unzip -q "${ARTIFACT_NAME}" -d .artifact_cache

}

# build_docker_image(){
#     # Configure image version
#     local version="$1"
#     local app_installer_file="$2"
#     local app_file="$3"
#     local app_setup_args="$4"
#     local app_alias="$5"
#     local image_name="$6"
#     local dockerfile_path="$7"
#     local project_root="$8"

#     # Build image
#     echo DOCKER_BUILDKIT=1 docker buildx build \
#         --platform linux/amd64 \
#         --build-arg "RELEASE_VERSION=$version" \
#         --build-arg "APP_INSTALLER_FILE=${app_installer_file}" \
#         --build-arg "APP_FILE=${app_file}" \
#         --build-arg "APP_SETUP_ARGS=${app_setup_args}"  \
#         --build-arg "APP_ALIAS=${app_alias}" \
#         -t "$image_name" -f "${dockerfile_path}" "${project_root}"
# }

# Retrieve secret from Azure Key Vault
get_keyvault_secret() {
    local vault_name="$1"
    local secret_name="$2"
    local secret_value

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
    local key_vault_name="${1:-${SHARED_KEY_VAULT_NAME:-}}"
    

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

project_root="$(git rev-parse --show-toplevel)"
project_version=$(grep -oP '(?<=^version = ")[^"]+' "${project_root}/pyproject.toml"  | tr -d '\n')

model_name="$MODEL_NAME"
model_version="$MODEL_VERSION"
image="${model_name}_v${model_version}"

build_number=$(date +%Y%m%dT%H%M)
version="${project_version}.dev${build_number}"

image_name="${image}:${version}"

dockerfile_path="${project_root}/pipeline_app/Dockerfile"

validate_provision_parameters

# fetch_artifact

# build_docker_image \
#     "$version" \
#     "$APP_INSTALLER_FILE" \
#     "$APP_FILE" \
#     "$APP_SETUP_ARGS" \
#     "$APP_ALIAS" \
#     "$image_name" \
#     "$dockerfile_path" \
#     "$project_root"

# Build image
# DOCKER_BUILDKIT=1 docker buildx build \
#     --platform linux/amd64 \
#     --build-arg "RELEASE_VERSION=$version" \
#     --build-arg "APP_INSTALLER_FILE=$APP_INSTALLER_FILE" \
#     --build-arg "APP_FILE=$APP_FILE" \
#     --build-arg "APP_SETUP_ARGS=$APP_SETUP_ARGS"  \
#     --build-arg "APP_ALIAS=$APP_ALIAS" \
#     -t "$image_name" -f "${dockerfile_path}" "${project_root}"

login_acr "$KEY_VAULT_NAME"


