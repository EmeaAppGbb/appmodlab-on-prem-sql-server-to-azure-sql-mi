#!/usr/bin/env bash
# =============================================================================
# Deployment Script: Lakeview Medical — Azure SQL Managed Instance Lab
# =============================================================================
# Provisions the complete MI infrastructure:
#   - VNet with MI, Management, and Gateway subnets
#   - Azure SQL Managed Instance (General Purpose, 8 vCores)
#   - Azure Database Migration Service
#
# Prerequisites:
#   - Azure CLI installed and logged in (az login)
#   - Bicep CLI installed (az bicep install)
#   - Contributor role on the target subscription
#
# Usage:
#   ./deploy.sh                                    # Uses defaults
#   ./deploy.sh -g myResourceGroup -l westeurope   # Custom RG and location
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Default configuration (override via command-line flags)
# ---------------------------------------------------------------------------
RESOURCE_GROUP="rg-lakeview-mi-lab"
LOCATION="eastus2"
DEPLOYMENT_NAME="lakeview-mi-$(date +%Y%m%d-%H%M%S)"
PARAMETERS_FILE="parameters.json"
TEMPLATE_FILE="main.bicep"

# ---------------------------------------------------------------------------
# Parse command-line arguments
# ---------------------------------------------------------------------------
while getopts "g:l:p:h" opt; do
  case $opt in
    g) RESOURCE_GROUP="$OPTARG" ;;
    l) LOCATION="$OPTARG" ;;
    p) PARAMETERS_FILE="$OPTARG" ;;
    h)
      echo "Usage: $0 [-g resource-group] [-l location] [-p parameters-file]"
      echo ""
      echo "Options:"
      echo "  -g  Resource group name (default: rg-lakeview-mi-lab)"
      echo "  -l  Azure region (default: eastus2)"
      echo "  -p  Parameters file path (default: parameters.json)"
      echo "  -h  Show this help message"
      exit 0
      ;;
    *) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Resolve script directory so paths work regardless of cwd
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="${SCRIPT_DIR}/${TEMPLATE_FILE}"
PARAMETERS_FILE="${SCRIPT_DIR}/${PARAMETERS_FILE}"

echo "============================================="
echo " Lakeview Medical — SQL MI Lab Deployment"
echo "============================================="
echo "Resource Group : ${RESOURCE_GROUP}"
echo "Location       : ${LOCATION}"
echo "Template       : ${TEMPLATE_FILE}"
echo "Parameters     : ${PARAMETERS_FILE}"
echo "Deployment     : ${DEPLOYMENT_NAME}"
echo "============================================="

# ---------------------------------------------------------------------------
# Validate prerequisites
# ---------------------------------------------------------------------------
echo ""
echo "[1/5] Checking prerequisites..."

if ! command -v az &> /dev/null; then
  echo "ERROR: Azure CLI (az) is not installed. See https://aka.ms/install-azure-cli"
  exit 1
fi

# Ensure the user is logged in
ACCOUNT=$(az account show --query "name" -o tsv 2>/dev/null || true)
if [ -z "$ACCOUNT" ]; then
  echo "ERROR: Not logged in to Azure CLI. Run 'az login' first."
  exit 1
fi
echo "  Logged in to subscription: ${ACCOUNT}"

# ---------------------------------------------------------------------------
# Prompt for the SQL admin password (avoid storing in parameter files)
# ---------------------------------------------------------------------------
echo ""
echo "[2/5] Collecting credentials..."

if [ -z "${SQL_ADMIN_PASSWORD:-}" ]; then
  read -rsp "Enter SQL MI administrator password: " SQL_ADMIN_PASSWORD
  echo ""
fi

# Validate password meets MI complexity requirements (12+ chars)
if [ ${#SQL_ADMIN_PASSWORD} -lt 12 ]; then
  echo "ERROR: Password must be at least 12 characters long."
  exit 1
fi

# ---------------------------------------------------------------------------
# Create the resource group
# ---------------------------------------------------------------------------
echo ""
echo "[3/5] Creating resource group '${RESOURCE_GROUP}' in '${LOCATION}'..."

az group create \
  --name "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --tags project=lakeview-medical environment=lab \
  --output none

echo "  Resource group ready."

# ---------------------------------------------------------------------------
# Validate the Bicep template
# ---------------------------------------------------------------------------
echo ""
echo "[4/5] Validating Bicep template..."

az deployment group validate \
  --resource-group "${RESOURCE_GROUP}" \
  --template-file "${TEMPLATE_FILE}" \
  --parameters @"${PARAMETERS_FILE}" \
  --parameters sqlAdministratorLoginPassword="${SQL_ADMIN_PASSWORD}" \
  --output none

echo "  Template validation passed."

# ---------------------------------------------------------------------------
# Deploy the infrastructure
# ---------------------------------------------------------------------------
echo ""
echo "[5/5] Deploying infrastructure (this may take 4-6 hours for SQL MI)..."
echo "  Deployment started at: $(date)"

az deployment group create \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${DEPLOYMENT_NAME}" \
  --template-file "${TEMPLATE_FILE}" \
  --parameters @"${PARAMETERS_FILE}" \
  --parameters sqlAdministratorLoginPassword="${SQL_ADMIN_PASSWORD}" \
  --verbose \
  --output json

echo ""
echo "============================================="
echo " Deployment complete!"
echo " Finished at: $(date)"
echo "============================================="

# ---------------------------------------------------------------------------
# Display key outputs
# ---------------------------------------------------------------------------
echo ""
echo "Key deployment outputs:"
az deployment group show \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${DEPLOYMENT_NAME}" \
  --query "properties.outputs" \
  --output table
