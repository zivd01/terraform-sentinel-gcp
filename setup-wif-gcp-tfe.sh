#!/bin/bash
# This script configures GCP Workload Identity Federation (WIF) for Terraform Cloud (TFE).
# Using WIF allows TFE to authenticate dynamically using OpenID Connect (OIDC) tokens
# without needing long-lived JSON service account keys. This is the ultimate security best practice.

set -e

# --- Load Configuration ---
if [ ! -f "config.env" ]; then
    echo "Error: config.env file not found. Please create it and fill in your variables."
    exit 1
fi
source config.env

# Validate required variables
REQUIRED_VARS=("GCP_PROJECT_ID" "TFE_ORG_NAME" "TFE_WORKSPACE_NAME" "GCP_SA_NAME" "GCP_WIF_POOL_NAME" "GCP_WIF_PROVIDER_NAME")
for VAR in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!VAR}" ] || [[ "${!VAR}" == "your-"* ]]; then
        echo "Error: Missing or default value for $VAR in config.env. Please configure it properly."
        exit 1
    fi
done

# Map variables for the script
PROJECT_ID="$GCP_PROJECT_ID"
TFE_ORG="$TFE_ORG_NAME"
TFE_WORKSPACE="$TFE_WORKSPACE_NAME"
SA_NAME="$GCP_SA_NAME"

SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
POOL_NAME="$GCP_WIF_POOL_NAME"
PROVIDER_NAME="$GCP_WIF_PROVIDER_NAME"

gcloud config set project $PROJECT_ID
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")

# 1. Create the Service Account
echo "Creating Service Account: $SA_NAME"
gcloud iam service-accounts create $SA_NAME --display-name="TFE Dynamic Auth SA" || true

# 2. Grant necessary roles to the Service Account
# Applying Principle of Least Privilege: Removing the overly broad 'roles/editor'.
# Instead, we grant exactly what Terraform needs to provision Compute and Networks.
echo "Granting specific Compute Engine & Network Admin roles to $SA_EMAIL"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/compute.instanceAdmin.v1"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/compute.networkAdmin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/compute.securityAdmin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/iam.serviceAccountUser"

# 3. Create the Workload Identity Pool
echo "Creating Workload Identity Pool: $POOL_NAME"
gcloud iam workload-identity-pools create $POOL_NAME \
    --project=$PROJECT_ID \
    --location="global" \
    --display-name="TFE Global Identity Pool" || true

# 4. Create the OIDC Provider in the Pool for Terraform Cloud
echo "Creating OIDC Provider: $PROVIDER_NAME"
gcloud iam workload-identity-pools providers create-oidc $PROVIDER_NAME \
    --project=$PROJECT_ID \
    --location="global" \
    --workload-identity-pool=$POOL_NAME \
    --display-name="TFE OIDC Provider" \
    --issuer-uri="https://app.terraform.io" \
    --attribute-mapping="google.subject=assertion.sub,attribute.aud=assertion.aud,attribute.terraform_workspace_id=assertion.terraform_workspace_id,attribute.terraform_full_workspace=assertion.terraform_full_workspace" || true

# 5. Bind the Service Account to the Workload Identity Pool (Restrict to specific Workspace)
echo "Binding Service Account to TFE Workspace: ${TFE_ORG}/${TFE_WORKSPACE}"
gcloud iam service-accounts add-iam-policy-binding $SA_EMAIL \
    --role="roles/iam.workloadIdentityUser" \
    --member="principalSet://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/$POOL_NAME/attribute.terraform_full_workspace/organization:${TFE_ORG}:workspace:${TFE_WORKSPACE}"

# Output TFE Variables for copying
PROVIDER_ID="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_NAME}/providers/${PROVIDER_NAME}"

echo ""
echo "=== SETUP COMPLETE. NEXT STEPS FOR TERRAFORM CLOUD ==="
echo "Add the following Environment Variables to your TFE Workspace (${TFE_WORKSPACE}):"
echo ""
echo "1. Key: TFC_GCP_PROVIDER_AUTH"
echo "   Value: true"
echo "   Description: Tells Terraform to use dynamic provider authentication."
echo ""
echo "2. Key: TFC_GCP_WORKLOAD_PROVIDER_NAME"
echo "   Value: $PROVIDER_ID"
echo "   Description: The GCP Workload Identity Provider ID."
echo ""
echo "3. Key: TFC_GCP_RUN_SERVICE_ACCOUNT_EMAIL"
echo "   Value: $SA_EMAIL"
echo "   Description: The GCP Service Account email that will be impersonated."
echo ""
echo "With this setup, TFE receives a short-lived GCP token automatically for each run. No JSON keys needed!"
