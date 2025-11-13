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

assign_role(){

    local role_name=$1
    local role_definition=$2
    local scope=$3
    local app_sp_id=$4
    local role_id
    
    # Get Custom role ID
    role_id=$(az role definition list \
        --name "$role_name" \
        --query '[0].id' -o tsv 2>/dev/null || echo "")

    # Create Custom - Resource Group Creator role if it does not exist
    if [ -n "$role_id" ]; then
        echo "Role $role_name already exists." >&2
    else
        echo "Creating role $role_name with definition:\n$role_definition" >&2

        set +e
        results=$(az role definition create \
            --role-definition "$role_definition" \
            --only-show-errors 2>&1)
        set -e
        if [ "$debug" -eq 1 ]; then
            echo "$results" >> "${project_root}/.deploy_log/az_role_definition_create_$role_name.json"
        fi

        role_id=$(echo "$results" | jq -r '.id')

    fi

    set +e
    results=$(az role assignment create \
        --role "$role_id" \
        --scope "$scope" \
        --assignee-object-id  "$app_sp_id" \
        --assignee-principal-type ServicePrincipal \
        --only-show-errors 2>&1)
    set -e
    if [ "$debug" -eq 1 ]; then
        echo "$results" >> "${project_root}/.deploy_log/az_role_assignment_create_$role_name.json"
    fi

    assignment_id=$(echo "$results" | jq -r '.id' || echo "")

    echo "Successfully assigned role $role_name to service principal." >&2
    echo "$assignment_id"

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
    echo "App registration created" >&2

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
    echo "Service principal created" >&2

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

    app_name=$(echo "$results" | jq -r '.[0].displayName')
    app_id=$(echo "$results" | jq -r '.[0].id')
    app_client_id=$(echo "$results" | jq -r '.[0].appId')

    echo "Found app registration $app_name." >&2

    # get the service principal ID
    echo "Get service principal ID..." >&2
    set +e
    results=$(az ad sp list \
        --all \
        --display-name "$app_name"  \
        --only-show-errors 2>&1)
    set -e
    if [ "$debug" -eq 1 ]; then
        echo "$results" >> "${project_root}/.deploy_log/az_ad_sp_list.json"
    fi
    app_sp_id=$(echo "$results" | jq -r '.[0].id')
    echo "Found service principal." >&2
fi



echo "Assigning roles to the service principal..." >&2

# Custome Role - Resource Group Creator
role_name=$(cat "${project_root}/docs/ad_resource_group_creator_role.json" | jq -r '.Name')
response=$(az role assignment list --assignee "$app_sp_id" --role "$role_name")
if [[ $response == '[]' ]]; then
    role_definition=$("$project_root"/script/render_role_template.sh -i "${project_root}/docs/ad_resource_group_creator_role.json" -v ASSIGNABLE_SCOPE="/subscriptions/$SUBSCRIPTION_ID")
    response=$(assign_role "$role_name" "$role_definition" "/subscriptions/$SUBSCRIPTION_ID" "$app_sp_id")
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        echo "Failed to assign $role_name role to service principal" >&2
        exit 1
    fi
    echo "Assigned $role_name role." >&2
else
    echo "Service principal already has $role_name role." >&2
fi

# Built in roles
roles=(
  "Storage Account Contributor"
  "Storage Account Key Operator Service Role"
  "Storage Blob Data Contributor"
  "AcrPush"
  "Monitoring Contributor"
  "Key Vault Contributor"
  "Key Vault Secrets Officer"
)

for role_name in "${roles[@]}"; do
    # Check if role already assigned
    response=$(az role assignment list --assignee "$app_sp_id" --role "$role_name")
    if [[ $response == '[]' ]]; then
        # Assign role
        echo "Assigning $role_name role to service principal..." >&2

        set +e
        response=$(az role assignment create \
            --role "$role_name" \
            --scope "/subscriptions/$SUBSCRIPTION_ID" \
            --assignee-object-id "$app_sp_id" \
            --assignee-principal-type ServicePrincipal \
            --subscription "$SUBSCRIPTION_ID" \
            --only-show-errors 2>&1)
        set -e

        if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
            echo "Failed to assign $role_name role to service principal" >&2
            if [ "$debug" -eq 1 ]; then
                echo "$response" >> "${project_root}/.deploy_log/az_role_assignment_create_${role_name}.json"
            fi
            exit 1
        fi
        echo "Assigned $role_name role." >&2
    else
        echo "Service principal already has $role_name role." >&2
    fi
done


# Add OIDC federated credentials for the application.
response=$(az ad app federated-credential list --id "$app_id")
if [[ $response == '[]' ]]; then
    echo "No existing federated identity credentials found." >&2
        
    echo "Adding OIDC federated identity credentials to the app registration..." >&2
    post_body="{\"name\":\"$app_secret_name\","
    post_body=$post_body'"issuer":"https://token.actions.githubusercontent.com",'
    post_body=$post_body"\"subject\":\"repo:$GITHUB_ORG/$GITHUB_REPO:environment:staging\","
    post_body=$post_body'"description":"GitHub CICID Service","audiences":["api://AzureADTokenExchange"]}'
    az rest --method POST --uri "https://graph.microsoft.com/beta/applications/$app_id/federatedIdentityCredentials" --body "$post_body"

    echo "OIDC federated identity credentials added." >&2

else
    echo "Existing federated identity credentials found. Skipping addition." >&2
fi

# Save generated values to .env file
echo "Save CICD_CLIENT_NAME to ${env_file}" >&2
{
    echo ""
    echo "# create_cicd_sp.sh generated values"
    echo "# Generated on ${isa_date_utc}"
    echo "CICD_CLIENT_NAME=$app_name"
    echo "CICD_CLIENT_ID=$app_client_id"
}>> "$env_file"
