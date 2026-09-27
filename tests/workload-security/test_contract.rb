#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"
require "yaml"

ROOT = File.expand_path("../..", __dir__)
FIXTURES = File.join(ROOT, "tests/fixtures/workload-security/forbidden/*.yaml")
EXPECTED_PSA_LABELS = {
  "pod-security.kubernetes.io/enforce" => "restricted",
  "pod-security.kubernetes.io/enforce-version" => "v1.36",
  "pod-security.kubernetes.io/audit" => "restricted",
  "pod-security.kubernetes.io/audit-version" => "v1.36",
  "pod-security.kubernetes.io/warn" => "restricted",
  "pod-security.kubernetes.io/warn-version" => "v1.36"
}.freeze

def fail_test(message)
  warn "FAIL: #{message}"
  exit 1
end

def assert(condition, message)
  fail_test(message) unless condition
end

def render(path)
  stdout, stderr, status = Open3.capture3("kubectl", "kustomize", File.join(ROOT, path))
  fail_test("kubectl kustomize #{path} failed: #{stderr}") unless status.success?
  YAML.load_stream(stdout).compact
end

def workload_violations(deployment)
  pod = deployment.dig("spec", "template", "spec") || {}
  pod_security = pod.fetch("securityContext", {})
  violations = []

  violations << "host-network" if pod["hostNetwork"] == true
  violations << "host-path" if pod.fetch("volumes", []).any? { |volume| volume.key?("hostPath") }
  violations << "service-account" unless pod["serviceAccountName"] == "service-a"
  violations << "token-automount" unless pod["automountServiceAccountToken"] == false
  violations << "run-as-non-root" unless pod_security["runAsNonRoot"] == true
  violations << "run-as-user" unless pod_security["runAsUser"] == 10_001
  violations << "seccomp" unless pod_security.dig("seccompProfile", "type") == "RuntimeDefault"

  containers = pod.fetch("containers", [])
  violations << "containers" if containers.empty?
  containers.each do |container|
    security = container.fetch("securityContext", {})
    capabilities = security.fetch("capabilities", {})
    resources = container.fetch("resources", {})
    requests = resources.fetch("requests", {})
    limits = resources.fetch("limits", {})

    violations << "privileged" if security["privileged"] == true
    violations << "privilege-escalation" unless security["allowPrivilegeEscalation"] == false
    violations << "capabilities" unless capabilities.fetch("drop", []).include?("ALL")
    violations << "capabilities" unless capabilities.fetch("add", []).empty?
    violations << "read-only-root" unless security["readOnlyRootFilesystem"] == true
    violations << "resources" unless %w[cpu memory].all? do |resource|
      requests.fetch(resource, "").to_s != "" && limits.fetch(resource, "").to_s != ""
    end
    violations << "readiness-probe" unless container["readinessProbe"].is_a?(Hash)
    violations << "liveness-probe" unless container["livenessProbe"].is_a?(Hash)
    violations << "immutable-image" unless container.fetch("image", "").match?(
      %r{\A[^@\s]+@sha256:[0-9a-f]{64}\z}
    )
  end

  violations.uniq
end

def apply_patch(document, operations)
  result = Marshal.load(Marshal.dump(document))
  operations.each do |operation|
    parts = operation.fetch("path").split("/").drop(1).map do |part|
      part.gsub("~1", "/").gsub("~0", "~")
    end
    leaf = parts.pop
    parent = parts.reduce(result) do |value, part|
      value.is_a?(Array) ? value.fetch(Integer(part, 10)) : value.fetch(part)
    end

    case operation.fetch("op")
    when "add", "replace"
      if parent.is_a?(Array)
        parent[Integer(leaf, 10)] = operation.fetch("value")
      else
        parent[leaf] = operation.fetch("value")
      end
    when "remove"
      parent.is_a?(Array) ? parent.delete_at(Integer(leaf, 10)) : parent.delete(leaf)
    else
      fail_test("unsupported fixture operation #{operation.fetch('op')}")
    end
  end
  result
end

workload = render("services/service-a/overlays/dev")
deployment = workload.find { |resource| resource["kind"] == "Deployment" }
assert(deployment, "rendered Service A workload is missing its Deployment")
assert(workload_violations(deployment).empty?, "hardened Service A Deployment failed the contract")
puts "PASS: hardened Service A Deployment satisfies the GP-3 workload contract"

namespace = render("environments/dev").fetch(0)
labels = namespace.dig("metadata", "labels") || {}
assert(EXPECTED_PSA_LABELS.all? { |key, value| labels[key] == value }, "Namespace/dev PSA labels are incomplete")
puts "PASS: Namespace/dev enforces the Kubernetes v1.36 Restricted profile"

identity = render("platform/service-accounts/service-a")
assert(identity.length == 1 && identity.first["kind"] == "ServiceAccount", "identity path must render one ServiceAccount")
service_account = identity.first
assert(service_account.dig("metadata", "name") == "service-a", "unexpected ServiceAccount name")
assert(service_account.dig("metadata", "namespace") == "dev", "ServiceAccount must render into dev")
assert(service_account["automountServiceAccountToken"] == false, "ServiceAccount token automount must be disabled")
puts "PASS: platform-owned ServiceAccount/service-a is tokenless"

fixture_paths = Dir.glob(FIXTURES).sort
assert(fixture_paths.length == 9, "expected exactly nine workload-security negative fixtures")
fixture_paths.each do |path|
  fixture = YAML.load_file(path)
  candidate = apply_patch(deployment, fixture.fetch("patch"))
  violations = workload_violations(candidate)
  expected = fixture.fetch("expected")
  assert(violations == [expected], "#{fixture.fetch('name')} produced #{violations.inspect}, expected only #{expected}")
  puts "PASS: denied fixture #{fixture.fetch('name')} (#{expected})"
end

puts "PASS: GP-3 workload security contract is TEST-VERIFIED / STATIC"
