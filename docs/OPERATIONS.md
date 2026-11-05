# Operations

## Build and run

Requires Gleam 1.16+, Erlang/OTP 27+, and Rebar3 3.26. Node 24 and Python 3 are only needed for development checks. Runtime needs Erlang, not Gleam, Node, npm, or Rebar3. Versions under test are recorded in the release report.

`./run.sh` starts an isolated development instance on `127.0.0.1:4000`; set `PORT=4400` when working on the production VPS. `./run_peer.sh` runs an independent development instance on 4401. There is no automatic node discovery or message replication. `sys.config` is a retained legacy file, not loaded by the new service. Do not enable distributed Erlang to add browser users.

Configuration: `PORT` (1024–65535), `SPECTRE_ORIGIN` (exact allowed public origin). Local browser origins on the configured loopback port are allowed for development. API clients without Origin are allowed but subject to the same validation/capacity/rate limits. No environment file or credentials are needed.

## Deploy

Run `./scripts/deploy.sh` from a clean committed checkout on this VPS. It builds with `gleam export erlang-shipment`, creates a root-owned release under `/opt/spectre-link/releases`, and tests it as `spectre-link` in a temporary isolated systemd service on port 4402. That port must be free. Only after HTTP/security checks pass does it update the production symlink and the app's unit/vhost/snippets. Configuration is checked before a graceful nginx reload. No Git push or Cloudflare change is performed.

The service user cannot access the developer home or `/srv`, write the checkout/release, use public outbound networking, or produce core/crash dumps. BEAM JIT still requires executable memory; MemoryDenyWriteExecute is intentionally not enabled. Resource caps and loopback-only networking add containment, not a claim of protection against every kernel/runtime exploit.

The script saves prior configuration under `/var/backups/spectre-link/<release>`, mode 0700, and restores it on deployment failure. On later releases it restores the previous release symlink as well. **Initial adoption caveat:** before this flow there was no immutable release; reverting the initial service configuration alone does not revert a modified source checkout. The original source is retained in Git at `6720890`. Rebuilding it is an emergency recovery option, with its documented security weaknesses, and requires deliberate operator review. Do not reset the working tree automatically.

Restart/deployment/rollback discards every active message, reaction and burn capability. No content backup is created. The application has no schema migrations or persistent user database.

## Rollback of a later release

1. Choose the previous known-good directory from `/opt/spectre-link/releases` and its recorded backup. Verify it belongs to this app.
2. Atomically update `/opt/spectre-link/current` using a temporary symlink and `mv -Tf`.
3. Restore the matching service/vhost files from the restricted backup if their configuration changed; run `systemctl daemon-reload` and `nginx -t`.
4. Restart only `spectre-link-canary.service`; gracefully reload nginx if its configuration was restored.
5. Check `http://127.0.0.1:4000/healthz` and `https://spectre.micutu.com/healthz`, plus public assets. Do not read public message content as a diagnostic.

Old releases are intentionally kept for rollback. Remove only individually reviewed unused release directories; never run a broad recursive deletion of `/opt` or this checkout.

## Proxy and privacy

The vhost depends on the existing centrally maintained `$from_cloudflare_origin` peer guard and CF-Connecting-IP real-IP configuration. Preserve those global files: other applications use them. The vhost overwrites X-Real-IP and X-Forwarded-For, keeps the backend on loopback, buffers request bodies and limits writes separately from reads. Do not expose port 4000 directly.

nginx's app access log includes method, path **without query string**, status, size and duration; it omits client IP, bodies, cookies and burn headers. Error logs and the Cloudflare edge may retain additional operational data. Existing host log rotation policy applies; edge settings and contractual/vendor guarantees were not changed. No tracking/analytics script is added.

## Health and incident response

`/healthz` is a minimal liveness endpoint. Use `systemctl show spectre-link-canary -p ActiveState -p NRestarts -p MemoryCurrent`, `ss -lnt`, and bounded journal inspection to check operation. Health does not verify edge policies or attest that memory is physically erased. The incident runbook and proposed alert thresholds are in SECURITY-AUDIT.md. An alert destination/on-call must be chosen by the operator; this release does not send messages to a third party.
