# GP-6 ValidatingAdmissionPolicy

## Evidence state

GP-6 is an admission-policy release candidate. Its manifests are
`SOURCE-CONFIRMED`, and its semantic positive and negative contract tests are
`TEST-VERIFIED / STATIC`. Kubernetes admission behavior is
`NOT RUNTIME-VERIFIED`.

The initial binding uses `Warn` and `Audit`. GP-6 does not yet reject a
Deployment, and this document makes no runtime-enforcement claim.

## Admission ownership

The platform-owned `golden-path-dev-admission` AppProject permits only these
cluster-scoped kinds:

- `admissionregistration.k8s.io/ValidatingAdmissionPolicy`;
- `admissionregistration.k8s.io/ValidatingAdmissionPolicyBinding`.

It has no namespaced-resource permission. The `dev-admission` Application
owns the admission path and targets the future GitOps `v0.6.0` release.

The existing workload, identity, and resource-governance AppProjects remain
unchanged. In particular, `golden-path-service-a` still permits only
Deployment, Service, and ConfigMap in `dev` and has no cluster-resource
authority.

## Contract

`golden-path-deployment-contract` matches CREATE and UPDATE requests for
namespaced `apps/v1` Deployments. Its separate CEL validations require:

- immutable SHA-256 image references for containers and init containers;
- the approved `ghcr.io/cbssmh/` registry path;
- an explicit, non-default ServiceAccount;
- `automountServiceAccountToken: false`;
- `readOnlyRootFilesystem: true` for every regular container;
- readiness and liveness probes for every regular container;
- explicit CPU and memory requests and limits for every regular container;
- between one and four replicas, treating an omitted value as one.

The policy uses `failurePolicy: Fail`, so CEL evaluation or policy errors are
handled according to the binding actions. The initial
`golden-path-deployment-contract-dev` binding uses `Warn` and `Audit` only.
It selects namespaces carrying `golden-path.io/admission: enabled`; only the
platform-owned `dev` Namespace declares that label.

Argo syncs the policy at wave `0` and its binding at wave `1`, so the binding
does not precede its policy definition.

## Existing control ownership

GP-6 does not duplicate other Golden Path controls:

- Argo CD AppProjects continue to own repository, destination, and allowed-kind
  boundaries.
- Restricted Pod Security Admission continues to own standardized Pod security
  requirements such as non-root execution, seccomp, privilege escalation, and
  Linux capabilities.
- ResourceQuota continues to own aggregate namespace consumption.
- LimitRange continues to own numeric per-container CPU and memory maxima.
- CI continues to own render integrity, release identity, exact UID `10001`,
  labels, and rollout-budget arithmetic.

GP-6 does not verify image signatures, provenance, SBOMs, vulnerabilities, or
remote registry content.

## Warn/Audit rollout

Before changing the binding to `Deny`, a separately approved disposable
Kubernetes `v1.36.1` runtime must verify:

1. the policy and binding are accepted without CEL type-check warnings;
2. the released Service A Deployment produces no admission warning;
3. every negative fixture produces the intended warning and audit evidence;
4. Argo applications and Service A remain healthy;
5. the same fixtures are rejected after an explicit, separately reviewed
   transition to `Deny` and `Audit`.

The Deny transition requires its own governed change. It must not add user,
group, or controller bypass actors.

## Residual risks

- A cluster administrator can alter or remove the policy, binding, or Namespace
  selector label.
- After a future Deny transition, a malformed CEL expression can block matching
  Deployment updates.
- Deployment-only validation does not govern direct Pod creation outside the
  Argo workload path; PSA and resource governance still apply to those Pods.
- Digest and registry validation prove reference shape and location, not image
  provenance, signature, or safety.
- Probe and resource presence do not prove that their values are operationally
  correct.
