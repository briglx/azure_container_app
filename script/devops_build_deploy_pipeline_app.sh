#!/usr/bin/env bash
#########################################################################
# Deploy function app resources on cloud infrastructure.
# Usage: devops_build_deploy_pipeline_app.sh 
# Globals:
#   SUBSCRIPTION_ID
#   ENVIRONMENT
#   LOCATION
# Optional Globals:
#   MODEL_NAME
#   MODEL_VERSION
#   APP_INSTALLER_FILE
#   APP_FILE
#   APP_SETUP_ARGS
#   APP_ALIAS
# Params
#########################################################################

# Stop on errors
set -e

project_root="$(git rev-parse --show-toplevel)"
env_file="${project_root}/.env"
project_name=$(grep -oP '(?<=^name = ")[^"]+' "${project_root}/pyproject.toml"  | tr -d '\n')
project_version=$(grep -oP '(?<=^version = ")[^"]+' "${project_root}/pyproject.toml"  | tr -d '\n')
short_name=$(grep -oP '(?<=^short_name = ")[^"]+' "${project_root}/pyproject.toml"  | tr -d '\n')
resource_token=$(echo -n "${SUBSCRIPTION_ID}${project_name}${LOCATION}" | sha1sum | awk '{print $1}' | cut -c1-8)
short_env=$(echo "${ENVIRONMENT:0:1}" | tr '[:upper:]' '[:lower:]')
tags="asn=tbd project=$project_name owner=tbd environment=$ENVIRONMENT servicetier=tier3"

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
