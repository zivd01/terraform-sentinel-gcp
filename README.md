# Infrastructure Governance and Management in Google Cloud (GCP) Using Terraform Cloud / Enterprise

```text
 +---------------------+                  +---------------------+
 |  Terraform Cloud    |                  |  Google Cloud (GCP) |
 |  (TFE Workspace)    |                  |                     |
 |                     |   OIDC Token     |  +---------------+  |
 | 1. TFE Run Starts --|----------------->|--| WIF Pool      |  |
 |                     |                  |  +---------------+  |
 |                     |                  |          |          |
 |                     |                  |          v          |
 |                     |                  |  +---------------+  |
 |                     |                  |  | WIF Provider  |  |
 |                     |  Impersonated SA |  +---------------+  |
 | 2. Authenticated  <-|----- Token ------|--| Service Acct  |  |
 |    Workspace        |                  |  +---------------+  |
 +---------------------+                  |                     |
          |                               |                     |
          v                               |                     |
 +---------------------+                  |                     |
 |  Sentinel Engine    |                  |                     |
 |                     |  Provisioning    |  +---------------+  |
 | - Machine Types     |-- Policy Checks->|  | Compute VMs & |  |
 | - Firewall Ports    |                  |  | Firewalls     |  |
 +---------------------+                  |  +---------------+  |
                                          +---------------------+
```

This project is designed to demonstrate to infrastructure managers how to govern, manage, and secure a cloud environment in GCP by utilizing the advanced capabilities of Terraform Cloud / Enterprise (TFE), particularly through the use of Sentinel for policy enforcement and manual change detection (Drift Detection).

## 0. Configuration Setup (`config.env`)

Before running any scripts in this project, you must define your environment variables centrally:
1. Open the `config.env` file in the root directory.
2. Replace all placeholder values (`"your-..."`) with your actual GCP and TFE identifiers.

All automation scripts automatically load and validate these variables before execution to prevent misconfigurations.

### 🛡️ Module Validations (`utils.sh`)
Behind the scenes, all Bash automation scripts load a central dependency module called `utils.sh`. I engineered this file according to the **Single Responsibility Principle (SRP)**. Its only job is to dynamically pull variables from `config.env` and rigorously validate them. If any variable is missing or contains placeholder text, `utils.sh` will instantly catch it and halt the executing script, actively preventing destructive cloud misconfigurations!

## 1. Connecting TFE to GCP Cloud (Generating Tokens and Permissions)

**Where do I run the scripts?**
The connection scripts can be executed in two ways:
1. **Recommended - Via GCP Cloud Shell:** Log in to the GCP Console in your browser, click on the Cloud Shell icon at the top right (`>_`), create the script file (e.g., `nano setup-wif-gcp-tfe.sh`), grant it execution permissions (`chmod +x setup-wif-gcp-tfe.sh`), and run `./setup-wif-gcp-tfe.sh`. The Cloud Shell is automatically authenticated with your user's management privileges.
2. **Via Local Workstation (Linux/Mac/Windows):** On a computer with the Google Cloud CLI (`gcloud`) installed, you must run `gcloud auth login` and authenticate through a browser before executing the script. Afterward, you can run the script normally.

There are two approaches for connecting TFE to GCP. The first approach (WIF) is highly recommended as a security best practice:

### Option A: Dynamic Keyless Authentication (Workload Identity Federation) - Recommended!
The `setup-wif-gcp-tfe.sh` script creates an OIDC Provider and Pool. Using this method, TFE does not receive a static (JSON) key; instead, it generates a short-lived access token for GCP per run, specifically for the authorized Workspace.
After running the script, you must add the following Environment Variables to your Terraform Cloud Workspace (no need to mark them as Sensitive!):
1. Enablement Flag: `TFC_GCP_PROVIDER_AUTH` set to `true`.
2. Provider Address: `TFC_GCP_WORKLOAD_PROVIDER_NAME` set to the value output at the end of the script.
3. Service Account: `TFC_GCP_RUN_SERVICE_ACCOUNT_EMAIL` set to the Service Account email address.

### Option B: Traditional Authentication via Static Key (JSON Key)
The `setup-gcp-tfe.sh` script is designed to download a static Key file, suitable for legacy systems.
After running the script:
1. Navigate to the Workspace in TFE.
2. Under **Variables**, add an opaque variable named `GOOGLE_CREDENTIALS` (mark it as Sensitive).
3. Paste the entire content of the JSON key as a single string (without line breaks).

In both methods, the Service Account ("User") is assigned highly granular Compute and Network Admin roles (and additional permissions if necessary), allowing the system to provision resources in compliance with organizational policies securely.

## 2. Policy as Code (Sentinel)

