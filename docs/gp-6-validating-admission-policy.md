# GP-6 ValidatingAdmissionPolicy

## Evidence state

The corrected GP-6 admission policy is released as GitOps `v0.6.1`. Its
manifests are `SOURCE-CONFIRMED`, and its semantic positive and negative
contract tests are `TEST-VERIFIED / STATIC`. Kubernetes `v1.36.1` type
checking and Warn/Audit behavior are `RUNTIME-VERIFIED`.

The released binding uses `Warn` and `Audit`; it does not reject a Deployment.
A temporary runtime-only switch to `Deny` and `Audit` rejected all nine invalid
fixtures and was restored. That result is a `TEMPORARY RUNTIME OBSERVATION`,
not the released enforcement state.

## Admission ownership

The platform-owned `golden-path-dev-admission` AppProject permits only these
cluster-scoped kinds:

- `admissionregistration.k8s.io/ValidatingAdmissionPolicy`;
- `admissionregistration.k8s.io/ValidatingAdmissionPolicyBinding`.

It has no namespaced-resource permission. The `dev-admission` Application
owns the admission path and targets the protected GitOps `v0.6.1` release.

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

## Runtime evidence and rollout state

The disposable Kubernetes `v1.36.1` exercise observed:

1. `observedGeneration == generation`, empty `status.typeChecking`, and no
   `expressionWarnings` for the corrected policy;
2. no warning for the compliant Service A Deployment;
3. expected warnings for all nine invalid fixtures under Warn/Audit;
4. healthy Argo Applications and Service A; and
5. API rejection and object absence for all nine fixtures during a temporary
   Deny/Audit switch.

The binding was restored to Warn/Audit before cleanup. A permanent Deny
transition still requires its own governed source change and release. It must
not add user, group, or controller bypass actors.

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
