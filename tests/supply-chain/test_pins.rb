# frozen_string_literal: true

require 'pathname'

root = Pathname.new(__dir__).join('../..').expand_path
workflow = root.join('.github/workflows/validate.yml').read
installer = root.join('scripts/install-ci-tools.sh').read
versions = root.join('ci/tool-versions.env').read

failures = []
workflow.scan(/^\s*- uses:\s*([^\s#]+)/).flatten.each do |reference|
  next if reference.start_with?('./')
  next if reference.match?(%r{\A[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+@[0-9a-f]{40}\z})

  failures << "external Action is not pinned to a full commit SHA: #{reference}"
end

failures << 'workflow uses ubuntu-latest' if workflow.include?('ubuntu-latest')
failures << 'workflow contains a floating latest reference' if workflow.match?(%r{releases/latest|[:/@-]latest(?:\s|$)})
failures << 'installer contains curl-to-tar execution' if installer.match?(/curl[^\n]*\|\s*tar/)
failures << 'installer does not fail on checksum mismatch' unless installer.include?('checksum mismatch')
unless system({ 'SC1_CHECKSUM_SELF_TEST' => '1' }, '/usr/bin/env', 'bash',
              root.join('scripts/install-ci-tools.sh').to_s,
              out: File::NULL, err: File::NULL)
  failures << 'checksum negative self-test failed'
end
failures << 'kubectl is not pinned to v1.36.1' unless versions.include?('KUBECTL_VERSION=v1.36.1')
failures << 'kubeconform is not pinned to v0.8.0' unless versions.include?('KUBECONFORM_VERSION=v0.8.0')
unless versions.match?(/^KUBERNETES_SCHEMA_COMMIT=[0-9a-f]{40}$/)
  failures << 'Kubernetes schemas are not pinned to a full commit SHA'
end

abort("FAIL: #{failures.join('; ')}") unless failures.empty?

puts 'PASS: SC-1 GitOps supply-chain pins are enforced.'
