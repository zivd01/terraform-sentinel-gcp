terraform {
  required_providers {
    tfe = {
      version = "~> 0.50.0"
    }
  }
}

variable "tfe_organization" {
  description = "The name of your Terraform Cloud Organization"
  type        = string
}

variable "tfe_workspace_id" {
  description = "The ID of the Workspace where these policies should apply (e.g., ws-12345678)"
  type        = string
}

variable "tfe_policy_set_name" {
  description = "The name of the Sentinel Policy Set"
  type        = string
}

# The tfe_slug data source packages your local Sentinel policies
# You can change source_path to a designated folder if you move the .sentinel files
data "tfe_slug" "gcp_sentinel_policies" {
  source_path = "."
}

# The policy set resource configured based on the local slug
resource "tfe_policy_set" "gcp_governance" {
  name          = var.tfe_policy_set_name
  description   = "Sentinel policies enforcing GCP machine types and firewall rules"
  organization  = var.tfe_organization
  workspace_ids = [var.tfe_workspace_id]
  kind          = "sentinel"

  # We use the manually uploaded slug in lieu of a VCS repo
  slug = data.tfe_slug.gcp_sentinel_policies
}
