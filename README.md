# File Processing Pipeline

Example project demonstrating an automated workflow for file processing. Uploading a file triggers a containerized application that processes the file and writes results back to the storage account.

![Architecture Overview](./docs/architecture_overview.drawio.svg)

# Getting Started

Configure the environment variables. Copy `example.env` to `.env` and update the values.

## Create System Identities

The solution use system identities to deploy cloud resources. The following table lists the system identities and their purpose.

| System Identities      | Authentication                                             | Details |
| -----------------------| ---------------------------------------------------------- | --------|
| `env.CICD_CLIENT_NAME` | OpenId Connect (OIDC) based Federated Identity Credentials | `{"subject":"repo:$GITHUB_ORG/$GITHUB_REPO:environment:$ENVIRONMENT"}` |

Role Detail for `env.CICD_CLIENT_NAME` to provision shared resources

| Permission Scope | Purpose | Built in Role | Least Privlage |
| --- | --- | --- | --- |
| `/subscription/sub-common/` | Provision Shared Resources - Resource Group | `Subscription Contributor` | <ul><li>`Microsoft.Resources/subscriptions/resourceGroups/write`</li></ul> |
| `/subscription/sub-common/resource_group/rg-common/` | Provision Shared Artifact Store - Storage Account | `Storage Account Contributor` | <ul><li>`Microsoft.Storage/storageAccounts/read`</li><li>`Microsoft.Storage/storageAccounts/write`</li></ul> |
| `/subscription/sub-common/resource_group/rg-common/storage/startifacts` | Provision Artifact Container - Storage Account Container | `Storage Blob Data Contributor` | <ul><li>`Microsoft.Storage/storageAccounts/blobServices/containers/read`</li><li>`Microsoft.Storage/storageAccounts/blobServices/containers/write`</li></ul> |
| `/subscription/sub-common/resource_group/rg-common/` | Provision Shared Container Registry | `Owner` or `Contributor` | <ul><li>`Microsoft.ContainerRegistry/registries/read`</li><li>`Microsoft.ContainerRegistry/registries/write`</li></ul> |
| `/subscription/sub-common/resource_group/rg-common/crcommon` | Create ACR Credential to Push or pull artifacts | `AcrPush` | <ul><li>`Microsoft.ContainerRegistry/registries/pull/read`</li><li>`Microsoft.ContainerRegistry/registries/pull/write`</li></ul> |
| `/subscription/sub-common/resource_group/rg-common/` | Provision Shared Monitoring | `Log Analytics Contributor` | <ul><li>`Microsoft.OperationalInsights/workspaces/read`</li><li>`Microsoft.OperationalInsights/workspaces/write`</li></ul> |
| `/subscription/sub-common/resource_group/rg-common/` | Provision Shared Key Vault | `Key Vault Contributor` | <ul><li>`"Microsoft.KeyVault/vaults/write`</li></ul> |
| `/subscription/sub-common/resource_group/rg-common/keyvault/kv-common` | Set Shared secrets | `Key Vault Secrets Officer` | <ul><li>`Microsoft.KeyVault/vaults/secrets/setSecret/action`</li></ul> |

