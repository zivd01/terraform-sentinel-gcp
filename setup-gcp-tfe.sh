#!/bin/bash
# This script configures a GCP Service Account for Terraform Cloud / TFE
# It creates the account, assigns necessary roles, and generates a JSON key.

# Exit immediately if a command exits with a non-zero status
set -e

# --- Configuration Variables ---
# Define your GCP Project ID
PROJECT_ID="your-gcp-project-id"
# Define the Service Account name for Terraform
SA_NAME="terraform-tfe-sa"
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
# For Terraform to create resources (like VMs and Firewalls) and enforce policies, it needs appropriate permissions.
# Often, 'roles/editor' is used for general resource management, but you should restrict this in production (Principle of Least Privilege).
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/editor"

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
