# Golden Path GitOps

This repository is the Kubernetes desired-state source of truth for the local
v0.1.1 Golden Path release. It contains the Argo CD Service A Application, the
`dev` namespace, and Service A Kustomize manifests. It does not build images or
bootstrap clusters.

## Immutable release inputs

The official Platform v0.1.1 release workflow reads this repository at the
annotated `v0.1.1` tag, not `main`. The Root Application and the generated
`service-a` child Application both use `targetRevision: v0.1.1`.

[`config/values.env`](config/values.env) is the only GitOps value source. It
defines the public repository URL, the `v0.1.1` release revision, and the
immutable Service A OCI image digest:

```text
ghcr.io/cbssmh/golden-path-service-a@sha256:5972389a2b99f26c89544528e4785655aaa422b54e7f0602b4a7b77a5c640916
```

`main` remains a development branch only; it is not the documented release
source. Run `./scripts/configure.sh` after changing `config/values.env`. The
script renders tracked desired-state manifests from templates; do not edit the
generated URL, revision, or image fields directly.

## Runtime verification

The prior v0.1.0 GitOps path was runtime verified on local kind. The Platform
v0.1.1 release workflow verifies this immutable GitOps tag and records the
actual commands and runtime output in its separate v0.1.1 evidence directory.

## Validate

Run `./scripts/configure.sh` after changing configuration, then
`./scripts/validate.sh`. Validation renders all Kustomizations, rejects
`latest`, requires the configured OCI digest and release revision, checks
labels and resources, and uses kubeconform when installed.
