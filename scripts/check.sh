#!/usr/bin/env bash
# Run the same release checks locally and in CI, without touching production.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
export ERL_FLAGS="${ERL_FLAGS:-+S 2:2 +SDcpu 1 +SDio 1 +A 2}"
python3 scripts/require_free_port.py 4400
gleam format --check src test
shellcheck run.sh run_peer.sh scripts/*.sh
npm run check:js
npm audit --audit-level=high
gleam test
gleam export erlang-shipment
PORT=4400 build/erlang-shipment/entrypoint.sh run > /tmp/spectre-check.log 2>&1 &
spectre_check_pid=$!
trap 'kill "$spectre_check_pid" 2>/dev/null || true; wait "$spectre_check_pid" 2>/dev/null || true' EXIT
spectre_check_ready=0
for _ in {1..30}; do
  if ! kill -0 "$spectre_check_pid" 2>/dev/null; then cat /tmp/spectre-check.log; exit 1; fi
  if curl -fsS --max-time 2 http://127.0.0.1:4400/healthz >/dev/null 2>&1; then spectre_check_ready=1; break; fi
  sleep 0.5
done
if (( ! spectre_check_ready )); then cat /tmp/spectre-check.log; exit 1; fi
BASE_URL=http://127.0.0.1:4400 python3 scripts/http_smoke.py
BASE_URL=http://127.0.0.1:4400 npm run test:browser
