# Security audit and threat model

Date: 2026-11-05. Assessment: source review, dependency-source inspection, bounded local checks, read-only examination of the application's service/vhost, and public response headers. This is not an independent penetration test or a host-wide compromise investigation. No user message bodies were read for the audit.

## Findings at baseline

| ID | Severity | Evidence / impact | Planned remediation |
| --- | --- | --- | --- |
| S01 | High | `parse_message_json/1` uses regex rather than JSON parsing and returns character lists where Gleam expects UTF-8 binaries. Unicode, escaping, malformed documents and runtime behavior are unreliable. | Typed `gleam_json` decoding and encoding; strict schema validation. |
| S02 | High | `node_registry` stores complete message content in its dictionary and removes expired entries only on `ListMessages`. Actors exiting do not erase the registry copy. | Independent expiration and periodic cleanup, deadline checks on reads/writes. |
| S03 | High | Public service runs as the developer user, with access to the home directory and a writable checkout/cache. Erlang distribution starts automatically under that identity. A code execution bug could expose unrelated credentials. | Dedicated system identity, read-only release, inaccessible home, distribution disabled by default. |
| S04 | Medium | `location = /api/messages` applies the 10/minute POST zone to GET too; dashboard polls twice/2s. Normal use hits 429s and errors are swallowed. | Separate write budget from read budget; explicit client error/backoff. |
| S05 | Medium | Application responses have no CSP/security headers; they depend on one proxy route. | Application-level security headers and matching nginx policy. |
| S06 | Medium | No origin/content-type checks, no application-level abuse budget, weak timestamp/random IDs. | Same-origin write policy, JSON-only requests, bounded per-client/global budgets, cryptographic IDs. |
| S07 | Medium | Body-size handling relies on Content-Length and Mist 6.0.3 `read_body`; unsupported framing is not explicitly rejected. | Require bounded Content-Length for mutations, reject transfer encoding, verify actual bytes. nginx buffers public requests. |
| S08 | Medium | No tests/CI or repeatable deployment; startup invokes `gleam run`, and launch scripts target a different directory. | Tests, built releases, portable scripts, checked-in scoped configuration. |
| S09 | Low | IDs/internal BEAM node names and operational architecture exposed through public API. | Public node aliases and minimal aggregate status. |
| S10 | Product/privacy | README claims “no trace” and distributed messaging; neither physical erasure nor replication is implemented. Browser screenshots, swap, crash dumps and proxy logs remain possible. | Accurate public privacy model; no false E2EE or replication claims. |

EPMD (4369), distribution (9100), and HTTP (4000) were bound to 127.0.0.1 at inspection, not publicly exposed. Existing global SSH/firewall/TLS settings are not changed on behalf of this project.

## STRIDE and blast radius

Top risks: denial of service through anonymous write/resource abuse (high likelihood, medium impact); information disclosure through retained content or public-room misunderstandings (medium likelihood, high impact); privilege escalation/lateral movement from a compromised application sharing the developer identity (medium likelihood, high impact).

All rooms in this release are public. Anyone knowing a room name can read it. This service is unsuitable for secrets. No user count, revenue or incident cost data is available; financial loss/ALE and number of affected users cannot responsibly be quantified. Worst case before isolation: application memory, the developer user's accessible files/credentials, and potentially other applications accessible through those credentials. After isolation, the intended boundary is this service's active in-memory content and runtime.

Trust boundaries: browser → Cloudflare → nginx → loopback Mist → registry/actors. Client headers are untrusted except where nginx overwrites them. No external analytics library or new data processor is added. Existing Cloudflare traffic processing and nginx/journal retention remain operator concerns; no DPA/compliance status is inferred.

Erlang documentation cautions that distribution cookies do not provide a cryptographically secure transport; any future multi-host deployment must use authenticated TLS and explicit network restrictions: https://www.erlang.org/docs/29/system/distributed.html and https://www.erlang.org/doc/apps/ssl/ssl_distribution.html .

## Detection and response

Current external alerting/on-call ownership and MTTD are unknown. No claim of automated incident alerting is made. Suggested operator alerts: public health endpoint failing for 2 minutes; service restart count increasing; sustained 429/5xx bursts; memory pressure approaching the service limit. Monitor counts/status only, not bodies or burn keys. Initial target MTTD: 5 minutes once an operator connects these checks to an alert destination.

Incident runbook:

1. Confirm service health and recent restart/error counts without exporting user content. Check only this vhost/service initially.
2. For suspected application compromise, stop `spectre-link-canary`, keep the rest of the VPS running, and preserve restricted infrastructure logs/configuration as appropriate. Stopping drops all messages.
3. Revoke any credentials the service could access, including the developer account's credentials if the old shared-user service was compromised. Do not copy secrets into issues or commit messages.
4. Build a reviewed release from a known commit, apply the root-owned service template, validate nginx, and restore only this application.
5. Check public health, normal read/write behavior in a dedicated temporary room, service identity and loopback binding. Investigate lateral access before declaring containment.
6. Record impact, timeline, affected data and notification decisions with the operator. Applicable legal duties require a separate assessment; none is certified by this audit.

Tabletop: not independently exercised with the operator; local smoke/regression checks are not an incident-response tabletop. A deployment/rollback rehearsal will be documented when completed.

## Verdict

Baseline: **mitigate before promotion**. Anonymous public content, upstream edge behavior, physical memory erasure and absence of external alerting remain explicit residual risks even after code fixes. Track final verification and limitations in the release report rather than claiming the site is vulnerability-free.
