import gleam/bit_array
import gleam/bytes_tree
import gleam/dict
import gleam/erlang/process
import gleam/http.{Delete, Get, Head, Post}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import mist.{type Connection, type ResponseData}
import spectre_link/config
import spectre_link/json_utils as j
import spectre_link/message_actor.{type MessageInfo}
import spectre_link/node_registry.{type RegistryMsg}
import spectre_link/rate_limit
import spectre_link/validation

pub fn start(
  port: Int,
  registry: process.Subject(RegistryMsg),
  limiter: process.Subject(rate_limit.Msg),
) -> Result(Nil, String) {
  let handler = fn(req: Request(Connection)) -> Response(ResponseData) {
    handle_request(req, registry, limiter)
    |> security_headers()
    |> fn(res) {
      case req.method {
        Head -> response.set_body(res, mist.Bytes(bytes_tree.new()))
        _ -> res
      }
    }
  }
  handler
  |> mist.new()
  |> mist.port(port)
  |> mist.bind("127.0.0.1")
  |> mist.start()
  |> result.map(fn(_) { Nil })
  |> result.map_error(string.inspect)
}

fn handle_request(
  req: Request(Connection),
  registry: process.Subject(RegistryMsg),
  limiter: process.Subject(rate_limit.Msg),
) -> Response(ResponseData) {
  let path = request.path_segments(req)
  case req.method, path {
    Get, [] | Head, [] -> html_resp(dashboard_html())
    Get, ["static", "dashboard.js"] | Head, ["static", "dashboard.js"] ->
      js_resp(dashboard_js())
    Get, ["healthz"] | Head, ["healthz"] ->
      json_resp(200, "{\"status\":\"ok\"}")
    _, ["api", ..] -> {
      let bucket = case req.method {
        Get | Head -> rate_limit.Read
        _ -> rate_limit.Write
      }
      // Only the loopback reverse proxy may supply X-Real-IP. The checked-in
      // nginx configuration overwrites the incoming value.
      let client =
        request.get_header(req, "x-real-ip")
        |> result.unwrap("loopback")
        |> hash()
      let wait =
        process.call(limiter, 1000, fn(reply) {
          rate_limit.Check(client, bucket, reply)
        })
      case wait {
        0 ->
          case bucket == rate_limit.Write && !allowed_write(req) {
            True -> error_response(403, "Cross-origin writes are not allowed.")
            False -> route_api(req, path, registry)
          }
        _ ->
          error_response(429, "Too many requests. Try again shortly.")
          |> response.set_header("retry-after", int.to_string(wait))
      }
    }
    _, _ -> error_response(404, "Not found.")
  }
}

fn route_api(
  req: Request(Connection),
  path: List(String),
  registry: process.Subject(RegistryMsg),
) -> Response(ResponseData) {
  let room =
    request.get_query(req)
    |> result.unwrap([])
    |> list.key_find("room")
    |> result.unwrap("lobby")
  case validation.validate_room(room) {
    Error(error) -> error_response(400, error)
    Ok(room) ->
      case req.method, path {
        Get, ["api", "messages"] | Head, ["api", "messages"] -> {
          let messages = get_messages(registry, room)
          json_resp(200, j.arr(list.map(messages, message_to_json)))
        }
        Get, ["api", "stats"] | Head, ["api", "stats"] -> {
          let messages = get_messages(registry, room)
          json_resp(
            200,
            j.obj([
              #("room", j.str(room)),
              #("active", j.num(list.length(messages))),
              #("room_limit", "100"),
              #("max_ttl_ms", "300000"),
            ]),
          )
        }
        Post, ["api", "messages"] ->
          with_body(req, fn(body) { create_message(body, registry) })
        Delete, ["api", "messages", id] -> {
          let key = request.get_header(req, "x-burn-key") |> result.unwrap("")
          case validation.valid_token(key) {
            False ->
              error_response(404, "Message or burn capability not found.")
            True -> {
              let burned =
                process.call(registry, 1000, fn(reply) {
                  node_registry.BurnMessage(id, room, hash(key), reply)
                })
              case burned {
                True -> json_resp(200, "{\"status\":\"burned\"}")
                False ->
                  error_response(404, "Message or burn capability not found.")
              }
            }
          }
        }
        Post, ["api", "messages", id, "reactions"] -> {
          let client =
            request.get_header(req, "x-spectre-client") |> result.unwrap("")
          case validation.valid_token(client) {
            False ->
              error_response(400, "A valid X-Spectre-Client token is required.")
            True ->
              with_body(req, fn(body) {
                case validation.parse_reaction(body) {
                  Error(error) -> error_response(400, error)
                  Ok(emoji) -> {
                    let reply =
                      process.call(registry, 1000, fn(reply) {
                        node_registry.React(
                          id,
                          room,
                          hash(client),
                          emoji,
                          reply,
                        )
                      })
                    case reply {
                      Ok(info) -> json_resp(200, message_to_json(info))
                      Error(error) -> error_response(404, error)
                    }
                  }
                }
              })
          }
        }
        Get, ["api", "nodes"] | Head, ["api", "nodes"] ->
          json_resp(200, "[\"local\"]")
        _, ["api", "messages"]
        | _, ["api", "messages", _]
        | _, ["api", "messages", _, "reactions"]
        | _, ["api", "stats"]
        | _, ["api", "nodes"]
        ->
          error_response(405, "Method not allowed.")
          |> response.set_header("allow", "GET, HEAD, POST, DELETE")
        _, _ -> error_response(404, "Not found.")
      }
  }
}