Role Detail for `env.CICD_CLIENT_NAME` to provision solution resources
| Permission Scope | Purpose | Built in Role | Least Privlage |
| --- | --- | --- | --- |
|  `/subscription/sub-solution/`  | Provision Solution Resources - Resource Group  | `Subscription Contributor`  | <ul><li>`Microsoft.Resources/subscriptions/resourceGroups/write`</li></ul> |
| `/subscription/sub-solution/resource_group/rg-solution/` | Provision Primary and Function App Storage Accounts| `Storage Account Contributor` | <ul><li>`Microsoft.Storage/storageAccounts/read`</li><li>`Microsoft.Storage/storageAccounts/write`</li></ul> |
| `/subscription/sub-solution/resource_group/rg-solution/storage/stprimary` | Provision Pipeline Container - Storage Account Container | `Storage Blob Data Contributor` | <ul><li>`Microsoft.Storage/storageAccounts/blobServices/containers/read`</li><li>`Microsoft.Storage/storageAccounts/blobServices/containers/write`</li></ul> |
| `/subscription/sub-solution/resource_group/rg-solution/storage/stprimary` | Provision Default Directories - Storage Account Blobs | `Storage Blob Data Contributor` | <ul><li>`Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read`</li><li>`Microsoft.Storage/storageAccounts/blobServices/containers/blobs/write`</li></ul> |
| `/subscription/sub-solution/resource_group/rg-solution/storage/stprimary` | Provision Shared - Storage Account Share | `Storage File Data SMB Share Contributor` | <ul><li>`Microsoft.Storage/storageAccounts/fileServices/shares/write`</li></ul> |
| `/subscription/sub-solution/resource_group/rg-solution/` | Event Grid Topic | `EventGrid Contributor` | <ul><li>`Microsoft.EventGrid/systemTopics/write`</li></ul> |
| `/subscription/sub-solution/resource_group/rg-solution/storage/stprimary` | Event Grid Topic | `Reader` | <ul><li>`Microsoft.EventGrid/systemTopics/eventSubscriptions/read`</li></ul> |
| `/subscription/sub-solution/resource_group/rg-solution/storage/stprimary` | Configure Function app to read storage content | `Storage Account Key Operator Service Role` | <ul><li>`Microsoft.Storage/storageAccounts/listkeys/action`</li></ul> |
| `/subscription/sub-solution/resource_group/rg-solution/systemTopics/evgstprimary/eventSubscriptions/evgsblob2func` | Configure Event Grid Subscription | `EventGrid EventSubscription Contributor` | <ul><li>`Microsoft.EventGrid/systemTopics/eventSubscriptions/write`</li></ul> |
| `/subscription/sub-solution/resource_group/rg-solution/systemTopics/evgstprimary` | Configure Event Grid Subscription | `EventGrid EventSubscription Contributor` | <ul><li>`Microsoft.EventGrid/systemTopics/write`</li></ul> |
| `/subscription/sub-solution/resource_group/rg-solution/` | Provision Solution Primary Storage Account | `Storage Account Contributor` | <ul><li>`Microsoft.Storage/storageAccounts/read`</li><li>`Microsoft.Storage/storageAccounts/write`</li></ul> |
| `/subscription/sub-common/resource_group/rg-common/keyvault/kv-common`  | Read Shared secrets | `Key Vault Secrets User` | <ul><li>`Microsoft.KeyVault/vaults/secrets/getSecret/action`</li></ul> |
| `/subscription/sub-solution/resource_group/rg-solution/`   | Read Shared secrets | `Application Insights Component Contributor` | <ul><li>`microsoft.insights/components/read`</li><li>`microsoft.insights/components/write`</li></ul> |
| `/subscription/sub-solution/resource_group/rg-solution/`   | Create function app | `Website Contributor` | <ul><li>`Microsoft.Web/sites/read`</li><li>`Microsoft.Web/sites/write`</li><li>`Microsoft.Web/sites/config/write`</li></ul> |
| `/subscription/sub-solution/resource_group/rg-solution/func-app`   | Configure Event trigger | `Website Contributor` | <ul><li>`Microsoft.Web/sites/host/listkeys/action`</li></ul> |

Admin level roles
| Permission Scope | Purpose | Built in Role | Least Privlage |
| --- | --- | --- | --- |
|  `/subscription/sub-solution/`  | Register Container Instance resource provider  | `Subscription Contributor`  | <ul><li>`Microsoft.Resources/subscriptions/resourceProviders/register/action`</li></ul> |

