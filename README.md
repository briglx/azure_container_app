# azure_container_app

Example project demonstraiting container apps that use a binary from an azure storage account

# Getting Started

Configre the environment variables. Copy `example.env` to `.env` and update the values.

## Create System Identities

The solution use system identities to deploy cloud resources. The following table lists the system identities and their purpose.

| System Identities      | Authentication                                             | Authorization                                                                                                                                                                  | Purpose                                                                                                          |
| ---------------------- | ---------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------- |
| TBD| TBD | TBD| TBD |

```bash
# Configure the environment variables. Copy `example.env` to `.env` and update the values
cp example.env .env
# load .env vars
[ ! -f .env ] || export $(grep -v '^#' .env | xargs)
# or this version allows variable substitution and quoted long values
[ -f .env ] && while IFS= read -r line; do [[ $line =~ ^[^#]*= ]] && eval "export $line"; done < .env

# Login to az. Only required once per install.
az login --tenant $AZURE_TENANT_ID --use-device-code
```

## Provision Resources

Typical system requirements are:
* 32 or 64-bit compatible CPU. A processor operating at 2.0 GHz or faster is recommended.
* 2 GB RAM is recommended
* 10GB disk

```bash
# Shared Resources
    # Container Registry
    # Storage Account - Shared Artifacts
# Solution Resources
    # Azure Container Instance
    # Storage Account - Application Working Files
    # File Shares - Networked mapped working files
```

This approach uses a centralized artifact store for binaries. Blob storage account is the artifact store
```bash
# Download your binary that needs to be deployed in the container as ARTIFACT_NAME. 
curl /path/to/files -o "$ARTIFACT_NAME"
# Upload to a shared artifact location in blob storage
az storage blob upload \
    --account-name "$COMMON_STORAGE_ACCOUNT" \
    --container-name "$SHARED_CONTAINER" \
    --name "$ARTIFACT_NAME" \
    --file "$ARTIFACT_NAME"
```

## Build and Deploy the Artifact

The build pipeline
* Fetch artifact
* Build image
* Publish Image
* Deploy Container

### Fetch Artifact
```bash
# Get Artifact Storage SAS Key
set +e
SAS_TOKEN=$(az storage container generate-sas \
    --account-name "$COMMON_STORAGE_ACCOUNT" \
    --name "$SHARED_CONTAINER" \
    --permission r \
    --expiry $(date -u -d "1 hour" '+%Y-%m-%dT%H:%MZ') \
    --auth-mode login \
    --as-user \
    --output tsv 2>&1)
set -e

artifact_path="https://${COMMON_STORAGE_ACCOUNT}.blob.core.windows.net/${SHARED_CONTAINER}/${ARTIFACT_FOLDER}/${ARTIFACT_NAME}?${SAS_TOKEN}"

rm -Rf ./temp
mkdir -p ./temp
curl -fsSL "${artifact_path}" -o "temp/${ARTIFACT_NAME}"
unzip -q "${ARTIFACT_NAME}" -d temp
```

### Build docker image
```bash
# Configure image version
model_name="$MODEL_NAME"
model_version="$MODEL_VERSION"
image="${model_name}_v${model_version}"

proj_version="${PROJ_VERSION}"
build_number=$(date +%Y%m%dT%H%M)
version="${proj_version}.dev${build_number}"

image_name="${image}:${version}"

project_root=$(git rev-parse --show-toplevel)
dockerfile_path="${project_root}/Dockerfile"

# Build image
DOCKER_BUILDKIT=1 docker buildx build \
    --platform linux/amd64 \
    --build-arg "RELEASE_VERSION=$version" \
    --build-arg "APP_INSTALLER_FILE=$APP_INSTALLER_FILE" \
    --build-arg "APP_FILE=$APP_FILE" \
    --build-arg "APP_SETUP_ARGS=$APP_SETUP_ARGS"  \
    -t "$image_name" -f "${dockerfile_path}" "${project_root}"

# Run container
docker run -p 5000:5000 "$image_name"

# Interactive shell
docker run -it --entrypoint /bin/bash -p 5000:5000  "$image_name"

```

### Push image

```bash
# Login to remote registry
docker login -u "$CONTAINER_REGISTRY_USERNAME" -p "$CONTAINER_REGISTRY_PASSWORD" "${CONTAINER_REGISTRY_NAME}.azurecr.io"

# Tag image
docker tag "${image}:${version}" "${image}:latest"
docker tag "${image}:${version}" "${CONTAINER_REGISTRY_NAME}.azurecr.io/${CONTAINER_REGISTRY_NAMESPACE}/${image}:${version}"
docker tag "${image}:latest" "${CONTAINER_REGISTRY_NAME}.azurecr.io/${CONTAINER_REGISTRY_NAMESPACE}/${image}:latest"

docker push "${CONTAINER_REGISTRY_NAME}.azurecr.io/${CONTAINER_REGISTRY_NAMESPACE}/${image}:${version}"
docker push "${CONTAINER_REGISTRY_NAME}.azurecr.io/${CONTAINER_REGISTRY_NAMESPACE}/${image}:latest"
```

