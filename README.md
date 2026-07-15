# Golden Path GitOps

This repository, intended for `https://github.com/cbssmh/golden-path-gitops.git` on `main`, is the Kubernetes desired-state source of truth for v0.1.0. It contains the Argo CD Service A Application, the `dev` namespace, and Service A Kustomize manifests. It does not build images or bootstrap clusters.

## Configuration

[`config/values.env`](config/values.env) is the only GitOps value source. It defines the public `https://github.com/cbssmh/golden-path-gitops.git` URL on `main` and the fixed Service A image `ghcr.io/cbssmh/golden-path-service-a:4d72badd815328bbd557bf724773561ec4369263`. Images are pinned by immutable Git SHA after Application CI publishes and validates them; `latest` and automated GitOps updates are not used. Run `./scripts/configure.sh` after changing it. The script renders tracked desired-state manifests from templates; do not edit generated URL or image values directly.

**Current state: IMPLEMENTED BUT NOT RUNTIME VERIFIED.** Runtime verification waits for this public GitHub repository to be created and populated.

## Validate

Run `./scripts/configure.sh` after changing configuration, then `./scripts/validate.sh`. Validation renders all Kustomizations, rejects `latest`, checks labels and resources, and uses kubeconform when installed.