```bash
# Configure the environment variables. Copy `example.env` to `.env` and update the values
cp example.env .env
# load .env vars
[ ! -f .env ] || export $(grep -v '^#' .env | xargs)
# or this version allows variable substitution and quoted long values
[ -f .env ] && while IFS= read -r line; do [[ $line =~ ^[^#]*= ]] && eval "export $line"; done < .env

# Login to az. Only required once per install.
az login --tenant "$AZURE_TENANT_ID" --use-device-code

# Create CICD System Identity
./script/create_cicd_sp.sh
# Adds output vars to .env
```

## Provision Resources

Typical system requirements are:
* 32 or 64-bit compatible CPU. A processor operating at 2.0 GHz or faster is recommended.
* 2 GB RAM is recommended
* 10GB disk

Shared Resources
* Resource Group
* Storage Account - Shared Artifacts
* Container Registry
* Log Analytics Workspace

```bash
# Provision Shared Resources
./script/devops_provision_shared.sh
# Adds output vars to .env and common keyvault
```

Solution Resources
* Solution Resource Group
* Azure Container Instance (TBD)
* Primary Storage Account - Application Working Files
* Function app - See [func_app](./func_app/README.md)
* Event Grid
```bash
./script/devops_provision.sh
```

This approach uses a centralized artifact store for binaries. Blob storage account is the artifact store
```bash
# Download your binary that needs to be deployed in the container as ARTIFACT_NAME.
curl /path/to/files -o "$ARTIFACT_NAME"

# Upload to a shared artifact location in blob storage
local_file="/path/to/$ARTIFACT_NAME"
target_file="${ARTIFACT_FOLDER}/${ARTIFACT_NAME}"
./script/devops.sh upload_artifact \
    --file "$local_file" \
    --account-name "$ARTIFACT_STORAGE_ACCOUNT" \
    --account-key "$ARTIFACT_STORAGE_ACCOUNT_KEY" \
    --container-name "$ARTIFACT_CONTAINER" \
    --name "$target_file"

# Or with defaults
./script/devops.sh upload_artifact \
    --file "$local_file" \
    --account-name "$ARTIFACT_STORAGE_ACCOUNT" \
    --account-key "$ARTIFACT_STORAGE_ACCOUNT_KEY"
```

## Build and Deploy the Pipeline App

The build pipeline
* Fetch artifact
* Build image
* Publish Image
* Deploy Configs
* Deploy Container

### Fetch Artifact
```bash
target_file="${ARTIFACT_FOLDER}/${ARTIFACT_NAME}"
./script/devops.sh fetch_artifact \
    --account-name "$ARTIFACT_STORAGE_ACCOUNT" \
    --account-key "$ARTIFACT_STORAGE_ACCOUNT_KEY" \
    --container-name "$ARTIFACT_CONTAINER" \
    --name "$target_file"

# Or with defaults
./script/devops.sh fetch_artifact \
    --account-name "$ARTIFACT_STORAGE_ACCOUNT" \
    --account-key "$ARTIFACT_STORAGE_ACCOUNT_KEY"
```

### Build docker image
```bash
# Save version to use in next step
version=$(./script/devops.sh build_image \
    --channel dev \
    --debug)
```

### Push image
```bash
# Login to remote registry
# docker login -u "$CONTAINER_REGISTRY_USERNAME" -p "$CONTAINER_REGISTRY_PASSWORD" "${CONTAINER_REGISTRY_NAME}.azurecr.io"
./script/devops.sh publish_image \
    --tag "$IMAGE_TAG" \
    --debug
```

### Deploy Configs
```bash
# Copy app configs to storage share
./script/devops.sh upload_pipeline_config \
    --debug
```

### Deploy to Azure Container Instance
```bash
./script/devops.sh deploy_container_instance \
    --tag "$IMAGE_TAG" \
    --debug
```

## Build and Deploy the Function App
```bash
./script/devops.sh deploy_function_app \
    --debug

# Trigger app by uploading a test file
./script/devops_create_testfile.sh
```

# Development

