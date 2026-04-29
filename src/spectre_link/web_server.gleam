import gleam/bit_array
import gleam/bytes_tree
import gleam/dynamic.{type Dynamic}
import gleam/erlang/atom
import gleam/erlang/process
import gleam/http.{Get, Post}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import mist.{type Connection, type ResponseData}
import spectre_link/json_utils as j
import spectre_link/mesh_discovery
import spectre_link/message_actor.{type MessageInfo}
import spectre_link/node_registry.{type RegistryMsg}

pub fn start(
  port: Int,
  registry: process.Subject(RegistryMsg),
) -> Result(Nil, String) {
  let handler = fn(req: Request(Connection)) -> Response(ResponseData) {
    handle_request(req, registry)
  }

  handler
  |> mist.new()
  |> mist.port(port)
  |> mist.start()
  |> result.map(fn(_) { Nil })
  |> result.map_error(fn(e) { string.inspect(e) })
}

fn handle_request(
  req: Request(Connection),
  registry: process.Subject(RegistryMsg),
) -> Response(ResponseData) {
  let path = request.path_segments(req)
  case req.method, path {
    Get, [] -> serve_dashboard()
    Get, ["static", "dashboard.js"] -> serve_dashboard_js()
    Get, ["api", "messages"] -> list_messages(registry)
    Post, ["api", "messages"] -> create_message(req, registry)
    Get, ["api", "nodes"] -> list_nodes()
    _, _ -> not_found()
  }
}

fn json_resp(status: Int, body: String) -> Response(ResponseData) {
  response.new(status)
  |> response.set_header("content-type", "application/json")
  |> response.set_header("cache-control", "no-store")
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
  |> response.set_header("cache-control", "max-age=3600")
  |> response.set_body(mist.Bytes(bytes_tree.from_string(body)))
}

fn serve_dashboard_js() -> Response(ResponseData) {
  js_resp(dashboard_js())
}

fn not_found() -> Response(ResponseData) {
  json_resp(404, j.obj([#("error", j.str("not found"))]))
}

fn bad_request(msg: String) -> Response(ResponseData) {
  json_resp(400, j.obj([#("error", j.str(msg))]))
}

fn serve_dashboard() -> Response(ResponseData) {
  html_resp(dashboard_html())
}

fn list_messages(registry: process.Subject(RegistryMsg)) -> Response(ResponseData) {
  let messages =
    process.call(registry, waiting: 5000, sending: fn(reply) {
      node_registry.ListMessages(reply_to: reply)
    })
  let body = j.arr(list.map(messages, message_to_json))
  json_resp(200, body)
}

fn create_message(
  req: Request(Connection),
  registry: process.Subject(RegistryMsg),
) -> Response(ResponseData) {
  case mist.read_body(req, 10_240) {
    Error(_) -> bad_request("failed to read body")
    Ok(req_with_body) -> {
      case bit_array.to_string(req_with_body.body) {
        Error(Nil) -> bad_request("invalid utf-8")
        Ok(body_str) -> {
          case parse_message_json(<<body_str:utf8>>) {
            Error(_) -> bad_request("invalid json — expected {\"content\":\"...\",\"ttl\":N}")
            Ok(#(content, ttl)) -> {
              case string.length(content) > 500 {
                True -> bad_request("content too long (max 500 chars)")
                False -> {
                  let id = generate_id()
                  let node_str = atom.to_string(mesh_discovery.node_name())
                  let reply =
                    process.call(registry, waiting: 5000, sending: fn(reply) {
                      node_registry.AddMessage(
                        id: id,
                        content: content,
                        from_node: node_str,
                        ttl_ms: ttl,
                        reply_to: reply,
                      )
                    })
                  case reply {
                    Ok(msg_id) ->
                      json_resp(
                        201,
                        j.obj([
                          #("id", j.str(msg_id)),
                          #("status", j.str("created")),
                        ]),
                      )
                    Error(e) -> bad_request(e)
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

fn list_nodes() -> Response(ResponseData) {
  let connected = mesh_discovery.connected_nodes()
  let self_str = atom.to_string(mesh_discovery.node_name())
  let all =
    [self_str, ..list.map(connected, atom.to_string)]
    |> list.map(j.str)
  json_resp(200, j.arr(all))
}

fn message_to_json(info: MessageInfo) -> String {
  j.obj([
    #("id", j.str(info.id)),
    #("content", j.str(info.content)),
    #("from_node", j.str(info.from_node)),
    #("ttl_ms", j.num(info.ttl_ms)),
    #("created_at", j.num(info.created_at)),
  ])
}

@external(erlang, "spectre_link_ffi", "parse_message_json")
fn parse_message_json(json: BitArray) -> Result(#(String, Int), Dynamic)

@external(erlang, "spectre_link_ffi", "now_ms")
fn now_ms() -> Int

fn generate_id() -> String {
  "msg_" <> int.to_string(now_ms()) <> "_" <> int.to_string(int.random(999_999))
}

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
