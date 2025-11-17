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
# Optional Globals:
# Params
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

project_root="$(git rev-parse --show-toplevel)"
project_version=$(grep -oP '(?<=^version = ")[^"]+' "${project_root}/pyproject.toml"  | tr -d '\n')

model_name="$MODEL_NAME"
model_version="$MODEL_VERSION"
image="${model_name}_v${model_version}"

build_number=$(date +%Y%m%dT%H%M)
version="${project_version}.dev${build_number}"

image_name="${image}:${version}"

dockerfile_path="${project_root}/pipeline_app/Dockerfile"

# Build image
DOCKER_BUILDKIT=1 docker buildx build \
    --platform linux/amd64 \
    --build-arg "RELEASE_VERSION=$version" \
    --build-arg "APP_INSTALLER_FILE=$APP_INSTALLER_FILE" \
    --build-arg "APP_FILE=$APP_FILE" \
    --build-arg "APP_SETUP_ARGS=$APP_SETUP_ARGS"  \
    --build-arg "APP_ALIAS=$APP_ALIAS" \
    -t "$image_name" -f "${dockerfile_path}" "${project_root}"
