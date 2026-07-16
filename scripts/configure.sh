#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT_DIR}/config/values.env"

render_template() {
  local template="$1"
  local output="$2"
  sed \
    -e "s|__GITOPS_REPOSITORY_URL__|${GITOPS_REPOSITORY_URL}|g" \
    -e "s|__GITOPS_TARGET_REVISION__|${GITOPS_TARGET_REVISION}|g" \
    -e "s|__SERVICE_A_IMAGE__|${SERVICE_A_IMAGE}|g" \
    "${template}" >"${output}"
}

render_template "${ROOT_DIR}/templates/applications/root/service-a.yaml.tmpl" "${ROOT_DIR}/applications/root/service-a.yaml"
render_template "${ROOT_DIR}/templates/services/service-a/base/deployment.yaml.tmpl" "${ROOT_DIR}/services/service-a/base/deployment.yaml"
echo "Rendered GitOps manifests from config/values.env."
