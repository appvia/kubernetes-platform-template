#!/usr/bin/env bash
#
# This script validates all cluster and workload definitions in the release
# directory using check-jsonschema.
#
# Usage: scripts/validate-schema.sh
#
# Prerequisites:
#   - check-jsonschema installed (pip install check-jsonschema)
#

set -euo pipefail

# The revision to use from the kubernetes-platform
PLATFORM_REVISION="main"
# The location of the kubernetes-platform repository
PLATFORM_REPO="appvia/kubernetes-platform"
# The location of the JSON schema files (relative to the repository root)
CLUSTER_SCHEMA="clusters.json"
# The location of the workload schema file (relative to the repository root)
WORKLOAD_SCHEMA="applications.json"
# The default path to the cluster definitions to validate
CLUSTERS_PATH="clusters"
# The default path to the workload definitions to validate
WORKLOADS_PATH="workloads"
# Whether to use the local schema files instead of downloading from the repository
DISABLE_LOCAL_SCHEMAS=false
# The path to the schemas directory
SCHEMAS_DIR="schemas"
# The number of errors encountered
ERRORS=0

usage() {
  cat << EOF
  Usage: $0 [options]

  -r|--platform-revision <revision>   The revision to use from the kubernetes-platform (default: ${PLATFORM_REVISION})
  -p|--platform-repo <repo>           The location of the kubernetes-platform repository (default: ${PLATFORM_REPO})
  -c|--clusters <dir>                 The path to the cluster definitions to validate (default: ${CLUSTERS_PATH})
  -w|--workloads <dir>                The path to the workload definitions to validate (default: ${WORKLOADS_PATH})
  -s|--schemas-dir <dir>              The path to the schemas directory (default: ${SCHEMAS_DIR})
  --disable-local-schemas             Disable the use of local schema files and always download from the repository (default: ${DISABLE_LOCAL_SCHEMAS})
  -h|--help                           Show this help message and exit
EOF
  if [[ -z ${*}   ]]; then
    echo "[ERROR] ${*}"
    exit 1
  fi
  exit 0
}

## Check dependencies
if ! command -v check-jsonschema &> /dev/null; then
  echo "ERROR: check-jsonschema is not installed."
  echo "Install with: pip install check-jsonschema"
  exit 1
fi

## Parse the command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -r | --platform-revision)
      PLATFORM_REVISION=$2
      shift 2
      ;;
    -p | --platform-repo)
      PLATFORM_REPO=$2
      shift 2
      ;;
    -c | --clusters)
      CLUSTERS_PATH=$2
      shift 2
      ;;
    -w | --workloads)
      WORKLOADS_PATH=$2
      shift 2
      ;;
    -s | --schemas-dir)
      SCHEMAS_DIR=$2
      shift 2
      ;;
    --disable-local-schemas)
      DISABLE_LOCAL_SCHEMAS=true
      shift
      ;;
    -h | --help)
      usage
      ;;
    *)
      echo "Unknown option: $1"
      usage
      ;;
  esac
done

# We need to retrieve the schema files from the kubernetes-platform repository to validate
# the definitions. We can either clone the repository or fetch the files directly using curl.
download-schemas() {
  local urls
  local file_path

  # Ensure the schemas directory exists
  if [[ ! -d ${SCHEMAS_DIR}   ]]; then
    mkdir -p "${SCHEMAS_DIR}"
  fi

  # https://raw.githubusercontent.com/appvia/kubernetes-platform/refs/heads/main/schemas/clusters.json
  urls=(
    "https://raw.githubusercontent.com/${PLATFORM_REPO}/refs/heads/${PLATFORM_REVISION}/schemas/${CLUSTER_SCHEMA}"
    "https://raw.githubusercontent.com/${PLATFORM_REPO}/refs/heads/${PLATFORM_REVISION}/schemas/${WORKLOAD_SCHEMA}"
  )

  for url in "${urls[@]}"; do
    file_path="${url##*/}"
    # Check if we should use the local schema files
    if [[ $DISABLE_LOCAL_SCHEMAS == false ]]; then
      # Check if the schema file exists in the local schemas directory
      if [[ -f "${SCHEMAS_DIR}/${file_path}" ]]; then
        echo "Using local schema file: ${file_path}"
        continue
      fi
    fi
    echo "Downloading schema file: ${url}"

    if ! curl -qsL "$url" -o "${SCHEMAS_DIR}/${file_path}"; then
      usage "Failed to download schema file: ${url}"
    fi
  done
}

## Download the schema files
if ! download-schemas; then
  usage "Failed to download schema files"
fi

## Validate cluster definitions
echo "=== Validating cluster definitions ==="
while IFS= read -r -d '' cluster_file; do
  rel_path="${cluster_file}"
  if check-jsonschema --schemafile "${SCHEMAS_DIR}/${CLUSTER_SCHEMA}" "$cluster_file" > /dev/null 2>&1; then
    echo "  PASS: $rel_path"
  else
    echo "  FAIL: $rel_path"
    check-jsonschema --schemafile "${SCHEMAS_DIR}/${CLUSTER_SCHEMA}" "$cluster_file" 2>&1 | sed 's/^/    /'
    ERRORS=$((ERRORS + 1))
  fi
done < <(find "$CLUSTERS_PATH" -name "*.yaml" -print0)

## Validate workload definitions (applications and system workloads)
echo ""
echo "=== Validating workload definitions ==="
while IFS= read -r -d '' workload_file; do
  rel_path="${workload_file}"
  # Check if the content contains ^helm: or ^kustomize:
  if ! grep -qE '^(helm|kustomize):' "$workload_file"; then
    echo "  SKIP: $rel_path (no helm/kustomize key)"
    continue
  fi
  if check-jsonschema --schemafile "${SCHEMAS_DIR}/${WORKLOAD_SCHEMA}" "$workload_file" > /dev/null 2>&1; then
    echo "  PASS: $rel_path"
  else
    echo "  FAIL: $rel_path"
    check-jsonschema --schemafile "${SCHEMAS_DIR}/${WORKLOAD_SCHEMA}" "$workload_file" 2>&1 | sed 's/^/    /'
    ERRORS=$((ERRORS + 1))
  fi
done < <(find "$WORKLOADS_PATH" -name "*.yaml" -print0)

## Summary
echo ""
if [[ $ERRORS -eq 0 ]]; then
  echo "All definitions validated successfully."
  exit 0
else
  echo "Validation failed with $ERRORS error(s)."
  exit 1
fi