fn security_headers(res: Response(ResponseData)) -> Response(ResponseData) {
  res
  |> response.set_header("x-content-type-options", "nosniff")
  |> response.set_header("x-frame-options", "DENY")
  |> response.set_header("referrer-policy", "no-referrer")
  |> response.set_header(
    "permissions-policy",
    "camera=(), microphone=(), geolocation=()",
  )
  |> response.set_header(
    "content-security-policy",
    "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'",
  )
}

fn allowed_write(req: Request(Connection)) -> Bool {
  let site = request.get_header(req, "sec-fetch-site") |> result.unwrap("")
  let origin = request.get_header(req, "origin") |> result.unwrap("")
  site != "cross-site"
  && {
    origin == ""
    || origin == config.origin()
    || origin == "http://127.0.0.1:" <> int.to_string(config.port())
    || origin == "http://localhost:" <> int.to_string(config.port())
  }
}

fn json_resp(status: Int, body: String) -> Response(ResponseData) {
  response.new(status)
  |> response.set_header("content-type", "application/json; charset=utf-8")
  |> response.set_header("cache-control", "no-store")
  |> response.set_header("x-robots-tag", "noindex, nofollow")
  |> response.set_header("x-server-time", int.to_string(now_ms()))
  |> response.set_body(mist.Bytes(bytes_tree.from_string(body)))
}

fn html_resp(body: String) -> Response(ResponseData) {
  response.new(200)
  |> response.set_header("content-type", "text/html; charset=utf-8")
  |> response.set_header("cache-control", "no-store")
  |> response.set_body(mist.Bytes(bytes_tree.from_string(body)))
}

fn js_resp(body: String) -> Response(ResponseData) {
  response.new(200)
  |> response.set_header("content-type", "text/javascript; charset=utf-8")
  |> response.set_header("cache-control", "no-cache")
  |> response.set_body(mist.Bytes(bytes_tree.from_string(body)))
}

