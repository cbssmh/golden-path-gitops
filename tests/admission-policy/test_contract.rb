#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"
require "yaml"

ROOT = File.expand_path("../..", __dir__)
FIXTURES = File.join(ROOT, "tests/fixtures/admission-policy/forbidden/*.yaml")
APPROVED_REGISTRY = "ghcr.io/cbssmh/"
IMAGE_DIGEST = %r{\A[^@]+@sha256:[0-9a-f]{64}\z}
NAMESPACE_SELECTOR = {"golden-path.io/admission" => "enabled"}.freeze
EXPECTED_EXPRESSIONS = [
  "c.image.matches('^[^@]+@sha256:[0-9a-f]{64}$')",
  "c.image.startsWith('ghcr.io/cbssmh/')",
  "serviceAccountName != 'default'",
  "automountServiceAccountToken == false",
  "c.securityContext.readOnlyRootFilesystem == true",
  "has(c.readinessProbe)",
  "has(c.livenessProbe)",
  "'cpu' in dyn(c.resources).requests",
  "object.spec.replicas <= 4"
].freeze
RESOURCE_EXPRESSION_FRAGMENTS = [
  "has(c.resources)",
  "has(dyn(c.resources).requests)",
  "has(dyn(c.resources).limits)",
  "'cpu' in dyn(c.resources).requests",
  "'memory' in dyn(c.resources).requests",
  "'cpu' in dyn(c.resources).limits",
  "'memory' in dyn(c.resources).limits"
].freeze

def fail_test(message)
  warn "FAIL: #{message}"
  exit 1
end

def assert(condition, message)
  fail_test(message) unless condition
end

def documents_from_text(text)
  YAML.load_stream(text).compact
end

def document(path)
  documents = YAML.load_stream(File.read(File.join(ROOT, path))).compact
  assert(documents.length == 1, "#{path} must contain exactly one YAML document")
  documents.first
end

def render(path)
  stdout, stderr, status = Open3.capture3("kubectl", "kustomize", File.join(ROOT, path))
  fail_test("kubectl kustomize #{path} failed: #{stderr}") unless status.success?
  documents_from_text(stdout)
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
      parent.is_a?(Array) ? parent[Integer(leaf, 10)] = operation.fetch("value") : parent[leaf] = operation.fetch("value")
    when "remove"
      parent.is_a?(Array) ? parent.delete_at(Integer(leaf, 10)) : parent.delete(leaf)
    else
      fail_test("unsupported fixture operation #{operation.fetch('op')}")
    end
  end
  result
end

def deployment_violations(deployment)
  pod = deployment.dig("spec", "template", "spec") || {}
  containers = pod.fetch("containers", [])
  init_containers = pod.fetch("initContainers", [])
  all_images = containers + init_containers
  violations = []

  violations << "image-digest" unless all_images.all? { |container| container.fetch("image", "").match?(IMAGE_DIGEST) }
  violations << "approved-registry" unless all_images.all? { |container| container.fetch("image", "").start_with?(APPROVED_REGISTRY) }

  service_account = pod.fetch("serviceAccountName", "")
  violations << "service-account" if service_account.empty? || service_account == "default"
  violations << "token-automount" unless pod["automountServiceAccountToken"] == false

  containers.each do |container|
    security = container.fetch("securityContext", {})
    resources = container.fetch("resources", {})
    requests = resources.fetch("requests", {})
    limits = resources.fetch("limits", {})

    violations << "read-only-root" unless security["readOnlyRootFilesystem"] == true
    violations << "readiness-probe" unless container["readinessProbe"].is_a?(Hash)
    violations << "liveness-probe" unless container["livenessProbe"].is_a?(Hash)
    violations << "resources" unless %w[cpu memory].all? do |resource|
      requests.key?(resource) && limits.key?(resource)
    end
  end

  replicas = deployment.dig("spec", "replicas") || 1
  violations << "replicas" unless replicas.is_a?(Integer) && (1..4).cover?(replicas)
  violations.uniq
end

admission = render("platform/admission/dev")
assert(admission.length == 2, "admission path must render exactly two resources")
policy = admission.find { |resource| resource["kind"] == "ValidatingAdmissionPolicy" }
binding = admission.find { |resource| resource["kind"] == "ValidatingAdmissionPolicyBinding" }
assert(policy, "admission path is missing ValidatingAdmissionPolicy")
assert(binding, "admission path is missing ValidatingAdmissionPolicyBinding")

