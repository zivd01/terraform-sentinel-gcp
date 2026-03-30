# Infrastructure Management and Security with Terraform & Sentinel on GCP

Welcome to the comprehensive technical guide for our Governance project!
This guide was written specifically for Junior DevOps, Infrastructure, and Cloud engineers who are learning Terraform and want to understand exactly **what** this project does, **how** it works behind the scenes, and get a **detailed breakdown** of the code itself.

---

## 1. The Goal: What does this project actually do? 🎯

In modern infrastructure, engineers use a tool called **Terraform** to provision infrastructure (like servers, networks, and databases) using code (Infrastructure as Code). The problem begins in large organizations: how do you ensure a junior programmer doesn't accidentally spin up a server that costs $5,000 a month, or accidentally open a dangerous port (like port 22 - SSH) to the entire internet, exposing the company to a breach?

This is where our project comes into play.
The project connects **Google Cloud (GCP)** to the central **Terraform Cloud (TFE)** management server and uses an engine called **Sentinel** (Policy as Code - rules written as code).
**Our Goal:** To build a "Gatekeeper for Information Security and Budget" that stands in the middle. If the developer's code is correct and safe – the infrastructure will be provisioned. If the developer violates any organizational rule – the deployment will fail automatically *before* the server is even created in the cloud!

---

## 2. Architecture: How does it work? 🏗️

The project is built in 3 logical layers:
1. **Keyless Authentication (WIF):** Instead of storing password files (JSON Keys) that could leak to hackers, the project uses a mechanism called Workload Identity Federation (WIF). This means Terraform Cloud gets temporary access, lasting only a few minutes, to the Google Cloud.
2. **Automation and Permissions:** The project contains Bash scripts (like `setup-wif-gcp-tfe.sh`) that create the Machine Account (Service Account) for us with a click of a button and grant it minimal permissions (Least Privilege) to allow it to perform only network and server operations.
3. **Policy Injection:** Our Terraform code (`setup_tfe_policies.tf`) takes the rules we wrote and packages them into a directory in the Terraform Cloud so they apply to every new infrastructure save/apply.

---

## 3. Diving into the Code (Line-by-Line Walkthrough) 🔍

### A. Bash Automation Script: Cloud configuration (`utils.sh` + `setup-wif-gcp-tfe.sh`)
To avoid having to type out exactly dozens of commands to configure our cloud, we write automation in Bash. Here is an example code snippet from our scripts:

```bash
# 1. State-Check (Idempotency) 
# We check if the Service Account (the virtual user in the cloud) already exists.
# If it exists - we skip. If not - we create it. This prevents the script from crashing if someone runs it twice.
if gcloud iam service-accounts describe "${SA_EMAIL}" &>/dev/null; then
    echo "Service Account ${SA_NAME} already exists. Skipping creation."
else
    echo "Creating Service Account: ${SA_NAME}"
    gcloud iam service-accounts create $SA_NAME --display-name="TFE Dynamic Auth SA"
fi

# 2. Principle of Least Privilege - Minimalist Information Security
# Here we "bind" our user with the lowest possible privilege for our needs. 
# Instead of giving them "System Administrator" - we only grant them permission to manage servers. 
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/compute.instanceAdmin.v1"
```

### B. Sentinel Policy Code - Financial Protection (`restrict-gce-machine-type.sentinel`)
This is the code for our FinOps team. Sentinel language is written in a very clear structure to approve or reject conditions:

```sentinel
import "tfplan/v2" as tfplan  # Import the future state (Plan) of the infrastructure we tried to build
import "strings"              # A library that allows string slicing and manipulation

# We define a strict list of allowed servers - only the cheap e2 family. 
# Attempting to request a stronger server will be rejected and will save us thousands of dollars!
allowed_machine_types = [
  "e2-micro",
  "e2-small",
  "e2-medium",
]

# We loop through all the servers (instances) that the Software Engineer is trying to create today:
for instances as address, instance {
  # Read the actual server type they requested
  mt_raw = instance.change.after.machine_type else ""
  
  # Mathematical trick (O(1)): We slice the server name from the long Google API path
  mt_parts = strings.split(mt_raw, "/")
  base_mt = mt_parts[length(mt_parts) - 1]
  
  # Final check: if the requested server is not in our list above -> the run fails (`is_valid = false`).
  if base_mt not in allowed_machine_types {
    print("Violation:", address, "uses forbidden machine type:", base_mt)
    is_valid = false
  }
}
```

### C. Terraform Infrastructure Code - Policy Deployment (`setup_tfe_policies.tf`)
Finally, we need code that will upload the rules to the Terraform server on the network. We write the actual upload operation in Terraform too!

```hcl
# A Data block that packages all Sentinel files (with the .sentinel extension) from our folder into a compressed archive in memory (Slug).
data "tfe_slug" "sentinel_policies" {
  source_path = "${path.module}/"
}

# A Resource creation block. We instruct the Terraform Cloud server to create a Policy Set.
resource "tfe_policy_set" "sentinel_policies" {
  name          = var.tfe_policy_set_name
  description   = "GCP Hard-Mandatory Security Guards"  # Administrative description
  organization  = var.tfe_organization                  # Our organization in HashiCorp Cloud
  kind          = "sentinel"                            # Specifying the policy type (could also be OPA, for example)

  # Actual Upload: We send the compressed file we created in the previous block directly to the API.
  slug = data.tfe_slug.sentinel_policies.id
  
  # Minor Assignment: To which environments (Workspaces) these rules will apply.
  workspace_ids = [var.tfe_workspace_id]
}
```

---
**Summary:** We have seen advanced use of infrastructure management where automation (Bash/CLI) wraps permissions (IAM/WIF), the global deployment tool (Terraform) reads configurations, and the policy isolation layer (Sentinel) restricts power and protects the company from mistakes that cost thousands of dollars or expose security risks! 
Good luck natively on your journey to the Cloud!
