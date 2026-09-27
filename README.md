# Golden Path GitOps

This repository is the Kubernetes desired-state source for the local Golden
Path platform. GP-2A `v0.2.0` established and runtime-verified the Argo CD
deployment boundary. GP-3 `v0.3.0` released and runtime-verified a hardened
workload, Restricted Pod Security Admission, and a platform-owned
ServiceAccount. The current GP-4 changes prepare a `v0.4.0` release candidate
with platform-owned namespace resource governance. This repository does not
build images or bootstrap clusters.

## Release inputs

Released workflows read annotated tags, not `main`. GP-4 prepares
`targetRevision: v0.4.0`; that tag does not exist during the implementation
review gate and must not be created before governance approval.

[`config/values.env`](config/values.env) is the GitOps value source. It defines
the public repository URL, the `v0.4.0` candidate revision, and the
immutable Service A OCI image digest:

```text
ghcr.io/cbssmh/golden-path-service-a@sha256:5972389a2b99f26c89544528e4785655aaa422b54e7f0602b4a7b77a5c640916
```

`main` remains a development branch; it is not a release source. Run
`./scripts/configure.sh` after changing `config/values.env`. The
script renders tracked desired-state manifests from templates; do not edit the
generated URL, revision, or image fields directly.

## GP-2A trust boundary

The root owns the `golden-path-service-a` AppProject, Namespace `dev`, and the
Service A Application. The Service A overlay renders only Deployment, Service,
and ConfigMap resources. Its AppProject permits only the exact GitOps
repository, the in-cluster `dev` destination, those three namespaced kinds, and
no cluster-scoped resources.

This boundary is SOURCE-CONFIRMED, TEST-VERIFIED, and RUNTIME-VERIFIED. It is
not a multi-tenant claim, and the Argo application-controller remains a
cluster-wide, high-trust identity. CODEOWNERS documents path responsibility;
with one maintainer it does not provide independent human review.

## GP-3 workload security boundary

Service A declares a non-root UID, RuntimeDefault seccomp, no privilege
escalation, no Linux capabilities, and a read-only root filesystem. The Pod
uses a dedicated tokenless ServiceAccount. Namespace `dev` enables the
Kubernetes v1.36 Restricted Pod Security Standard in enforce, audit, and warn
modes.

The workload AppProject remains limited to Deployment, Service, and ConfigMap.
A separate platform-owned identity Application uses a dedicated AppProject
that permits only ServiceAccount in `dev`. No RBAC binding is created.

The rendered positive contract and nine negative fixtures are
TEST-VERIFIED / STATIC. The released GP-3 workload, effective identity, token
absence, read-only root filesystem, and Restricted PSA enforcement were also
RUNTIME-VERIFIED in a disposable cluster.

## GP-4 resource governance boundary

Namespace `dev` has a platform-owned aggregate ResourceQuota and a Container
LimitRange with explicit CPU and memory maxima. A dedicated
`golden-path-dev-governance` AppProject permits only ResourceQuota and
LimitRange in `dev`; the workload and identity AppProjects remain unchanged.

The positive contract verifies exact quota values, exact per-container maxima,
and that Service A plus its rolling surge fit the budget. Eight isolated
negative fixtures cover excessive replicas, CPU and memory requests and
limits, missing resources, and missing governance objects. These results are
TEST-VERIFIED / STATIC. Kubernetes quota and LimitRange admission remain NOT
RUNTIME-VERIFIED until a separately approved disposable runtime phase.

## Runtime verification

The v0.1.x path, GP-2A `v0.2.0` boundary, and GP-3 `v0.3.0` workload security
baseline were runtime verified on local disposable kind clusters. GP-4 has not
been applied to a cluster.

## Validate

Run `./scripts/configure.sh` after changing configuration, then
`./scripts/validate.sh`. Validation renders all Kustomizations, rejects
`latest`, requires the configured OCI digest and release revision, checks
labels, evaluates the AppProject/Application ownership contract, validates the
complete workload security contract and isolated denied fixtures, and uses
kubeconform when installed. It also verifies the complete GP-4 resource
governance contract and eight negative fixtures. GP-4 results are
TEST-VERIFIED / STATIC, not proof of Kubernetes admission enforcement.
