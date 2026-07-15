#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

for path in applications/root environments/dev services/service-a/overlays/dev; do
  kubectl kustomize "${path}" >/dev/null
done

if rg -n 'image:.*:latest|newTag: latest' . --glob '*.yaml'; then
  echo "FAIL: latest image tags are forbidden." >&2
  exit 1
fi
for label in name instance version managed-by part-of; do
  if ! rg -U "app\.kubernetes\.io/${label}:" services/service-a --glob '*.yaml' >/dev/null; then
    echo "FAIL: required label app.kubernetes.io/${label} is missing." >&2
    exit 1
  fi
done
if ! rg -U 'requests:|limits:' services/service-a/base/deployment.yaml >/dev/null; then
  echo "FAIL: resource requests and limits are required." >&2
  exit 1
fi
if command -v kubeconform >/dev/null 2>&1; then
  kubectl kustomize services/service-a/overlays/dev | kubeconform -strict -summary
else
  echo "SKIP: kubeconform is not installed."
fi
git diff --check
echo "PASS: GitOps validation completed."
