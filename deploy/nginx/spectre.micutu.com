server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name spectre.micutu.com;
    include snippets/block-dotfiles.conf;
    # Uses the existing centrally maintained Cloudflare peer allowlist.
    if ($from_cloudflare_origin = 0) { return 403; }
    include snippets/spectre-security.conf;
    access_log /var/log/nginx/spectre.access.log spectre_minimal;
    error_log /var/log/nginx/spectre.error.log warn;
    client_max_body_size 8k;
    client_body_timeout 10s;
    client_header_timeout 10s;
    send_timeout 10s;
    keepalive_timeout 20s;
    limit_conn spectre_conn_v2 32;
    limit_conn_status 429;
    if ($request_method !~ ^(GET|POST|HEAD|DELETE)$) { return 405; }
    error_page 429 = @spectre_rate_limited;
    location @spectre_rate_limited {
        include snippets/spectre-security.conf;
        add_header Retry-After "30" always;
        add_header Cache-Control "no-store" always;
        default_type application/json;
        return 429 '{"error":"Too many requests. Try again shortly."}';
    }
    location /api/ {
        limit_req zone=spectre_write_v2 burst=10 nodelay;
        limit_req zone=spectre_read_v2 burst=30 nodelay;
        limit_req_status 429;
        include snippets/spectre-proxy.conf;
    }
    location / {
        limit_req zone=spectre_read_v2 burst=40 nodelay;
        limit_req_status 429;
        include snippets/spectre-proxy.conf;
    }
    ssl_certificate /etc/letsencrypt/live/spectre.micutu.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/spectre.micutu.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_cache shared:spectre_tls:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
}
server {
    listen 80;
    listen [::]:80;
    server_name spectre.micutu.com;
    return 301 https://spectre.micutu.com$request_uri;
}