The `sentinel.hcl` file groups and defines two central policies aimed at preventing security risks and undesired costs **before** the resources are actually provisioned:

1. **`restrict-gce-machine-type.sentinel`**: The purpose of this policy is to ensure that no user can provision excessively expensive virtual machines (VMs) (such as GPU servers). The code restricts the allowed machine types to a very limited and low-cost list (`e2-micro`, `e2-small`, `e2-medium`).
2. **`restrict-gce-firewall-ports.sentinel`**: This code scans planned Firewall rules during provisioning and blocks any attempt to open restricted ports (such as SSH - port 22 or RDP - port 3389) to the entire public internet (`0.0.0.0/0`). This prevents critical security exposures in the organizational cloud.

*Note: All code blocks in these files include English comments providing focused explanations for infrastructure administrators.*

### 2.1 Deploying the Policies to TFE 

I have added automated deployment scripts to package these Sentinel rules and attach them to your target TFE Workspace.

1. **`setup_tfe_policies.tf`**: This Terraform configuration uses the `tfe_policy_set` and `tfe_slug` resources to bundle your local Sentinel rules dynamically.
2. **`deploy_policy_set.sh`**: A helper bash script that executes the Terraform deployment.

**Deployment Steps:**
1. Open a terminal and authenticate to Terraform Cloud using `terraform login`.
2. Ensure you have fully populated `config.env`.
3. Run the deployment script:
   ```bash
   chmod +x ./deploy_policy_set.sh
   ./deploy_policy_set.sh
   ```
Once applied, the Policy Set is bound to your workspace with a "hard-mandatory" enforcement level. Any future `terraform plan` triggered in this Workspace will automatically evaluate your infrastructure against these security policies.

### 🛡️ 2.2 Security Insights & Best Practices

As part of securing this integration against hostile activities, please observe the following strictly:
- **Avoid Static Keys**: Do not use the `setup-gcp-tfe.sh` script (JSON Key method) in production. Always prefer Workload Identity Federation (WIF) via `setup-wif-gcp-tfe.sh`.
- **Principle of Least Privilege**: Our setup scripts automatically assign highly restricted roles (`compute.instanceAdmin.v1`, `compute.securityAdmin`, etc.) instead of the standard `roles/editor`. This severely limits blast radius in the event your Terraform workspace is compromised.
- **Sentinel Firewall Coverage**: A robust port-blocking policy MUST evaluate empty `ports` configurations. In GCP, explicitly omitting the `ports` array implicitly allows ALL ports to open. Our `restrict-gce-firewall-ports.sentinel` dynamically catches this implicit exposure to guarantee airtight port governance.

## 3. Drift Detection and Remediation

One of the challenges in managing cloud infrastructure is that users with broad permissions might manually execute changes within the GCP Console—changes that are not documented or tracked by the central Terraform code. This phenomenon is known as **Drift**.
The TFE platform provides a "Health Status" containing advanced capabilities to detect and remediate these drifts:

1. **Early Detection and Indication (Health Assessment)**:
   Terraform Cloud periodically runs background assessments in a "Refresh-Only" mode against the GCP cloud. It compares the actual state of the infrastructure in the cloud (Real World) against the state saved in the Terraform state file. When a gap is detected—for example, if an engineer manually changed the machine type to a stronger, more expensive server contrary to the code configuration—the Workspace status changes to **Drifted**. At this stage, immediate alerts (e.g., Slack or Email notifications) can be dispatched.

2. **Independent Remediation and Policy Enforcement**:
   - To "fix" and revert the deviation back to the approved standard in code, I can re-run an `apply` operation digitally in TFE. This action "overrides" the manual change in GCP and returns the machine back to its original configuration as agreed upon and approved (Drift remediation – revert mechanism).
   - Alternatively, if I wish to **Adopt** the manual change, I must update my Terraform code (Code update to match Real World).
   
   **Sentinel Protection and the Closed-Loop Feedback**: Here is where the impressive capability for infrastructure administrators comes into play—if a developer or network administrator wishes to update the configuration code to "adopt" an unapproved manual change made in the cloud legitimately, **the Sentinel system will block the attempt!** (i.e., the run will fail via a "hard-mandatory" enforcement). For instance, changing the machine to a massive instance size in GCP will trigger a state drift. If they subsequently try to update the Terraform code with the huge size to get it approved, the Sentinel system will identify it as a non-allowed machine type. Thus, TFE combined with Sentinel effectively shuts down entirely the manual communication channel, strictly enforcing methodical and defined behavior without exceptions (Automated Policy Compliance).

These capabilities demonstrate how the GCP environment becomes a "locked down and protected" zone against unwarranted resource consumption and security breaches, establishing a powerful enforcement tool for organizational administrators.
