# Security policy

The current supported code is the latest release on the default branch. Review [the security audit](docs/SECURITY-AUDIT.md) and [operations runbook](docs/OPERATIONS.md) for scope, known limitations and incident response.

Contact the repository maintainer privately before publishing an exploitable vulnerability. Do not include real message bodies, live burn keys, credentials or identifying infrastructure logs in public issues. Use an isolated local instance and a dedicated test room for reproduction. Production denial-of-service tests are not needed to demonstrate a validation bug.

All rooms are public; there is no E2EE or physical-erasure guarantee. Rate limits and per-page reaction tokens are abuse controls, not authentication. Dependency advisories and negative scans do not prove the absence of vulnerabilities. Changes to authentication, uploads, persistence, multi-node distribution or external data processors need a new threat-model review.
