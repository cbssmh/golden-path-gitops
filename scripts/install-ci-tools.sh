#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT_DIR}/ci/tool-versions.env"

verify_checksum() {
  local path="$1"
  local expected_sha256="$2"
  local label="$3"
  local actual_sha256

  actual_sha256="$(sha256sum "${path}" | awk '{print $1}')"
  if [[ "${actual_sha256}" != "${expected_sha256}" ]]; then
    echo "FAIL: checksum mismatch for ${label}" >&2
    return 1
  fi
}

if [[ "${SC1_CHECKSUM_SELF_TEST:-0}" == "1" ]]; then
  fixture="$(mktemp)"
  trap 'rm -f "${fixture}"' EXIT
  printf 'checksum-negative-fixture\n' >"${fixture}"
  if verify_checksum "${fixture}" "$(printf '0%.0s' {1..64})" fixture 2>/dev/null; then
    echo "FAIL: incorrect checksum was accepted." >&2
    exit 1
  fi
  echo "PASS: incorrect checksum is rejected."
  exit 0
fi

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "FAIL: the CI tool installer supports Linux only." >&2
  exit 1
fi

case "$(uname -m)" in
  x86_64)
    tool_arch="amd64"
    kubectl_sha256="${KUBECTL_LINUX_AMD64_SHA256}"
    kubeconform_sha256="${KUBECONFORM_LINUX_AMD64_SHA256}"
    ;;
  aarch64|arm64)
    tool_arch="arm64"
    kubectl_sha256="${KUBECTL_LINUX_ARM64_SHA256}"
    kubeconform_sha256="${KUBECONFORM_LINUX_ARM64_SHA256}"
    ;;
  *)
    echo "FAIL: unsupported CI architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT
bin_dir="${RUNNER_TEMP:-${work_dir}}/golden-path-tools/bin"
mkdir -p "${bin_dir}"

download_and_verify() {
  local url="$1"
  local expected_sha256="$2"
  local destination="$3"

  curl --fail --location --silent --show-error \
    --proto '=https' --tlsv1.2 --retry 3 \
    --output "${destination}" "${url}"
  verify_checksum "${destination}" "${expected_sha256}" "${url}"
}

kubectl_path="${work_dir}/kubectl"
download_and_verify \
  "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${tool_arch}/kubectl" \
  "${kubectl_sha256}" \
  "${kubectl_path}"
install -m 0755 "${kubectl_path}" "${bin_dir}/kubectl"

kubeconform_archive="${work_dir}/kubeconform.tar.gz"
download_and_verify \
  "https://github.com/yannh/kubeconform/releases/download/${KUBECONFORM_VERSION}/kubeconform-linux-${tool_arch}.tar.gz" \
  "${kubeconform_sha256}" \
  "${kubeconform_archive}"
tar -xzf "${kubeconform_archive}" -C "${work_dir}" kubeconform
install -m 0755 "${work_dir}/kubeconform" "${bin_dir}/kubeconform"

"${bin_dir}/kubectl" version --client --output=yaml |
  grep -F "gitVersion: ${KUBECTL_VERSION}" >/dev/null
"${bin_dir}/kubeconform" -v | grep -F "${KUBECONFORM_VERSION}" >/dev/null

if [[ -n "${GITHUB_PATH:-}" ]]; then
  printf '%s\n' "${bin_dir}" >>"${GITHUB_PATH}"
else
  echo "Installed checksum-verified tools in ${bin_dir}"
fi
