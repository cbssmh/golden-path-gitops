#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT_DIR}/config/values.env"

mode="${1:-write}"
if [[ $# -gt 1 || "${mode}" != "write" && "${mode}" != "--check" ]]; then
  echo "Usage: $0 [--check]" >&2
  exit 2
fi

render_template() {
  local template="$1"
  local output="$2"
  sed \
    -e "s|__GITOPS_REPOSITORY_URL__|${GITOPS_REPOSITORY_URL}|g" \
    -e "s|__GITOPS_TARGET_REVISION__|${GITOPS_TARGET_REVISION}|g" \
    -e "s|__SERVICE_A_IMAGE__|${SERVICE_A_IMAGE}|g" \
    "${template}" >"${output}"
}

render_all() {
  local output_root="$1"

  mkdir -p \
    "${output_root}/applications/root" \
    "${output_root}/services/service-a/base"
  render_template "${ROOT_DIR}/templates/applications/root/service-a.yaml.tmpl" "${output_root}/applications/root/service-a.yaml"
  render_template "${ROOT_DIR}/templates/applications/root/service-a-identity.yaml.tmpl" "${output_root}/applications/root/service-a-identity.yaml"
  render_template "${ROOT_DIR}/templates/applications/root/dev-resource-governance.yaml.tmpl" "${output_root}/applications/root/dev-resource-governance.yaml"
  render_template "${ROOT_DIR}/templates/services/service-a/base/deployment.yaml.tmpl" "${output_root}/services/service-a/base/deployment.yaml"
}

if [[ "${mode}" == "--check" ]]; then
  temporary_root="$(mktemp -d)"
  trap 'rm -rf "${temporary_root}"' EXIT
  render_all "${temporary_root}"
  for path in \
    applications/root/service-a.yaml \
    applications/root/service-a-identity.yaml \
    applications/root/dev-resource-governance.yaml \
    services/service-a/base/deployment.yaml; do
    diff -u "${ROOT_DIR}/${path}" "${temporary_root}/${path}"
  done
  echo "PASS: generated GitOps manifests match their templates and config."
else
  render_all "${ROOT_DIR}"
  echo "Rendered GitOps manifests from config/values.env."
fi
