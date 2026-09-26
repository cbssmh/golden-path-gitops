# Golden Path GitOps

This repository is the Kubernetes desired-state source for the local Golden
Path platform. The historical v0.1.1 release is runtime-verified. The current
GP-2A changes prepare a v0.2.0 release candidate with a workload AppProject,
platform-owned `dev` namespace, Service A Application, and Service A Kustomize
manifests. It does not build images or bootstrap clusters.

## Release inputs

The verified Platform v0.1.1 workflow reads the annotated `v0.1.1` tag, not
`main`. GP-2A prepares `targetRevision: v0.2.0`; that tag is not created until
the repository-governance approval gate. An unprotected Git tag is not treated
as immutable.

[`config/values.env`](config/values.env) is the GitOps value source. It defines
the public repository URL, the `v0.2.0` candidate revision, and the
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

This is SOURCE/TEST-CONFIRMED and not yet RUNTIME-VERIFIED. It is not a
multi-tenant claim, and the Argo application-controller remains a cluster-wide,
high-trust identity. CODEOWNERS documents path responsibility; with one
maintainer it does not provide independent human review.

## Runtime verification

The prior v0.1.0 path and Platform v0.1.1 release were runtime verified on
local kind. GP-2A runtime verification requires a separately approved clean
v0.2.0 bootstrap.

## Validate

Run `./scripts/configure.sh` after changing configuration, then
`./scripts/validate.sh`. Validation renders all Kustomizations, rejects
`latest`, requires the configured OCI digest and release revision, checks
labels and resources, evaluates the real AppProject/Application contract and
isolated denied fixtures, and uses kubeconform when installed. These policy
results are TEST-VERIFIED / STATIC rather than runtime proof.
