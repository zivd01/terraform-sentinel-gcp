# This configuration file defines the Sentinel policies that Terraform Cloud will enforce.
# It specifies the enforcement level and the path to the policy code.

# Policy to restrict the sizing of GCP Compute Engine instances
policy "restrict-gce-machine-type" {
    # The source of the policy file
    source = "./restrict-gce-machine-type.sentinel"
    # 'hard-mandatory' means the run will fail and cannot be overridden if the policy fails
    enforcement_level = "hard-mandatory"
}

# Policy to block the opening of specific forbidden ports (e.g., Port 22 for SSH globally)
policy "restrict-gce-firewall-ports" {
    source = "./restrict-gce-firewall-ports.sentinel"
    # 'advisory' means it will show a warning, 'soft-mandatory' can be overridden by admins
    enforcement_level = "hard-mandatory"
}