Use the following commands to setup your environment.

```bash
# Configure the environment variables. Copy example.env to .env and update the values
cp example.env .env

# load .env vars
# [ ! -f .env ] || export $(grep -v '^#' .env | xargs)
# or this version allows variable substitution and quoted long values
# [ -f .env ] && while IFS= read -r line; do [[ $line =~ ^[^#]*= ]] && eval "export $line"; done < .env

# Create and activate a python virtual environment
# Windows
# C:\Users\!Admin\AppData\Local\Programs\Python\Python312\python.exe -m venv .venv
# .venv\scripts\activate

# Linux
python3.12 -m venv .venv
source .venv/bin/activate

# Update pip
python -m pip install --upgrade pip

# Install dependencies
pip install -r requirements_dev.txt

# Configure linting and formatting tools
sudo apt-get update
sudo apt-get install -y shellcheck
pre-commit install
```
## Running the Application

Run the application locally after building the image.

```bash
# Run container locally
docker run -p 5000:5000 "$image_name"

# Run locally with Interactive shell
docker run -it --entrypoint /bin/bash -p 5000:5000  "$image_name"
```

Once your container instance has been deployed, you can manually start it and connect for interactive debugging or runtime inspection.

> **Prerequisite**
> Ensure your user or service principal has the following Azure role:
> **`Microsoft.ContainerInstance/containerGroups/start/action`**
> **`Microsoft.ContainerInstance/containerGroups/containers/exec/action`**
> **`Microsoft.ContainerInstance/containerGroups/restart/action`**
> These permission are included in the **Contributor** or **Azure Container Instance Contributor** roles.

```bash
# If the container is in a **Terminated** or **Stopped** state, use the following command to start it:
az container start \
    --resource-group "$ACI_RESOURCE_GROUP" \
    --name "$ACI_NAME"

# Connect to the Running Container with an Interactive shell
az container exec \
  --resource-group "$ACI_RESOURCE_GROUP" \
  --name "$ACI_NAME" \
  --exec-command "/bin/bash"

az container show \
    --resource-group "$ACI_RESOURCE_GROUP" \
    --name "$ACI_NAME" \
    --query 'containers[0].instanceView.currentState.state'
```

## Style Guidelines

Summary of the most relevant points:

- Comments should be full sentences and end with a period.
- Constants and the content of lists and dictionaries should be in alphabetical order.
- It is advisable to adjust IDE or editor settings to match those requirements.

## Testing

