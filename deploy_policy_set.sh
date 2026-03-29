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

# Configuration: Prompt user or use environment variables
TFE_ORG="${TFE_ORG_NAME:-your-org-name}"
TFE_WS_ID="${TFE_WORKSPACE_ID:-ws-12345678}"

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
  -auto-approve

echo "✅ Sentinel Policies successfully attached! You can verify this in Terraform Cloud under your Workspace > Policy Sets."
echo "Any future runs in this workspace will now evaluate against the Sentinel rules."
