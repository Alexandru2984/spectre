# Security policy

The current supported code is the latest release on the default branch. Review [the security audit](docs/SECURITY-AUDIT.md) and [operations runbook](docs/OPERATIONS.md) for scope, known limitations and incident response.

Contact the repository maintainer privately before publishing an exploitable vulnerability. Do not include real message bodies, live burn keys, credentials or identifying infrastructure logs in public issues. Use an isolated local instance and a dedicated test room for reproduction. Production denial-of-service tests are not needed to demonstrate a validation bug.

Built-in and named public rooms are open to everyone. Managed private events require a bearer invitation on every scoped read or mutation. Optional browser AES-GCM encryption protects message and poll text in encrypted private rooms; room metadata, aliases, traffic and anonymous interaction counts remain visible to the service. Invitation holders can copy links and content. There is no identity verification, per-person revocation, forward secrecy, key recovery or physical-erasure guarantee. Review [the feature threat model](docs/FEATURE-PLAN.md) and [the current review](docs/PRODUCT-4-PLAN.md).

Owner posting policies and per-page cooldowns are enforced by the server; anonymous tokens can still be rotated. Rate limits, presence, votes and reaction tokens are abuse controls, not proof of identity. Dependency advisories and negative scans do not prove the absence of vulnerabilities. Changes to authentication, uploads, persistence, multi-node distribution or external data processors need a new threat-model review.
