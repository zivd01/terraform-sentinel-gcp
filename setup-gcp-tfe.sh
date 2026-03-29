#!/bin/bash
# This script configures a GCP Service Account for Terraform Cloud / TFE
# It creates the account, assigns necessary roles, and generates a JSON key.

# Exit immediately if a command exits with a non-zero status
set -e

# --- Load Configuration ---
if [ ! -f "config.env" ]; then
    echo "Error: config.env file not found. Please create it and fill in your variables."
    exit 1
fi
source config.env

# Validate required variables
REQUIRED_VARS=("GCP_PROJECT_ID" "GCP_SA_NAME")
for VAR in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!VAR}" ] || [[ "${!VAR}" == "your-"* ]]; then
        echo "Error: Missing or default value for $VAR in config.env. Please configure it properly."
        exit 1
    fi
done

# Map variables for the script
PROJECT_ID="$GCP_PROJECT_ID"
SA_NAME="$GCP_SA_NAME"
# Define the full Service Account email address
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# 1. Set the active GCP project
# This command ensures that all subsequent gcloud commands are executed against the correct project.
gcloud config set project $PROJECT_ID

# 2. Create the Service Account
# This command creates a new Service Account in GCP which Terraform will use to authenticate.
gcloud iam service-accounts create $SA_NAME \
    --display-name="Terraform TFE Service Account"

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

# Additional roles might be needed depending on what you provision (e.g., Compute Admin, Security Admin).
# gcloud projects add-iam-policy-binding $PROJECT_ID \
#     --member="serviceAccount:${SA_EMAIL}" \
#     --role="roles/compute.admin"

# 4. Generate the JSON key for the Service Account
# This command creates a JSON key file which contains the credentials.
# Terraform TFE uses this key to authenticate with GCP.
gcloud iam service-accounts keys create terraform-key.json \
    --iam-account=$SA_EMAIL

echo "Service Account created and key saved to terraform-key.json."
echo "NEXT STEPS IN TERRAFORM CLOUD / TFE:"
echo "1. Go to your Workspace -> Variables."
echo "2. Add an Environment Variable named 'GOOGLE_CREDENTIALS'."
echo "3. Remove all newlines from 'terraform-key.json' and paste the content as the variable value."
echo "4. Mark the 'GOOGLE_CREDENTIALS' variable as 'Sensitive'."
