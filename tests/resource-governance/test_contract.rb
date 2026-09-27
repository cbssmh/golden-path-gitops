#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"
require "yaml"

ROOT = File.expand_path("../..", __dir__)
FIXTURES = File.join(ROOT, "tests/fixtures/resource-governance/forbidden/*.yaml")
MAX_REPLICAS = 4
QUOTA = {
  "requests.cpu" => "250m",
  "requests.memory" => "256Mi",
  "limits.cpu" => "500m",
  "limits.memory" => "512Mi",
  "pods" => "6",
  "services" => "5",
  "configmaps" => "10"
}.freeze
CONTAINER_MAX = {"cpu" => "250m", "memory" => "256Mi"}.freeze

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

def document(path)
  documents = YAML.load_stream(File.read(File.join(ROOT, path))).compact
  assert(documents.length == 1, "#{path} must contain exactly one YAML document")
  documents.first
end

def cpu_millicores(value)
  text = value.to_s
  return Integer(text.delete_suffix("m"), 10) if text.end_with?("m")
  Integer(text, 10) * 1000
rescue ArgumentError
  fail_test("unsupported CPU quantity #{value.inspect}")
end

def memory_mebibytes(value)
  text = value.to_s
  return Integer(text.delete_suffix("Mi"), 10) if text.end_with?("Mi")
  return Integer(text.delete_suffix("Gi"), 10) * 1024 if text.end_with?("Gi")
  fail_test("unsupported memory quantity #{value.inspect}")
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

def workload_violations(deployment)
  replicas = deployment.dig("spec", "replicas") || 1
  return ["replicas"] unless replicas.is_a?(Integer) && (1..MAX_REPLICAS).cover?(replicas)

  surge = deployment.dig("spec", "strategy", "rollingUpdate", "maxSurge") || 0
  return ["max-surge"] unless surge.is_a?(Integer) && surge >= 0

  containers = deployment.dig("spec", "template", "spec", "containers") || []
  return ["resources"] if containers.empty?

  resource_sets = containers.map do |container|
    resources = container.fetch("resources", {})
    requests = resources.fetch("requests", {})
    limits = resources.fetch("limits", {})
    return ["resources"] unless %w[cpu memory].all? do |resource|
      requests.fetch(resource, "").to_s != "" && limits.fetch(resource, "").to_s != ""
    end
    {"requests" => requests, "limits" => limits}
  end

  maximum_violations = []
  resource_sets.each do |resources|
    maximum_violations << "cpu-limit-max" if cpu_millicores(resources.dig("limits", "cpu")) > cpu_millicores(CONTAINER_MAX.fetch("cpu"))
    maximum_violations << "memory-limit-max" if memory_mebibytes(resources.dig("limits", "memory")) > memory_mebibytes(CONTAINER_MAX.fetch("memory"))
  end
  return maximum_violations.uniq unless maximum_violations.empty?

  rollout_pods = replicas + surge
  total_cpu_request = resource_sets.sum { |resources| cpu_millicores(resources.dig("requests", "cpu")) } * rollout_pods
  total_memory_request = resource_sets.sum { |resources| memory_mebibytes(resources.dig("requests", "memory")) } * rollout_pods
  total_cpu_limit = resource_sets.sum { |resources| cpu_millicores(resources.dig("limits", "cpu")) } * rollout_pods
  total_memory_limit = resource_sets.sum { |resources| memory_mebibytes(resources.dig("limits", "memory")) } * rollout_pods

  violations = []
  violations << "cpu-request-budget" if total_cpu_request > cpu_millicores(QUOTA.fetch("requests.cpu"))
  violations << "memory-request-budget" if total_memory_request > memory_mebibytes(QUOTA.fetch("requests.memory"))
  violations << "cpu-limit-budget" if total_cpu_limit > cpu_millicores(QUOTA.fetch("limits.cpu"))
  violations << "memory-limit-budget" if total_memory_limit > memory_mebibytes(QUOTA.fetch("limits.memory"))
  violations << "pod-budget" if rollout_pods > Integer(QUOTA.fetch("pods"), 10)
  violations
