#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
export ERL_FLAGS="${ERL_FLAGS:-+S 2:2 +SDcpu 1 +SDio 1 +A 2}"
exec gleam run
