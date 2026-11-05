#!/usr/bin/env bash
# Scoped deployment to this VPS. No push, DNS change, or other service restart.
set -euo pipefail
umask 077
spectre_project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$spectre_project_dir"
if [[ -n "$(git status --porcelain)" ]]; then
  printf 'Commit or preserve pending changes before deployment.\n' >&2
  exit 1
fi
for spectre_tool in gleam rebar3 curl python3 sudo; do command -v "$spectre_tool" >/dev/null; done
sudo -n true
export ERL_FLAGS="${ERL_FLAGS:-+S 2:2 +SDcpu 1 +SDio 1 +A 2}"
gleam format --check src test
gleam test
gleam export erlang-shipment
spectre_revision="$(git rev-parse --short=12 HEAD)"
spectre_release_id="${spectre_revision}-$(date -u +%Y%m%dT%H%M%SZ)"
spectre_release_dir="/opt/spectre-link/releases/$spectre_release_id"
spectre_backup_dir="/var/backups/spectre-link/$spectre_release_id"
spectre_previous="$(sudo -n readlink /opt/spectre-link/current 2>/dev/null || true)"
spectre_preview_file="$(mktemp)"
spectre_config_changed=0
spectre_link_changed=0
spectre_files=(
  /etc/systemd/system/spectre-link-canary.service
  /etc/nginx/sites-enabled/spectre.micutu.com
  /etc/nginx/conf.d/spectre-rate-limit.conf
  /etc/nginx/snippets/spectre-security.conf
  /etc/nginx/snippets/spectre-proxy.conf
)
cleanup_preview() {
  sudo -n systemctl stop spectre-link-preview.service >/dev/null 2>&1 || true
  sudo -n rm -f /run/systemd/system/spectre-link-preview.service
  sudo -n systemctl daemon-reload
  rm -f -- "$spectre_preview_file"
}
rollback_on_error() {
  local spectre_status=$?
  trap - EXIT
  cleanup_preview
  if (( spectre_status != 0 && spectre_config_changed )); then
    printf 'Deployment failed; restoring the previous service/proxy configuration.\n' >&2
    for spectre_file in "${spectre_files[@]}"; do
      if sudo -n test -f "$spectre_backup_dir$spectre_file"; then
        sudo -n cp -a -- "$spectre_backup_dir$spectre_file" "$spectre_file"
      else
        sudo -n rm -f -- "$spectre_file"
      fi
    done
    if (( spectre_link_changed )); then
      if [[ -n "$spectre_previous" ]]; then
        sudo -n ln -s -- "$spectre_previous" /opt/spectre-link/.rollback
        sudo -n mv -Tf /opt/spectre-link/.rollback /opt/spectre-link/current
      else
        sudo -n rm -f /opt/spectre-link/current
      fi
    fi
    sudo -n systemctl daemon-reload
    sudo -n nginx -t && sudo -n systemctl reload nginx
    sudo -n systemctl restart spectre-link-canary.service
  fi
  exit "$spectre_status"
}
trap rollback_on_error EXIT
if ! getent passwd spectre-link >/dev/null; then
  sudo -n useradd --system --user-group --home-dir /nonexistent --no-create-home --shell /usr/sbin/nologin spectre-link
fi
sudo -n install -d -m 0755 /opt/spectre-link /opt/spectre-link/releases "$spectre_release_dir"
sudo -n cp -a build/erlang-shipment/. "$spectre_release_dir/"
sudo -n chown -R root:root "$spectre_release_dir"
sudo -n chmod -R u=rwX,go=rX "$spectre_release_dir"
sudo -n chmod 0755 "$spectre_release_dir/entrypoint.sh"
# Validate the exact built release under the same isolation before switching.
sed -e "s|/opt/spectre-link/current|$spectre_release_dir|g" \
    -e 's/PORT=4000/PORT=4402/' \
    -e 's|/run/spectre-link|/run/spectre-link-preview|' \
    -e 's/RuntimeDirectory=spectre-link$/RuntimeDirectory=spectre-link-preview/' \
    deploy/spectre-link-canary.service > "$spectre_preview_file"
sudo -n install -m 0644 "$spectre_preview_file" /run/systemd/system/spectre-link-preview.service
sudo -n systemctl daemon-reload
sudo -n systemd-analyze verify /run/systemd/system/spectre-link-preview.service
sudo -n systemctl start spectre-link-preview.service
spectre_ready=0
for _ in {1..20}; do
  if curl -fsS --max-time 2 http://127.0.0.1:4402/healthz >/dev/null 2>&1; then spectre_ready=1; break; fi
  sleep 0.5
done
if (( ! spectre_ready )); then printf 'Isolated release did not become healthy.\n' >&2; exit 1; fi
BASE_URL=http://127.0.0.1:4402 python3 scripts/http_smoke.py
curl -fsS --max-time 5 http://127.0.0.1:4402/ >/dev/null
cleanup_preview
sudo -n install -d -m 0700 "$spectre_backup_dir"
for spectre_file in "${spectre_files[@]}"; do
  if sudo -n test -f "$spectre_file"; then sudo -n cp --parents -aL -- "$spectre_file" "$spectre_backup_dir"; fi
done
spectre_config_changed=1
sudo -n install -m 0644 deploy/spectre-link-canary.service /etc/systemd/system/spectre-link-canary.service
sudo -n install -m 0644 deploy/nginx/spectre-rate-limit.conf /etc/nginx/conf.d/spectre-rate-limit.conf
sudo -n install -m 0644 deploy/nginx/spectre-security.conf /etc/nginx/snippets/spectre-security.conf
sudo -n install -m 0644 deploy/nginx/spectre-proxy.conf /etc/nginx/snippets/spectre-proxy.conf
sudo -n install -m 0644 deploy/nginx/spectre.micutu.com /etc/nginx/sites-enabled/spectre.micutu.com
sudo -n nginx -t
sudo -n ln -s -- "$spectre_release_dir" /opt/spectre-link/.next
sudo -n mv -Tf /opt/spectre-link/.next /opt/spectre-link/current
spectre_link_changed=1
sudo -n systemctl daemon-reload
sudo -n systemd-analyze verify /etc/systemd/system/spectre-link-canary.service
sudo -n systemctl restart spectre-link-canary.service
spectre_ready=0
for _ in {1..20}; do
  if curl -fsS --max-time 2 http://127.0.0.1:4000/healthz >/dev/null 2>&1; then spectre_ready=1; break; fi
  sleep 0.5
done
if (( ! spectre_ready )); then printf 'Production release did not become healthy.\n' >&2; exit 1; fi
sudo -n systemctl reload nginx
curl -fsS --max-time 20 https://spectre.micutu.com/healthz >/dev/null
printf 'Deployed release: %s\nConfiguration backup: %s\nPrevious release: %s\n' "$spectre_release_dir" "$spectre_backup_dir" "${spectre_previous:-initial adoption; previous unit saved in backup}"
spectre_config_changed=0