### Deploy to Azure Container Instance
```bash
# Remove previous
az container delete \
    --resource-group "$ACI_RESOURCE_GROUP" \
    --name "$ACI_NAME" \
    --yes

# Create new instance
az container create \
    --resource-group "$ACI_RESOURCE_GROUP" \
    --name "$ACI_NAME" \
    --image "${CONTAINER_REGISTRY_NAME}.azurecr.io/${CONTAINER_REGISTRY_NAMESPACE}/${image}:${version}" \
    --cpu 1 --memory 1 \
    --restart-policy Never \
    --os-type Linux \
    --registry-login-server "${CONTAINER_REGISTRY_NAME}.azurecr.io" \
    --registry-username "$CONTAINER_REGISTRY_USERNAME" \
    --registry-password "$CONTAINER_REGISTRY_PASSWORD" \
    --azure-file-volume-account-name $NETWORK_SHARE_STORAGE_ACCOUNT \
    --azure-file-volume-account-key $NETWORK_SHARE_STORAGE_KEY \
    --azure-file-volume-share-name "share" \
    --azure-file-volume-mount-path /mnt/azurefiles

az container show \
    --resource-group "$ACI_RESOURCE_GROUP" \
    --name "$ACI_NAME" \
    --query 'containers[0].instanceView.currentState.exitCode'

# Interactive shell
az container exec \
  --resource-group "$ACI_RESOURCE_GROUP" \
  --name "$ACI_NAME" \
  --exec-command "/bin/bash"
```

# Notes

Various notes.

## Mounting network files in docker 

* At image build time
* At container create time
* At run time

```bash
# Get network storage key 
set +e
NETWORK_SHARE_STORAGE_KEY=$(az storage account keys list \
    --resource-group "$NETWORK_SHARE_RESOURCE_GROUP" \
    --account-name "$NETWORK_SHARE_STORAGE_ACCOUNT" \
    --query "[0].value" \
    --output tsv 2>&1)
set -e

# At Docker Build Time -----------------------------------------------------------------------------------
echo "$NETWORK_SHARE_STORAGE_KEY" > storage_key.txt
DOCKER_BUILDKIT=1 docker buildx build \
    --secret id=storage_key,src=storage_key.txt \
    --build-arg "RELEASE_VERSION=$version" \
    --build-arg "NETWORK_SHARE_STORAGE_ACCOUNT=$NETWORK_SHARE_STORAGE_ACCOUNT" \
    --build-arg "APP_INSTALLER_FILE=$APP_INSTALLER_FILE" \
    --build-arg "APP_FILE=$APP_FILE" \
    --build-arg "APP_SETUP_ARGS=$APP_SETUP_ARGS"  \
    -t "$image_name" -f "${dockerfile_path}" "${project_root}"
rm storage_key.txt

# Docker file has
RUN --mount=type=secret,id=storage_key mount -t cifs "//${NETWORK_SHARE_STORAGE_ACCOUNT}.file.core.windows.net/share" \
        /mnt/azurefiles \
        -o "vers=3.0,username=${NETWORK_SHARE_STORAGE_ACCOUNT},password=$(cat /run/secrets/storage_key),dir_mode=0777,file_mode=0777,serverino"

# At Container Create Time - Via Mounting fileshare
az container create \
    ... \
    --azure-file-volume-account-name $NETWORK_SHARE_STORAGE_ACCOUNT \
    --azure-file-volume-account-key $NETWORK_SHARE_STORAGE_KEY \
    --azure-file-volume-share-name "share" \
    --azure-file-volume-mount-path /mnt/azurefiles


# At Run Time - mount on host and run with volumn ------------------------------------------------
sudo mkdir -p /mnt/azurefiles 
sudo mount -t cifs //${NETWORK_SHARE_STORAGE_ACCOUNT}.file.core.windows.net/share \
    /mnt/azurefiles \
    -o "vers=3.0,username=${NETWORK_SHARE_STORAGE_ACCOUNT},password="$NETWORK_SHARE_STORAGE_KEY",dir_mode=0777,file_mode=0777,serverino"

docker run -p 5000:5000 -v /mnt/azurefiles:/mnt/azurefiles "$image_name"

# Interactive shell
docker run -it --entrypoint /bin/bash -p 5000:5000  -v /mnt/azurefiles:/mnt/azurefiles "$image_name"

```

## Azure Key Vault

General use
```bash
# Verify RBAC auth
az keyvault show \
    --name "$KEY_VAULT_NAME" \
    --query properties.enableRbacAuthorization

# Set role to a user - Dev only use case
assignee_id=$(az ad signed-in-user show --query id -o tsv)
az role assignment create \
  --role "Key Vault Secrets Officer" \
  --assignee "$assignee_id" \
  --scope $(az keyvault show --name "$KEY_VAULT_NAME" --query id -o tsv)
```

Storing and getting secrets
```bash

# Secret name
acr_password_name="acr-${CONTAINER_REGISTRY_NAME}-${CONTAINER_REGISTRY_USERNAME}-password"

# Set ACR password
az keyvault secret set \
    --vault-name "$KEY_VAULT_NAME" \
    --name "$acr_password_name" \
    --value "$CONTAINER_REGISTRY_PASSWORD"

# Get ACR password
CONTAINER_REGISTRY_PASSWORD=$(az keyvault secret show --vault-name "$KEY_VAULT_NAME" --name "$acr_password_name" --query value -o tsv)
```
