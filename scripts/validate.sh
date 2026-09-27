#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"
# shellcheck source=/dev/null
source "${ROOT_DIR}/config/values.env"

for path in \
  applications/root \
  projects \
  environments/dev \
  platform/service-accounts/service-a \
  services/service-a/overlays/dev; do
  kubectl kustomize "${path}" >/dev/null
done

ruby tests/trust-boundary/test_project_policy.rb
ruby tests/workload-security/test_contract.rb

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
grep -F "image: ${SERVICE_A_IMAGE}" services/service-a/base/deployment.yaml >/dev/null
for label in name instance version managed-by part-of; do
  if ! grep -R -E "app\.kubernetes\.io/${label}:" services/service-a \
    --include='*.yaml' >/dev/null; then
    echo "FAIL: required label app.kubernetes.io/${label} is missing." >&2
    exit 1
  fi
done
if command -v kubeconform >/dev/null 2>&1; then
  for path in \
    environments/dev \
    platform/service-accounts/service-a \
    services/service-a/overlays/dev; do
    kubectl kustomize "${path}" | kubeconform -strict -summary
  done
else
  echo "SKIP: kubeconform is not installed."
fi
git diff --check
echo "PASS: GitOps validation completed."
