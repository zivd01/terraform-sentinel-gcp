#!/bin/bash
# This script configures GCP Workload Identity Federation (WIF) for Terraform Cloud (TFE).
# Using WIF allows TFE to authenticate dynamically using OpenID Connect (OIDC) tokens
# without needing long-lived JSON service account keys. This is the ultimate security best practice.

set -e

# --- Load and Validate Configuration ---
source ./utils.sh || { echo "Error: utils.sh module not found!"; exit 1; }
load_and_validate_env "GCP_PROJECT_ID" "TFE_ORG_NAME" "TFE_WORKSPACE_NAME" "GCP_SA_NAME" "GCP_WIF_POOL_NAME" "GCP_WIF_PROVIDER_NAME"

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

# 1. Create the Service Account Idempotently
if gcloud iam service-accounts describe "${SA_EMAIL}" &>/dev/null; then
    echo "Service Account ${SA_NAME} already exists. Skipping creation."
else
    echo "Creating Service Account: $SA_NAME"
    gcloud iam service-accounts create $SA_NAME --display-name="TFE Dynamic Auth SA"
fi

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

# 3. Create the Workload Identity Pool Idempotently
# Architectural Decision: Generating a Workload Identity Pool allows us to build a completely 
# JSON-Keyless Cloud environment. This shifts authentications dynamically to memory, directly 
# eliminating the organizational risks of data-leakage (Stolen Static Keys).
if gcloud iam workload-identity-pools describe "$POOL_NAME" --project="$PROJECT_ID" --location="global" &>/dev/null; then
    echo "Workload Identity Pool $POOL_NAME already exists. Skipping creation."
else
    echo "Creating Workload Identity Pool: $POOL_NAME"
    gcloud iam workload-identity-pools create $POOL_NAME \
        --project=$PROJECT_ID \
        --location="global" \
        --display-name="TFE Global Identity Pool"
fi

# 4. Create the OIDC Provider Idempotently
if gcloud iam workload-identity-pools providers describe "$PROVIDER_NAME" --project="$PROJECT_ID" --location="global" --workload-identity-pool="$POOL_NAME" &>/dev/null; then
    echo "OIDC Provider $PROVIDER_NAME already exists. Skipping creation."
else
    echo "Creating OIDC Provider: $PROVIDER_NAME"
    gcloud iam workload-identity-pools providers create-oidc $PROVIDER_NAME \
        --project=$PROJECT_ID \
        --location="global" \
        --workload-identity-pool=$POOL_NAME \
        --display-name="TFE OIDC Provider" \
        --issuer-uri="https://app.terraform.io" \
        --attribute-mapping="google.subject=assertion.sub,attribute.aud=assertion.aud,attribute.terraform_workspace_id=assertion.terraform_workspace_id,attribute.terraform_full_workspace=assertion.terraform_full_workspace"
fi

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
