#!/usr/bin/env bash
#########################################################################
# Create An Azure Active Directory application, with a service principal
# Configure role assignments.
# Confgiure OpenId Connect (OIDC) based Federated Identity Credentials
# Globals:
#   SUBSCRIPTION_ID
#   GITHUB_ORG
#   GITHUB_REPO
# Optional Globals:
#   CICD_CLIENT_ID
# Params
#    -d, Debug mode
#########################################################################
# Stop on errors
set -e

validate_provision_parameters(){

    if [ -z "$SUBSCRIPTION_ID" ]
    then
        echo "SUBSCRIPTION_ID is required" >&2
        exit 1
    fi

    if [ -z "$GITHUB_ORG" ]
    then
        echo "GITHUB_ORG is required" >&2
        exit 1
    fi

    if [ -z "$GITHUB_REPO" ]
    then
        echo "GITHUB_REPO is required" >&2
        exit 1
    fi
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
project_short_name=$(grep -oP '(?<=^short_name = ")[^"]+' "${project_root}/pyproject.toml"  | tr -d '\n')
application_service_number=$(grep -oP '(?<=^application_service_number = ")[^"]+' "${project_root}/pyproject.toml" | tr -d '\n')
application_owner=$(grep -oP '(?<=^application_owner = ")[^"]+' "${project_root}/pyproject.toml" | tr -d '\n')
resource_token=$(echo -n "${SUBSCRIPTION_ID}${project_name}${LOCATION}" | sha1sum | awk '{print $1}' | cut -c1-8)
short_env=$(echo "${ENVIRONMENT:0:1}" | tr '[:upper:]' '[:lower:]')
tags="asn=$application_service_number project=$project_name owner=$application_owner environment=$ENVIRONMENT"

run_date=$(date +%Y%m%dT%H%M%S)
isa_date_utc=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
deployment_name="${project_name}.Create-CICD-SP.${run_date}"

# Variables
debug=${debug:-0}
app_name="appreg-$project_short_name-cicd-$short_env"
app_secret_name=github_cicd_client_secret

if [ "$debug" -eq 1 ]; then

    echo "Deployment ${deployment_name}" >&2
    echo "SUBSCRIPTION_ID=${SUBSCRIPTION_ID:-<not set>}" >&2
    echo "GITHUB_ORG=${GITHUB_ORG:-<not set>}" >&2
    echo "GITHUB_REPO=${GITHUB_REPO:-<not set>}" >&2
    echo "debug=${debug:-<not set>}" >&2

    rm -Rf .deploy_log
    mkdir -p .deploy_log
fi

validate_provision_parameters

echo "Creating Azure AD application and service principal for CICD..." >&2

if [ -z "$CICD_CLIENT_ID" ]; then
    echo "CICD_CLIENT_ID is not set. Creating new app registration: $app_name" >&2

    # Create an Azure Active Directory App Registration and service principal.
    set +e
    results=$(az ad app create \
        --display-name "$app_name" \
        --only-show-errors 2>&1)
    set -e
    if [ "$debug" -eq 1 ]; then
        echo "$results" >> "${project_root}/.deploy_log/az_ad_app_create.json"
    fi

    app_id=$(echo "$results" | jq -r '.id')
    app_client_id=$(echo "$results" | jq -r '.appId')
    echo "App registration created with App ID: $app_id and Client ID: $app_client_id" >&2

    echo "Creating service principal for the app registration..." >&2
    set +e
    results=$(az ad sp create \
        --id "$app_id" \
        --only-show-errors 2>&1)
    set -e
    if [ "$debug" -eq 1 ]; then
        echo "$results" >> "${project_root}/.deploy_log/az_ad_sp_create.json"
    fi

    # Need app service principal to Assign roles
    echo "Get the service principal ID..." >&2
    app_sp_id=$(echo "$results" | jq -r '.id')
    echo "Service principal created with ID: $app_sp_id" >&2

else
    echo "Using existing CICD_CLIENT_ID" >&2

    set +e
    results=$(az ad app list \
        --app-id "$CICD_CLIENT_ID" \
        --only-show-errors 2>&1)
    set -e
    if [ "$debug" -eq 1 ]; then
        echo "$results" >> "${project_root}/.deploy_log/az_ad_list.json"
    fi

    app_name=$(echo "$results" | jq -r '.name')
    app_id=$(echo "$results" | jq -r '.id')
    app_client_id=$(echo "$results" | jq -r '.[0].appId')

    echo "Found app registration $app_name. App ID: $app_id and Client ID: $app_client_id" >&2

    # get the service principal ID
    echo "Get the service principal ID..." >&2
    set +e
    results=$(az ad sp list \
        --all \
        --display-name "$app_name"  \
        --only-show-errors 2>&1)
    set -e
    if [ "$debug" -eq 1 ]; then
        echo "$results" >> "${project_root}/.deploy_log/az_ad_sp_list.json"
    fi
    app_sp_id=$(echo "$results" | jq -r '.id')
    echo "Service principal ID: $app_sp_id" >&2
fi

# echo "Assigning roles to the service principal..." >&2
# az role assignment create --assignee "$app_sp_id" --role contributor --scope "/subscriptions/$SUBSCRIPTION_ID"
# az role assignment create --role contributor --subscription "$SUBSCRIPTION_ID" --assignee-object-id  "$app_sp_id" --assignee-principal-type ServicePrincipal --scope "/subscriptions/$SUBSCRIPTION_ID"

# # Add OIDC federated credentials for the application.
# echo "Adding OIDC federated identity credentials to the app registration..." >&2
# post_body="{\"name\":\"$app_secret_name\","
# post_body=$post_body'"issuer":"https://token.actions.githubusercontent.com",'
# post_body=$post_body"\"subject\":\"repo:$GITHUB_ORG/$GITHUB_REPO:pull_request\","
# post_body=$post_body'"description":"GitHub CICID Service","audiences":["api://AzureADTokenExchange"]}'
# az rest --method POST --uri "https://graph.microsoft.com/beta/applications/$app_id/federatedIdentityCredentials" --body "$post_body"

# echo "CICD service principal created successfully." >&2


# # Save generated values to .env file
# if [ -z "$CICD_CLIENT_NAME" ]; then
#     echo "Save CICD_CLIENT_NAME to ${env_file}" >&2
#     {
#         echo ""
#         echo "# create_cicd_sp.sh generated values"
#         echo "# Generated on ${isa_date_utc}"
#         echo "CICD_CLIENT_NAME=$app_name"
#     }>> "$env_file"
# fi
# if [ -z "$CICD_CLIENT_ID" ]; then
#     echo "Save CICD_CLIENT_ID to ${env_file}" >&2
#     {
#         echo ""
#         echo "# create_cicd_sp.sh generated values"
#         echo "# Generated on ${isa_date_utc}"
#         echo "CICD_CLIENT_ID=$app_client_id"
#     }>> "$env_file"
# fi
