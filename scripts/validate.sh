#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"
# shellcheck source=/dev/null
source "${ROOT_DIR}/config/values.env"
# shellcheck source=/dev/null
source "${ROOT_DIR}/ci/tool-versions.env"

validate_rendering() {
  "${ROOT_DIR}/scripts/configure.sh" --check
  for path in \
    applications/root \
    projects \
    environments/dev \
    platform/resource-governance/dev \
    platform/service-accounts/service-a \
    services/service-a/overlays/dev; do
    kubectl kustomize "${path}" >/dev/null
  done
  echo "PASS: Kustomize render validation completed."
}

validate_contracts() {
  ruby tests/trust-boundary/test_project_policy.rb
  ruby tests/workload-security/test_contract.rb
  ruby tests/resource-governance/test_contract.rb
  ruby tests/supply-chain/test_pins.rb
}

validate_artifacts() {
  if grep -R -n -E 'image:.*:latest|newTag: latest' . --include='*.yaml'; then
    echo "FAIL: latest image tags are forbidden." >&2
    exit 1
  fi
  if [[ "${SERVICE_A_IMAGE}" != *@sha256:* ]]; then
    echo "FAIL: Service A image must use an OCI digest." >&2
    exit 1
  fi
  grep -F "targetRevision: ${GITOPS_TARGET_REVISION}" applications/root/service-a.yaml >/dev/null
  grep -F "targetRevision: ${GITOPS_TARGET_REVISION}" applications/root/service-a-identity.yaml >/dev/null
  grep -F "targetRevision: ${GITOPS_TARGET_REVISION}" applications/root/dev-resource-governance.yaml >/dev/null
  grep -F "image: ${SERVICE_A_IMAGE}" services/service-a/base/deployment.yaml >/dev/null
  for label in name instance version managed-by part-of; do
    if ! grep -R -E "app\.kubernetes\.io/${label}:" services/service-a \
      --include='*.yaml' >/dev/null; then
      echo "FAIL: required label app.kubernetes.io/${label} is missing." >&2
      exit 1
    fi
  done
  echo "PASS: artifact, revision, and label validation completed."
}

validate_schemas() {
  if ! command -v kubeconform >/dev/null 2>&1; then
    echo "FAIL: kubeconform is required for schema validation." >&2
    exit 1
  fi
  local schema_location
  schema_location="https://raw.githubusercontent.com/yannh/kubernetes-json-schema/${KUBERNETES_SCHEMA_COMMIT}/v${KUBERNETES_SCHEMA_VERSION}-standalone-strict/{{.ResourceKind}}{{.KindSuffix}}.json"
  for path in \
    environments/dev \
    platform/resource-governance/dev \
    platform/service-accounts/service-a \
    services/service-a/overlays/dev; do
    kubectl kustomize "${path}" | kubeconform \
      -strict \
      -summary \
      -kubernetes-version "${KUBERNETES_SCHEMA_VERSION}" \
      -schema-location "${schema_location}"
  done
  echo "PASS: kubeconform schema validation completed."
}

validate_whitespace() {
  git diff --check
  echo "PASS: whitespace validation completed."
}

echo "== Render validation =="
validate_rendering
echo "== GP-2A through GP-5 and SC-1 static contracts =="
validate_contracts
echo "== Artifact and image contract =="
validate_artifacts
echo "== Kubernetes schema validation =="
validate_schemas
echo "== Whitespace validation =="
validate_whitespace
echo "PASS: GitOps validation completed."