assert(policy.dig("metadata", "name") == "golden-path-deployment-contract", "unexpected policy name")
assert(policy.dig("metadata", "annotations", "argocd.argoproj.io/sync-wave") == "0", "policy must precede its binding")
assert(policy.dig("spec", "failurePolicy") == "Fail", "policy failurePolicy must be Fail")
assert(policy.dig("spec", "matchConstraints", "resourceRules") == [{
  "apiGroups" => ["apps"],
  "apiVersions" => ["v1"],
  "operations" => %w[CREATE UPDATE],
  "resources" => ["deployments"],
  "scope" => "Namespaced"
}], "policy scope must be namespaced apps/v1 Deployment CREATE and UPDATE only")

validations = policy.dig("spec", "validations") || []
assert(validations.length == EXPECTED_EXPRESSIONS.length, "policy must contain nine separate validations")
assert(validations.all? { |validation| validation["reason"] == "Invalid" }, "every validation must use reason Invalid")
assert(validations.all? { |validation| !validation.fetch("message", "").empty? }, "every validation must provide a message")
EXPECTED_EXPRESSIONS.each do |fragment|
  assert(validations.any? { |validation| validation.fetch("expression", "").include?(fragment) }, "policy expression is missing #{fragment}")
end
resource_validation = validations.find do |validation|
  validation.fetch("message", "").start_with?("Resource declaration contract failed:")
end
assert(resource_validation, "resource declaration validation is missing")
RESOURCE_EXPRESSION_FRAGMENTS.each do |fragment|
  assert(resource_validation.fetch("expression").include?(fragment), "resource validation is missing #{fragment}")
end
puts "PASS: VAP defines nine readable Deployment validations with failurePolicy Fail"
puts "PASS: resource CEL requires CPU and memory requests and limits through type-check-safe map access"

assert(binding.dig("metadata", "name") == "golden-path-deployment-contract-dev", "unexpected binding name")
assert(binding.dig("metadata", "annotations", "argocd.argoproj.io/sync-wave") == "1", "binding must follow its policy")
assert(binding.dig("spec", "policyName") == "golden-path-deployment-contract", "binding references the wrong policy")
assert(binding.dig("spec", "validationActions") == %w[Warn Audit], "initial binding must use Warn and Audit only")
assert(binding.dig("spec", "matchResources", "namespaceSelector", "matchLabels") == NAMESPACE_SELECTOR, "binding namespace selector changed")

namespace = render("environments/dev").fetch(0)
assert(namespace.dig("metadata", "name") == "dev", "admission selector must be placed on Namespace/dev")
assert(NAMESPACE_SELECTOR.all? { |key, value| namespace.dig("metadata", "labels", key) == value }, "Namespace/dev admission opt-in label is missing")
puts "PASS: binding is Warn/Audit and selects only explicitly opted-in namespaces"

workload = render("services/service-a/overlays/dev")
deployment = workload.find { |resource| resource["kind"] == "Deployment" }
assert(deployment, "rendered workload is missing its Deployment")
assert(deployment_violations(deployment).empty?, "compliant Service A Deployment failed the GP-6 contract")
puts "PASS: compliant Service A Deployment satisfies the GP-6 admission contract"

missing_resources_fixture = YAML.load_file(File.join(ROOT, "tests/fixtures/admission-policy/forbidden/missing-resources.yaml"))
missing_resources_candidate = apply_patch(deployment, missing_resources_fixture.fetch("patch"))
assert(deployment_violations(missing_resources_candidate) == ["resources"], "missing resources must fail only the resource contract")
puts "PASS: Deployment without resources fails the GP-6 resource contract"

fixture_paths = Dir.glob(FIXTURES).sort
assert(fixture_paths.length == 9, "expected exactly nine admission-policy negative fixtures")
fixture_paths.each do |path|
  fixture = YAML.load_file(path)
  candidate = apply_patch(deployment, fixture.fetch("patch"))
  violations = deployment_violations(candidate)
  expected = fixture.fetch("expected")
  assert(violations == [expected], "#{fixture.fetch('name')} produced #{violations.inspect}, expected only #{expected}")
  puts "PASS: denied fixture #{fixture.fetch('name')} (#{expected})"
end

puts "PASS: GP-6 ValidatingAdmissionPolicy contract is TEST-VERIFIED / STATIC"
