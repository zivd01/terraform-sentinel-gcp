# This module adheres to the Single Responsibility Principle (SRP).
# Its sole responsibility is securely exposing and validating runtime environments.

################################################################################
# Loads variable mappings from config.env and strictly validates required inputs.
#
# Arguments:
#   $@ (list of strings): A dynamic list of environment variable names that are
#                         strictly required for the caller script's execution.
# Outputs:
#   Writes validation error tracebacks to stdout if an environment variable is 
#   missing, unmapped, or still utilizing template placeholder strings.
# Returns:
#   0 upon successfully mapping and validating all arguments. 
# Raises:
#   Exit (1) if config.env does not exist or if any parameters fail validation.
################################################################################
load_and_validate_env() {
    # 1. Strictly enforce the presence of the configuration file mapping
    if [ ! -f "config.env" ]; then
        echo "Error: config.env file not found. Please create it and fill in your variables."
        exit 1
    fi
    
    # 2. Source the environments securely into memory
    source config.env

    # 3. Dynamic array resolution for explicitly passed required variables
    local REQUIRED_VARS=("$@")
    
    for VAR in "${REQUIRED_VARS[@]}"; do
        # Protect against empty strings or undeleted template placeholders
        if [ -z "${!VAR}" ] || [[ "${!VAR}" == "your-"* ]] || [[ "${!VAR}" == "ws-123"* ]]; then
            echo "Error: Missing or default placeholder value for the required variable: $VAR in config.env."
            echo "Please inspect config.env and replace '$VAR' with your actual production data."
            exit 1
        fi
    done
}