```bash
# Run linters with pre-commit
pre-commit run --hook-stage manual isort --all-files
pre-commit run --hook-stage manual ruff-check --all-files
pre-commit run --hook-stage manual yamllint --all-files

pre-commit run --hook-stage manual check-shebang-scripts-are-executable --all-files
pre-commit run --hook-stage manual check-executables-have-shebangs --all-files
pre-commit run --hook-stage manual check-toml --all-files
pre-commit run --hook-stage manual check-json --all-files
pre-commit run --hook-stage manual end-of-file-fixer --all-files
pre-commit run --hook-stage manual fix-byte-order-marker --all-files
pre-commit run --hook-stage manual mixed-line-ending --all-files
pre-commit run --hook-stage manual trailing-whitespace --all-files
pre-commit run --hook-stage manual codespell --all-files
pre-commit run --hook-stage manual shellcheck --all-files
pre-commit run --hook-stage manual hadolint-docker --all-files

# Run linters outside of pre-commit
isort .
ruff check --fix
ruff format
codespell
yamllint .
shellcheck -x ./script/*.sh
docker run --rm -i hadolint/hadolint < Dockerfile
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
APP_STORAGE_KEY=$(az storage account keys list \
    --resource-group "$APP_STORAGE_RG" \
    --account-name "$APP_STORAGE_ACCOUNT_NAME" \
    --query "[0].value" \
    --output tsv 2>&1)
set -e

# At Docker Build Time -----------------------------------------------------------------------------------
echo "$APP_STORAGE_KEY" > storage_key.txt
DOCKER_BUILDKIT=1 docker buildx build \
    --secret id=storage_key,src=storage_key.txt \
    --build-arg "RELEASE_VERSION=$version" \
    --build-arg "APP_STORAGE_ACCOUNT_NAME=$APP_STORAGE_ACCOUNT_NAME" \
    --build-arg "APP_INSTALLER_FILE=$APP_INSTALLER_FILE" \
    --build-arg "APP_FILE=$APP_FILE" \
    --build-arg "APP_SETUP_ARGS=$APP_SETUP_ARGS"  \
    -t "$image_name" -f "${dockerfile_path}" "${project_root}"
rm storage_key.txt

# Docker file has
RUN --mount=type=secret,id=storage_key mount -t cifs "//${APP_STORAGE_ACCOUNT_NAME}.file.core.windows.net/share" \
        /mnt/azurefiles \
        -o "vers=3.0,username=${APP_STORAGE_ACCOUNT_NAME},password=$(cat /run/secrets/storage_key),dir_mode=0777,file_mode=0777,serverino"

# At Container Create Time - Via Mounting fileshare
az container create \
    ... \
    --azure-file-volume-account-name $APP_STORAGE_ACCOUNT_NAME \
    --azure-file-volume-account-key $APP_STORAGE_KEY \
    --azure-file-volume-share-name "share" \
    --azure-file-volume-mount-path /mnt/azurefiles


# At Run Time - mount on host and run with volume ------------------------------------------------
sudo mkdir -p /mnt/azurefiles
sudo mount -t cifs //${APP_STORAGE_ACCOUNT_NAME}.file.core.windows.net/share \
    /mnt/azurefiles \
    -o "vers=3.0,username=${APP_STORAGE_ACCOUNT_NAME},password="$APP_STORAGE_KEY",dir_mode=0777,file_mode=0777,serverino"

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

## Event Grid

```bash
# Threw error connecting to endpoint
az eventgrid system-topic event-subscription create \
    --name "${eventgrid_event_subscription_name}-b" \
    --resource-group "$rg_name" \
    --system-topic-name "$eventgrid_system_topic_name" \
    --endpoint "https://${FUNC_APP_NAME}.azurewebsites.net/runtime/webhooks/blobs" \
    --endpoint-type webhook \
    --included-event-types Microsoft.Storage.BlobCreated
    # --subject-begins-with "/blobServices/default/containers/$APP_STORAGE_CONTAINER"

#  Didn't work with Blob trigger. Did work with event_grid_trigger
az eventgrid system-topic event-subscription create \
    --name "$eventgrid_event_subscription_name" \
    --resource-group "$rg_name" \
    --system-topic-name "$eventgrid_system_topic_name" \
    --endpoint "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${FUNC_APP_RG}/providers/Microsoft.Web/sites/${FUNC_APP_NAME}/functions/${FUNC_NAME}" \
    --endpoint-type azurefunction \
    --included-event-types Microsoft.Storage.BlobCreated \
    --subject-begins-with "/blobServices/default/containers/${APP_STORAGE_CONTAINER}/blobs/${APP_STORAGE_INPUT_PATH}"

# All in one
# az eventgrid event-subscription create \
#    --name "$eventgrid_event_subscription_name" \
#    --resource-group "$rg_name" \
#    --system-topic-name "$eventgrid_s
#    --source-resource-id "$app_storageid" \
#    --endpoint "$FUNC_APP_ENDPOINT" -->
```

# References
* Built in Azure Roles https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles
* Azure Permissions https://learn.microsoft.com/en-us/azure/role-based-access-control/resource-provider-operations
* Azure REST API - Container Group https://learn.microsoft.com/en-us/rest/api/container-instances/container-groups/create-or-update?view=rest-container-instances-2025-09-01&tabs=HTTP