fn error_response(status: Int, error: String) -> Response(ResponseData) {
  json_resp(status, j.obj([#("error", j.str(error))]))
}

fn get_messages(
  registry: process.Subject(RegistryMsg),
  room: String,
) -> List(MessageInfo) {
  process.call(registry, 1000, fn(reply) {
    node_registry.ListMessages(room, reply)
  })
}

fn with_body(
  req: Request(Connection),
  next: fn(String) -> Response(ResponseData),
) -> Response(ResponseData) {
  let content_type =
    request.get_header(req, "content-type")
    |> result.unwrap("")
    |> string.split(";")
    |> list.first()
    |> result.unwrap("")
    |> string.trim()
    |> string.lowercase()
  let size =
    request.get_header(req, "content-length")
    |> result.try(int.parse)
    |> result.unwrap(-1)
  case content_type, request.get_header(req, "transfer-encoding"), size {
    _, Ok(_), _ -> error_response(400, "Transfer encoding is not supported.")
    _, _, n if n < 0 -> error_response(411, "Content-Length required.")
    _, _, n if n > 8192 ->
      error_response(413, "Request body exceeds 8192 bytes.")
    t, _, _ if t != "application/json" ->
      error_response(415, "Use application/json.")
    _, _, _ ->
      case mist.read_body(req, 8192) {
        Error(_) -> error_response(400, "Unable to read request body.")
        Ok(body_req) ->
          case bit_array.byte_size(body_req.body) == size {
            False -> error_response(400, "Request length mismatch.")
            True ->
              case bit_array.to_string(body_req.body) {
                Error(_) -> error_response(400, "Invalid UTF-8.")
                Ok(body) -> next(body)
              }
          }
      }
  }
}

fn create_message(
  body: String,
  registry: process.Subject(RegistryMsg),
) -> Response(ResponseData) {
  case validation.parse_message(body) {
    Error(error) -> error_response(400, error)
    Ok(message) -> {
      let id = random_id()
      let key = random_id()
      let reply =
        process.call(registry, 1000, fn(reply) {
          node_registry.AddMessage(
            id:,
            content: message.content,
            room: message.room,
            kind: message.kind,
            ttl_ms: message.ttl,
            burn_hash: hash(key),
            reply_to: reply,
          )
        })
      case reply {
        Ok(info) ->
          json_resp(
            201,
            j.obj([
              #("id", j.str(id)),
              #("burn_key", j.str(key)),
              #("message", message_to_json(info)),
            ]),
          )
        Error(error) ->
          error_response(503, error) |> response.set_header("retry-after", "5")
      }
    }
  }
}

fn message_to_json(info: MessageInfo) -> String {
  j.obj([
    #("id", j.str(info.id)),
    #("content", j.str(info.content)),
    #("room", j.str(info.room)),
    #("kind", j.str(info.kind)),
    #("ttl_ms", j.num(info.ttl_ms)),
    #("created_at", j.num(info.created_at)),
    #("expires_at", j.num(info.created_at + info.ttl_ms)),
    #(
      "reactions",
      j.obj(
        list.map(["spark", "heart", "curious"], fn(key) {
          #(key, j.num(dict.get(info.reactions, key) |> result.unwrap(0)))
        }),
      ),
    ),
  ])
}

@external(erlang, "spectre_link_ffi", "hash")
fn hash(value: String) -> String

@external(erlang, "spectre_link_ffi", "random_id")
fn random_id() -> String

@external(erlang, "spectre_link_ffi", "now_ms")
fn now_ms() -> Int

fn dashboard_html() -> String {
  "<!DOCTYPE html>
<html lang=\"en\">
<head>
<meta charset=\"UTF-8\">
<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0, viewport-fit=cover\">
<title>Spectre-Link</title>
<style>
:root {
  --sw: 260px;
  --accent: #8080ff;
  --bg: #0a0a1a;
  --border: #2a2a6a;
}
* { margin: 0; padding: 0; box-sizing: border-box; }
html, body { height: 100%; }
body {
  background: var(--bg);
  color: #e0e0ff;
  font-family: 'Courier New', monospace;
  overflow: hidden;
  height: 100dvh;
}
#canvas {
  position: fixed; top: 0; left: 0;
  width: 100%; height: 100%;
  z-index: 0;
  touch-action: none;
}
/* Toggle button — hidden on desktop */
#toggle-btn {
  display: none;
  position: fixed; top: 12px; left: 12px;
  z-index: 200;
  background: rgba(10,10,30,0.92);
  border: 1px solid var(--border);
  border-radius: 8px;
  color: #e0e0ff;
  padding: 8px 12px;
  font-size: 1rem;
  cursor: pointer;
  align-items: center;
  gap: 6px;
  min-height: 44px;
}
#msg-badge {
  background: var(--accent);
  border-radius: 10px;
  padding: 1px 7px;
  font-size: 0.72em;
  min-width: 20px;
  text-align: center;
}
/* Backdrop */
#backdrop {
  display: none;
  position: fixed; inset: 0;
  background: rgba(0,0,0,0.55);
  z-index: 150;
  touch-action: none;
}
#backdrop.show { display: block; }
/* Sidebar */
#sidebar {
  position: fixed; top: 0; left: 0;
  width: var(--sw); height: 100%;
  background: rgba(10,10,30,0.92);
  border-right: 1px solid var(--border);
  padding: 20px;
  z-index: 100;
  overflow-y: auto;
  overscroll-behavior: contain;
}
#sidebar-hdr {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 16px;
}
#close-btn {
  display: none;
  background: none; border: none;
  color: #6060cc; cursor: pointer;
  font-size: 1.2rem;
  padding: 4px 8px;
  min-height: 44px; min-width: 44px;
  border-radius: 4px;
}
h1 { color: var(--accent); font-size: 1.3em; text-shadow: 0 0 10px #4040ff; }
h2 { color: #6060cc; font-size: 1em; margin-bottom: 10px; }
.node-item {
  background: rgba(40,40,100,0.5);
  border: 1px solid #3030a0;
  padding: 8px 12px;
  margin-bottom: 6px;
  border-radius: 4px;
  font-size: 0.75em;
  word-break: break-all;
}
.node-self { border-color: var(--accent); color: #b0b0ff; }
#msg-count { color: var(--accent); font-size: 0.8em; margin-top: 8px; }
/* Form */
#form-area {
  position: fixed; bottom: 0;
  left: calc(var(--sw) + 20px); right: 20px;
  background: rgba(10,10,30,0.92);
  border: 1px solid #3030a0;
  border-radius: 8px 8px 0 0;
  padding: 16px 20px;
  padding-bottom: max(16px, env(safe-area-inset-bottom));
  z-index: 100;
}
.form-row { display: flex; gap: 10px; align-items: center; flex-wrap: wrap; }
.ttl-row { display: flex; align-items: center; gap: 8px; }
input[type=text] {
  flex: 1; min-width: 180px;
  background: rgba(20,20,60,0.8);
  border: 1px solid #4040a0;
  color: #e0e0ff;
  padding: 10px; border-radius: 4px;
  font-family: inherit; font-size: 0.9em;
  min-height: 44px;
}
input[type=text]::placeholder { color: #5050a0; }
input[type=range] { width: 140px; accent-color: var(--accent); }
.ttl-label { color: #8080cc; font-size: 0.8em; white-space: nowrap; }
button {
  background: linear-gradient(135deg, #4040c0, #8040ff);
  border: none; color: #fff;
  padding: 10px 20px; border-radius: 4px;
  cursor: pointer; font-family: inherit; font-size: 0.9em;
  min-height: 44px;
  transition: opacity 0.2s;
}
button:hover, button:active { opacity: 0.85; }
#status { font-size: 0.75em; color: #6060cc; margin-top: 6px; min-height: 1em; }

/* ─── Mobile (≤768px) ─── */
@media (max-width: 768px) {
  #toggle-btn { display: flex; }
  #close-btn { display: block; }
  #sidebar {
    top: auto; bottom: 0;
    left: 0; right: 0;
    width: 100%; height: auto;
    max-height: 60dvh;
    border-right: none;
    border-top: 1px solid var(--border);
    border-radius: 16px 16px 0 0;
    transform: translateY(105%);
    transition: transform 0.3s cubic-bezier(0.4,0,0.2,1);
    padding-bottom: max(20px, env(safe-area-inset-bottom));
    z-index: 160;
  }
  #sidebar.open { transform: translateY(0); }
  #form-area {
    left: 0; right: 0;
    border-radius: 0;
    padding: 12px 16px;
    padding-bottom: max(12px, env(safe-area-inset-bottom));
    border-left: none; border-right: none; border-bottom: none;
  }
  .form-row { flex-direction: column; gap: 8px; }
  input[type=text] { width: 100%; min-width: unset; }
  .ttl-row { width: 100%; justify-content: space-between; }
  input[type=range] { flex: 1; max-width: 200px; }
  button { width: 100%; padding: 12px; }
}
</style>
</head>
<body>
<canvas id=\"canvas\"></canvas>
<button id=\"toggle-btn\" aria-label=\"Toggle nodes panel\" aria-expanded=\"false\">
  👻 <span id=\"msg-badge\">0</span>
</button>
<div id=\"backdrop\"></div>
<aside id=\"sidebar\">
  <div id=\"sidebar-hdr\">
    <h1>👻 Spectre-Link</h1>
    <button id=\"close-btn\" aria-label=\"Close nodes panel\">✕</button>
  </div>
  <h2>Connected Nodes</h2>
  <div id=\"nodes-list\"><div class=\"node-item\">Loading...</div></div>
  <div id=\"msg-count\"></div>
</aside>
<div id=\"form-area\">
  <div class=\"form-row\">
    <input type=\"text\" id=\"content-input\" placeholder=\"Enter ephemeral message...\" maxlength=\"500\" autocomplete=\"off\">
    <div class=\"ttl-row\">
      <span class=\"ttl-label\">TTL: <span id=\"ttl-display\">30s</span></span>
      <input type=\"range\" id=\"ttl-input\" min=\"3000\" max=\"300000\" step=\"1000\" value=\"30000\">
    </div>
    <button type=\"button\" id=\"send-btn\">Send 👻</button>
  </div>
  <div id=\"status\"></div>
</div>
<script src=\"/static/dashboard.js\"></script>
</body>
</html>"
}

fn dashboard_js() -> String {
  "const canvas = document.getElementById('canvas');
const ctx = canvas.getContext('2d');
let width, height, formH = 130;

function resize() {
  width = canvas.width = window.innerWidth;
  height = canvas.height = window.innerHeight;
  const f = document.getElementById('form-area');
  if (f) formH = f.offsetHeight + 16;
}
resize();
window.addEventListener('resize', () => { resize(); });

// Sidebar toggle
const sidebar = document.getElementById('sidebar');
const backdrop = document.getElementById('backdrop');
const toggleBtn = document.getElementById('toggle-btn');
const closeBtn = document.getElementById('close-btn');

function openSidebar() {
  sidebar.classList.add('open');
  backdrop.classList.add('show');
  toggleBtn.setAttribute('aria-expanded', 'true');
}
function closeSidebar() {
  sidebar.classList.remove('open');
  backdrop.classList.remove('show');
  toggleBtn.setAttribute('aria-expanded', 'false');
}
toggleBtn.addEventListener('click', () => sidebar.classList.contains('open') ? closeSidebar() : openSidebar());
closeBtn.addEventListener('click', closeSidebar);
backdrop.addEventListener('click', closeSidebar);
document.addEventListener('keydown', e => { if (e.key === 'Escape') closeSidebar(); });

// Canvas nodes
class MsgNode {
  constructor(m) {
    this.id = m.id; this.content = m.content;
    this.ttl_ms = m.ttl_ms; this.created_at = m.created_at;
    const mobile = window.innerWidth <= 768;
    const lx = mobile ? 20 : 280;
    this.x = lx + Math.random() * (width - lx - 40);
    this.y = 20 + Math.random() * (height - formH - 40);
    this.vx = (Math.random() - 0.5) * 1.2;
    this.vy = (Math.random() - 0.5) * 1.2;
    this.r = 38 + Math.random() * 18;
    this.hue = Math.floor(Math.random() * 60) + 200;
    this.phase = Math.random() * Math.PI * 2;
  }
  frac() { return Math.max(0, 1 - (Date.now() - this.created_at) / this.ttl_ms); }
  update() {
    this.x += this.vx; this.y += this.vy; this.phase += 0.03;
    const mobile = window.innerWidth <= 768;
    const lb = mobile ? this.r + 4 : 270 + this.r;
    if (this.x - this.r < lb) { this.x = lb + this.r; this.vx = Math.abs(this.vx); }
    if (this.x + this.r > width - 8) { this.x = width - 8 - this.r; this.vx = -Math.abs(this.vx); }
    if (this.y - this.r < 8) { this.y = 8 + this.r; this.vy = Math.abs(this.vy); }
    if (this.y + this.r > height - formH) { this.y = height - formH - this.r; this.vy = -Math.abs(this.vy); }
  }
  draw() {
    const f = this.frac();
    const pulse = 0.7 + 0.3 * Math.sin(this.phase);
    ctx.save();
    ctx.globalAlpha = f * 0.9;
    const g = ctx.createRadialGradient(this.x, this.y, this.r * 0.2, this.x, this.y, this.r * 1.5);
    g.addColorStop(0, `hsla(${this.hue},80%,70%,${0.4 * pulse})`);
    g.addColorStop(1, 'transparent');
    ctx.fillStyle = g;
    ctx.beginPath(); ctx.arc(this.x, this.y, this.r * 1.5, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.arc(this.x, this.y, this.r, 0, Math.PI * 2);
    ctx.fillStyle = `hsla(${this.hue},60%,15%,0.85)`; ctx.fill();
    ctx.strokeStyle = `hsla(${this.hue},80%,60%,${0.8 * pulse})`; ctx.lineWidth = 2; ctx.stroke();
    const fs = window.innerWidth <= 768 ? 12 : 10;
    ctx.fillStyle = `hsla(${this.hue},90%,80%,1)`;
    ctx.font = `bold ${fs}px Courier New`; ctx.textAlign = 'center';
    const lbl = this.content.length > 14 ? this.content.slice(0, 14) + '\\u2026' : this.content;
    ctx.fillText(lbl, this.x, this.y - 6);
    const sl = Math.ceil(this.ttl_ms * f / 1000);
    ctx.fillStyle = f < 0.25 ? '#ff6060' : `hsla(${this.hue},70%,65%,1)`;
    ctx.font = `${fs - 1}px Courier New`;
    ctx.fillText('\\u23f1 ' + sl + 's', this.x, this.y + 10);
    ctx.restore();
  }
}

let nodes = {};
function updateNodes(msgs) {
  const ids = new Set(msgs.map(m => m.id));
  for (const id of Object.keys(nodes)) if (!ids.has(id)) delete nodes[id];
  for (const m of msgs) if (!nodes[m.id]) nodes[m.id] = new MsgNode(m);
}

(function animate() {
  requestAnimationFrame(animate);
  ctx.clearRect(0, 0, width, height);
  ctx.strokeStyle = 'rgba(40,40,120,0.12)'; ctx.lineWidth = 1;
  for (let x = 0; x < width; x += 60) { ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, height); ctx.stroke(); }
  for (let y = 0; y < height; y += 60) { ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke(); }
  for (const n of Object.values(nodes)) { n.update(); n.draw(); }
})();

async function refresh() {
  try {
    const [mr, nr] = await Promise.all([fetch('/api/messages'), fetch('/api/nodes')]);
    const msgs = await mr.json(), ns = await nr.json();
    updateNodes(msgs);
    const nl = document.getElementById('nodes-list');
    nl.innerHTML = '';
    ns.forEach((n, i) => {
      const d = document.createElement('div');
      d.className = 'node-item' + (i === 0 ? ' node-self' : '');
      d.textContent = (i === 0 ? '\\u2605 ' : '\\u25cb ') + n;
      nl.appendChild(d);
    });
    const c = msgs.length;
    document.getElementById('msg-count').textContent = c + ' active message' + (c !== 1 ? 's' : '');
    document.getElementById('msg-badge').textContent = c;
  } catch(e) {}
}
refresh();
setInterval(refresh, 2000);

document.getElementById('ttl-input').addEventListener('input', function() {
  document.getElementById('ttl-display').textContent = (parseInt(this.value) / 1000) + 's';
});

async function sendMessage() {
  const inp = document.getElementById('content-input');
  const c = inp.value.trim();
  if (!c) { setStatus('Enter a message first', true); return; }
  const ttl = parseInt(document.getElementById('ttl-input').value);
  setStatus('Sending\\u2026', false);
  try {
    const r = await fetch('/api/messages', {
      method: 'POST', headers: {'content-type': 'application/json'},
      body: JSON.stringify({content: c, ttl})
    });
    const d = await r.json();
    if (r.ok) { setStatus('\\u2713 ' + d.id, false); inp.value = ''; refresh(); }
    else setStatus('Error: ' + (d.error || 'unknown'), true);
  } catch(e) { setStatus('Network error', true); }
}

document.getElementById('send-btn').addEventListener('click', sendMessage);
document.getElementById('content-input').addEventListener('keydown', e => { if (e.key === 'Enter') sendMessage(); });
function setStatus(m, err) {
  const el = document.getElementById('status');
  el.textContent = m;
  el.style.color = err ? '#ff6060' : '#8080ff';
}"
}
