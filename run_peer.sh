#!/usr/bin/env bash
set -euo pipefail
# Independent local development instance. Registries are not replicated.
export PORT="${PORT:-4401}"
exec "$(dirname -- "${BASH_SOURCE[0]}")/run.sh"
