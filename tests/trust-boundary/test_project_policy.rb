#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"
require "yaml"

ROOT = File.expand_path("../..", __dir__)
EXPECTED_REPOSITORY = "https://github.com/cbssmh/golden-path-gitops.git"
EXPECTED_SERVER = "https://kubernetes.default.svc"
EXPECTED_REVISION = "v0.4.0"
EXPECTED_ADMISSION_REVISION = "v0.6.0"
EXPECTED_NAMESPACE_KINDS = [
  ["", "ConfigMap"],
  ["", "Service"],
  ["apps", "Deployment"]
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

def documents(path)
  documents_from_text(File.read(File.join(ROOT, path)))
end

def document(path)
  docs = documents(path)
  assert(docs.length == 1, "#{path} must contain exactly one YAML document")
  docs.first
end

def render(path)
  stdout, stderr, status = Open3.capture3("kubectl", "kustomize", File.join(ROOT, path))
  fail_test("kubectl kustomize #{path} failed: #{stderr}") unless status.success?
  documents_from_text(stdout)
end

def group_kind(resource)
  api_version = resource.fetch("apiVersion")
  group = api_version.include?("/") ? api_version.split("/", 2).first : ""
  [group, resource.fetch("kind")]
end

project = document("projects/golden-path-service-a.yaml")
spec = project.fetch("spec")
assert(project.dig("metadata", "name") == "golden-path-service-a", "unexpected workload project name")
assert(project.dig("metadata", "namespace") == "argocd", "workload project must live in argocd")
assert(project.dig("metadata", "annotations", "argocd.argoproj.io/sync-wave") == "-2", "workload project must use sync wave -2")
assert(spec.fetch("sourceRepos") == [EXPECTED_REPOSITORY], "workload project sourceRepos must contain only the approved repository")
assert(spec.fetch("destinations") == [{"server" => EXPECTED_SERVER, "namespace" => "dev"}], "workload project destination must be in-cluster dev only")
assert(spec.fetch("clusterResourceWhitelist") == [], "workload project must allow no cluster resources")
allowed_kinds = spec.fetch("namespaceResourceWhitelist").map { |entry| [entry.fetch("group"), entry.fetch("kind")] }.sort
assert(allowed_kinds == EXPECTED_NAMESPACE_KINDS.sort, "workload namespaced kind whitelist is broader or narrower than the approved contract")

application = document("applications/root/service-a.yaml")
assert(application.dig("spec", "project") == "golden-path-service-a", "service-a must use golden-path-service-a")
assert(application.dig("spec", "source", "repoURL") == EXPECTED_REPOSITORY, "service-a source repository is not exact")
assert(application.dig("spec", "source", "targetRevision") == EXPECTED_REVISION, "service-a must target #{EXPECTED_REVISION}")
assert(application.dig("spec", "source", "path") == "services/service-a/overlays/dev", "service-a source path changed")
assert(application.dig("spec", "destination") == {"server" => EXPECTED_SERVER, "namespace" => "dev"}, "service-a destination must be in-cluster dev")
assert(application.dig("spec", "syncPolicy", "automated") == {"prune" => true, "selfHeal" => false}, "service-a prune/selfHeal policy changed")
assert(!application.dig("spec", "syncPolicy").key?("syncOptions"), "service-a must not auto-create its Namespace")
assert(application.dig("metadata", "annotations", "argocd.argoproj.io/sync-wave") == "1", "service-a Application must follow the identity Application")

identity_project = document("projects/golden-path-service-a-identity.yaml")
identity_spec = identity_project.fetch("spec")
assert(identity_project.dig("metadata", "name") == "golden-path-service-a-identity", "unexpected identity project name")
assert(identity_project.dig("metadata", "namespace") == "argocd", "identity project must live in argocd")
assert(identity_project.dig("metadata", "annotations", "argocd.argoproj.io/sync-wave") == "-2", "identity project must use sync wave -2")
assert(identity_spec.fetch("sourceRepos") == [EXPECTED_REPOSITORY], "identity project source repository must be exact")
assert(identity_spec.fetch("destinations") == [{"server" => EXPECTED_SERVER, "namespace" => "dev"}], "identity project destination must be in-cluster dev only")
assert(identity_spec.fetch("clusterResourceWhitelist") == [], "identity project must allow no cluster resources")
assert(identity_spec.fetch("namespaceResourceWhitelist") == [{"group" => "", "kind" => "ServiceAccount"}], "identity project must allow only ServiceAccount")

identity_application = document("applications/root/service-a-identity.yaml")
assert(identity_application.dig("spec", "project") == "golden-path-service-a-identity", "identity Application must use its dedicated project")
assert(identity_application.dig("spec", "source", "repoURL") == EXPECTED_REPOSITORY, "identity source repository is not exact")
assert(identity_application.dig("spec", "source", "targetRevision") == EXPECTED_REVISION, "identity Application must target #{EXPECTED_REVISION}")
assert(identity_application.dig("spec", "source", "path") == "platform/service-accounts/service-a", "identity source path changed")
assert(identity_application.dig("spec", "destination") == {"server" => EXPECTED_SERVER, "namespace" => "dev"}, "identity destination must be in-cluster dev")
assert(identity_application.dig("spec", "syncPolicy", "automated") == {"prune" => true, "selfHeal" => false}, "identity prune/selfHeal policy changed")
assert(identity_application.dig("metadata", "annotations", "argocd.argoproj.io/sync-wave") == "0", "identity Application must use sync wave 0")

governance_project = document("projects/golden-path-dev-governance.yaml")
governance_spec = governance_project.fetch("spec")
assert(governance_project.dig("metadata", "name") == "golden-path-dev-governance", "unexpected governance project name")
assert(governance_project.dig("metadata", "namespace") == "argocd", "governance project must live in argocd")
assert(governance_project.dig("metadata", "annotations", "argocd.argoproj.io/sync-wave") == "-2", "governance project must use sync wave -2")
assert(governance_spec.fetch("sourceRepos") == [EXPECTED_REPOSITORY], "governance source repository must be exact")
assert(governance_spec.fetch("destinations") == [{"server" => EXPECTED_SERVER, "namespace" => "dev"}], "governance destination must be in-cluster dev only")
assert(governance_spec.fetch("clusterResourceWhitelist") == [], "governance project must allow no cluster resources")
governance_kinds = governance_spec.fetch("namespaceResourceWhitelist").map do |entry|
  [entry.fetch("group"), entry.fetch("kind")]
end.sort
assert(governance_kinds == [["", "LimitRange"], ["", "ResourceQuota"]], "governance project must allow only LimitRange and ResourceQuota")

governance_application = document("applications/root/dev-resource-governance.yaml")
assert(governance_application.dig("spec", "project") == "golden-path-dev-governance", "governance Application must use its dedicated project")
assert(governance_application.dig("spec", "source", "repoURL") == EXPECTED_REPOSITORY, "governance source repository is not exact")
assert(governance_application.dig("spec", "source", "targetRevision") == EXPECTED_REVISION, "governance Application must target #{EXPECTED_REVISION}")
assert(governance_application.dig("spec", "source", "path") == "platform/resource-governance/dev", "governance source path changed")
assert(governance_application.dig("spec", "destination") == {"server" => EXPECTED_SERVER, "namespace" => "dev"}, "governance destination must be in-cluster dev")
assert(governance_application.dig("spec", "syncPolicy", "automated") == {"prune" => true, "selfHeal" => false}, "governance prune/selfHeal policy changed")
assert(governance_application.dig("metadata", "annotations", "argocd.argoproj.io/sync-wave") == "0", "governance Application must use sync wave 0")

admission_project = document("projects/golden-path-dev-admission.yaml")
admission_spec = admission_project.fetch("spec")
assert(admission_project.dig("metadata", "name") == "golden-path-dev-admission", "unexpected admission project name")
assert(admission_project.dig("metadata", "namespace") == "argocd", "admission project must live in argocd")
assert(admission_project.dig("metadata", "annotations", "argocd.argoproj.io/sync-wave") == "-2", "admission project must use sync wave -2")
assert(admission_spec.fetch("sourceRepos") == [EXPECTED_REPOSITORY], "admission source repository must be exact")
assert(admission_spec.fetch("destinations") == [{"server" => EXPECTED_SERVER, "namespace" => "dev"}], "admission destination must be in-cluster dev only")
assert(admission_spec.fetch("namespaceResourceWhitelist") == [], "admission project must allow no namespaced resources")
admission_kinds = admission_spec.fetch("clusterResourceWhitelist").map do |entry|
  [entry.fetch("group"), entry.fetch("kind")]
end.sort
expected_admission_kinds = [
  ["admissionregistration.k8s.io", "ValidatingAdmissionPolicy"],
  ["admissionregistration.k8s.io", "ValidatingAdmissionPolicyBinding"]
].sort
assert(admission_kinds == expected_admission_kinds, "admission project must allow only VAP and VAP binding")

admission_application = document("applications/root/dev-admission.yaml")
assert(admission_application.dig("spec", "project") == "golden-path-dev-admission", "admission Application must use its dedicated project")
assert(admission_application.dig("spec", "source", "repoURL") == EXPECTED_REPOSITORY, "admission source repository is not exact")
assert(admission_application.dig("spec", "source", "targetRevision") == EXPECTED_ADMISSION_REVISION, "admission Application must target #{EXPECTED_ADMISSION_REVISION}")
assert(admission_application.dig("spec", "source", "path") == "platform/admission/dev", "admission source path changed")
assert(admission_application.dig("spec", "destination") == {"server" => EXPECTED_SERVER, "namespace" => "dev"}, "admission destination must be in-cluster dev")
assert(admission_application.dig("spec", "syncPolicy", "automated") == {"prune" => true, "selfHeal" => false}, "admission prune/selfHeal policy changed")
assert(admission_application.dig("metadata", "annotations", "argocd.argoproj.io/sync-wave") == "0", "admission Application must use sync wave 0")

active_applications = Dir.glob(File.join(ROOT, "applications", "**", "*.yaml")).flat_map do |path|
  documents_from_text(File.read(path)).select { |item| item["kind"] == "Application" }
end
assert(active_applications.none? { |item| item.dig("spec", "project") == "default" }, "a current Application still uses the default project")

workload_resources = render("services/service-a/overlays/dev")
rendered_kinds = workload_resources.map { |item| group_kind(item) }.sort
assert(rendered_kinds == EXPECTED_NAMESPACE_KINDS.sort, "workload overlay must render exactly ConfigMap, Service, and Deployment")
assert(workload_resources.all? { |item| item.dig("metadata", "namespace") == "dev" }, "every workload resource must render into dev")
assert(workload_resources.none? { |item| item["kind"] == "Namespace" }, "workload overlay still owns a Namespace")

root_resources = render("applications/root")
root_kinds = root_resources.map { |item| group_kind(item) }.sort
expected_root_kinds = [
  ["", "Namespace"],
  ["argoproj.io", "AppProject"],
  ["argoproj.io", "AppProject"],
  ["argoproj.io", "AppProject"],
  ["argoproj.io", "AppProject"],
  ["argoproj.io", "Application"],
  ["argoproj.io", "Application"],
  ["argoproj.io", "Application"],
  ["argoproj.io", "Application"]
].sort
assert(root_kinds == expected_root_kinds, "root must render exactly four AppProjects, Namespace/dev, and four Applications")
namespace = root_resources.find { |item| item["kind"] == "Namespace" }
assert(namespace.dig("metadata", "name") == "dev", "root must own Namespace/dev")
assert(namespace.dig("metadata", "annotations", "argocd.argoproj.io/sync-wave") == "-1", "Namespace/dev must use sync wave -1")

identity_resources = render("platform/service-accounts/service-a")
assert(identity_resources.length == 1, "identity path must render exactly one resource")
service_account = identity_resources.first
assert(group_kind(service_account) == ["", "ServiceAccount"], "identity path must render only ServiceAccount")
assert(service_account.dig("metadata", "name") == "service-a", "identity path must own ServiceAccount/service-a")
assert(service_account.dig("metadata", "namespace") == "dev", "ServiceAccount/service-a must render into dev")
assert(service_account["automountServiceAccountToken"] == false, "ServiceAccount/service-a must disable token automount")

governance_resources = render("platform/resource-governance/dev")
assert(governance_resources.length == 2, "governance path must render exactly two resources")
assert(governance_resources.map { |item| group_kind(item) }.sort == [["", "LimitRange"], ["", "ResourceQuota"]], "governance path must render only LimitRange and ResourceQuota")
assert(governance_resources.all? { |item| item.dig("metadata", "namespace") == "dev" }, "governance resources must render into dev")

resource_cases = {
  "crd" => ["tests/fixtures/trust-boundary/forbidden/crd.yaml", :cluster],
  "cluster-role-binding" => ["tests/fixtures/trust-boundary/forbidden/cluster-role-binding.yaml", :cluster],
  "namespace" => ["tests/fixtures/trust-boundary/forbidden/namespace.yaml", :cluster],
  "storage-class" => ["tests/fixtures/trust-boundary/forbidden/storage-class.yaml", :cluster],
  "arbitrary-cluster-resource" => ["tests/fixtures/trust-boundary/forbidden/arbitrary-cluster-resource.yaml", :cluster],
  "secret" => ["tests/fixtures/trust-boundary/forbidden/secret.yaml", :namespaced],
  "service-account" => ["tests/fixtures/trust-boundary/forbidden/service-account.yaml", :namespaced]
}

resource_cases.each do |name, (path, scope)|
  resource = document(path)
  allowed = if scope == :cluster
              spec.fetch("clusterResourceWhitelist").include?({"group" => group_kind(resource)[0], "kind" => group_kind(resource)[1]})
            else
              allowed_kinds.include?(group_kind(resource))
            end
  assert(!allowed, "forbidden fixture #{name} was allowed")
  puts "PASS: denied fixture #{name} (#{scope} #{group_kind(resource).join('/')})"
end

application_cases = {
  "kube-system-destination" => "tests/fixtures/trust-boundary/forbidden/kube-system-destination.yaml",
  "argocd-destination" => "tests/fixtures/trust-boundary/forbidden/argocd-destination.yaml",
  "alternate-repository" => "tests/fixtures/trust-boundary/forbidden/alternate-repository.yaml"
}

application_cases.each do |name, path|
  candidate = document(path)
  source_allowed = spec.fetch("sourceRepos").include?(candidate.dig("spec", "source", "repoURL"))
  destination_allowed = spec.fetch("destinations").include?(candidate.dig("spec", "destination"))
  assert(!(source_allowed && destination_allowed), "forbidden fixture #{name} was allowed")
  reason = source_allowed ? "destination" : "source repository"
  puts "PASS: denied fixture #{name} (#{reason})"
end

puts "PASS: actual Service A repository, dev destination, Deployment, Service, and ConfigMap satisfy the workload project"
puts "PASS: platform identity project permits only ServiceAccount in dev"
puts "PASS: platform governance project permits only ResourceQuota and LimitRange in dev"
puts "PASS: platform admission project permits only VAP and VAP binding cluster resources"
puts "PASS: root ownership graph, namespace handoff, ServiceAccount, and resource governance are statically verified"
puts "PASS: GP-2A trust-boundary policy is TEST-VERIFIED / STATIC"