end

def governance_violations(resources)
  quota = resources.find { |resource| resource["kind"] == "ResourceQuota" }
  limit_range = resources.find { |resource| resource["kind"] == "LimitRange" }
  violations = []
  violations << "resource-quota" unless quota
  violations << "limit-range" unless limit_range
  violations
end

governance = render("platform/resource-governance/dev")
assert(governance_violations(governance).empty?, "governance path is missing ResourceQuota or LimitRange")
assert(governance.length == 2, "governance path must render exactly two resources")

quota = governance.find { |resource| resource["kind"] == "ResourceQuota" }
assert(quota.dig("metadata", "name") == "dev-resource-budget", "unexpected ResourceQuota name")
assert(quota.dig("metadata", "namespace") == "dev", "ResourceQuota must render into dev")
assert(quota.dig("spec", "hard") == QUOTA, "ResourceQuota values changed")
puts "PASS: ResourceQuota/dev-resource-budget matches the approved namespace budget"

limit_range = governance.find { |resource| resource["kind"] == "LimitRange" }
assert(limit_range.dig("metadata", "name") == "dev-container-boundary", "unexpected LimitRange name")
assert(limit_range.dig("metadata", "namespace") == "dev", "LimitRange must render into dev")
limits = limit_range.dig("spec", "limits")
assert(limits == [{"type" => "Container", "max" => CONTAINER_MAX}], "LimitRange must contain only approved Container maxima")
assert(limits.none? { |item| %w[default defaultRequest min].any? { |key| item.key?(key) } }, "LimitRange must not inject defaults or arbitrary minima")
puts "PASS: LimitRange/dev-container-boundary contains only approved Container maxima"

application = document("applications/root/dev-resource-governance.yaml")
assert(application.dig("spec", "project") == "golden-path-dev-governance", "governance Application project changed")
assert(application.dig("spec", "source", "path") == "platform/resource-governance/dev", "governance Application path changed")
assert(application.dig("spec", "destination") == {"server" => "https://kubernetes.default.svc", "namespace" => "dev"}, "governance Application destination changed")
puts "PASS: governance Application uses the dedicated dev governance project and path"

workload = render("services/service-a/overlays/dev")
deployment = workload.find { |resource| resource["kind"] == "Deployment" }
assert(deployment, "rendered Service A workload is missing its Deployment")
assert(workload_violations(deployment).empty?, "Service A does not fit the approved resource budget")

maximum_scale = Marshal.load(Marshal.dump(deployment))
maximum_scale["spec"]["replicas"] = MAX_REPLICAS
assert(workload_violations(maximum_scale).empty?, "maximum approved replicas plus rolling surge exceed the budget")
puts "PASS: Service A and four replicas plus maxSurge=1 fit the approved namespace budget"

workload_kinds = workload.map { |resource| resource["kind"] }
assert(workload_kinds.count("Service") <= Integer(QUOTA.fetch("services"), 10), "workload exceeds Service object quota")
assert(workload_kinds.count("ConfigMap") <= Integer(QUOTA.fetch("configmaps"), 10), "workload exceeds ConfigMap object quota")

fixture_paths = Dir.glob(FIXTURES).sort
assert(fixture_paths.length == 8, "expected exactly eight resource-governance negative fixtures")
fixture_paths.each do |path|
  fixture = YAML.load_file(path)
  violations = case fixture.fetch("target")
               when "workload"
                 workload_violations(apply_patch(deployment, fixture.fetch("patch")))
               when "governance"
                 candidate = governance.reject { |resource| resource["kind"] == fixture.fetch("removeKind") }
                 governance_violations(candidate)
               else
                 fail_test("unsupported fixture target #{fixture.fetch('target')}")
               end
  expected = fixture.fetch("expected")
  assert(violations == [expected], "#{fixture.fetch('name')} produced #{violations.inspect}, expected only #{expected}")
  puts "PASS: denied fixture #{fixture.fetch('name')} (#{expected})"
end

puts "PASS: GP-4 resource governance contract is TEST-VERIFIED / STATIC"
