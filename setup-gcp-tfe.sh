#!/bin/bash
# This script configures a GCP Service Account for Terraform Cloud / TFE
# It creates the account, assigns necessary roles, and generates a JSON key.

# Exit immediately if a command exits with a non-zero status
set -e

# --- Load and Validate Configuration ---
source ./utils.sh || { echo "Error: utils.sh module not found!"; exit 1; }
load_and_validate_env "GCP_PROJECT_ID" "GCP_SA_NAME"

# Map variables for the script
PROJECT_ID="$GCP_PROJECT_ID"
SA_NAME="$GCP_SA_NAME"
# Define the full Service Account email address
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# 1. Set the active GCP project
# This command ensures that all subsequent gcloud commands are executed against the correct project.
gcloud config set project $PROJECT_ID

# 2. Create the Service Account Idempotently
# Architectural Decision: We wrap this creation linearly in a 'describe' state-check to natively 
# support repeated CI/CD executions. If a build-server runs this twice, checking state prevents a crash.
if gcloud iam service-accounts describe "${SA_EMAIL}" &>/dev/null; then
    echo "Service Account ${SA_NAME} already exists. Skipping creation."
else
    echo "Creating Service Account: $SA_NAME"
    gcloud iam service-accounts create $SA_NAME \
        --display-name="Terraform TFE Service Account"
fi

# 3. Grant necessary roles to the Service Account
# Applying Principle of Least Privilege: Removing the overly broad 'roles/editor'.
# Instead, we grant exactly what Terraform needs to provision Compute and Networks.
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

# 4. Generate the JSON key for the Service Account
# Warning (Risk Acceptance): Generating a static JSON key inherently forces Terraform Cloud 
# to become responsible for storing a highly sensitive private credential. If possible, upgrade to WIF.
gcloud iam service-accounts keys create terraform-key.json \
    --iam-account=$SA_EMAIL

echo "Service Account created and key saved to terraform-key.json."
echo "NEXT STEPS IN TERRAFORM CLOUD / TFE:"
echo "1. Go to your Workspace -> Variables."
echo "2. Add an Environment Variable named 'GOOGLE_CREDENTIALS'."
echo "3. Remove all newlines from 'terraform-key.json' and paste the content as the variable value."
echo "4. Mark the 'GOOGLE_CREDENTIALS' variable as 'Sensitive'."
