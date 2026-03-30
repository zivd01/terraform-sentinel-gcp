#!/bin/bash
# Description: This script deploys the local Sentinel policies to Terraform Enterprise (TFE).
# It will use the generated setup_tfe_policies.tf file to attach the policy set to your target Workspace.

set -e

echo "=== TFE Policy Set Deployment Script ==="

# Check for required Terraform CLI tool
if ! command -v terraform &> /dev/null; then
    echo "Error: 'terraform' CLI is not installed. Please install it first."
    exit 1
fi

# --- Load and Validate Configuration ---
source ./utils.sh || { echo "Error: utils.sh module not found!"; exit 1; }
load_and_validate_env "TFE_ORG_NAME" "TFE_WORKSPACE_ID" "TFE_POLICY_SET_NAME"

TFE_ORG="$TFE_ORG_NAME"
TFE_WS_ID="$TFE_WORKSPACE_ID"
TFE_PS_NAME="$TFE_POLICY_SET_NAME"

if [ -z "$TFE_TOKEN" ]; then
    echo "Warning: TFE_TOKEN environment variable not set. You must be logged into TFE locally via 'terraform login'."
fi

echo "Deploying the policy set to Organization: $TFE_ORG and Workspace ID: $TFE_WS_ID"

# Step 1: Initialize Terraform
echo "Initializing Terraform..."
terraform init

# Step 2: Apply the Terraform configurations dynamically
echo "Applying TFE Policy Set configurations..."
terraform apply \
  -var="tfe_organization=$TFE_ORG" \
  -var="tfe_workspace_id=$TFE_WS_ID" \
  -var="tfe_policy_set_name=$TFE_PS_NAME" \
  -auto-approve

echo "✅ Sentinel Policies successfully attached! You can verify this in Terraform Cloud under your Workspace > Policy Sets."
echo "Any future runs in this workspace will now evaluate against the Sentinel rules."
