import gleam/bit_array
import gleam/bytes_tree
import gleam/dynamic/decode
import gleam/erlang/atom
import gleam/erlang/process
import gleam/http.{Get, Post}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import mist.{type Connection, type ResponseData}
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
    Get, ["api", "messages"] -> list_messages(registry)
    Post, ["api", "messages"] -> create_message(req, registry)
    Get, ["api", "nodes"] -> list_nodes()
    _, _ -> not_found()
  }
}

fn json_response(status: Int, body: String) -> Response(ResponseData) {
  response.new(status)
  |> response.set_header("content-type", "application/json")
  |> response.set_header("access-control-allow-origin", "*")
  |> response.set_body(mist.Bytes(bytes_tree.from_string(body)))
}

fn html_response(status: Int, body: String) -> Response(ResponseData) {
  response.new(status)
  |> response.set_header("content-type", "text/html; charset=utf-8")
  |> response.set_header("access-control-allow-origin", "*")
  |> response.set_body(mist.Bytes(bytes_tree.from_string(body)))
}

fn not_found() -> Response(ResponseData) {
  json_response(404, "{\"error\":\"not found\"}")
}

fn bad_request(msg: String) -> Response(ResponseData) {
  json_response(400, "{\"error\":\"" <> msg <> "\"}")
}

fn serve_dashboard() -> Response(ResponseData) {
  html_response(200, dashboard_html())
}

fn list_messages(
  registry: process.Subject(RegistryMsg),
) -> Response(ResponseData) {
  let messages =
    process.call(registry, waiting: 5000, sending: fn(reply) {
      node_registry.ListMessages(reply_to: reply)
    })
  let body =
    json.array(messages, fn(m) { message_to_json(m) })
    |> json.to_string()
  json_response(200, body)
}

fn create_message(
  req: Request(Connection),
  registry: process.Subject(RegistryMsg),
) -> Response(ResponseData) {
  case mist.read_body(req, 1_000_000) {
    Error(_) -> bad_request("failed to read body")
    Ok(req_with_body) -> {
      case bit_array.to_string(req_with_body.body) {
        Error(Nil) -> bad_request("invalid utf-8")
        Ok(body_str) -> {
          case json.decode(body_str, msg_decoder()) {
            Error(_) -> bad_request("invalid json")
            Ok(#(content, ttl)) -> {
              let id = generate_id()
              let node_str =
                atom.to_string(mesh_discovery.node_name())
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
                  json_response(
                    201,
                    "{\"id\":\"" <> msg_id <> "\",\"status\":\"created\"}",
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

fn list_nodes() -> Response(ResponseData) {
  let nodes = mesh_discovery.connected_nodes()
  let node_strs = list.map(nodes, fn(a) { json.string(atom.to_string(a)) })
  let self_str = atom.to_string(mesh_discovery.node_name())
  let all = list.prepend(node_strs, json.string(self_str))
  let body = json.preprocessed_array(all) |> json.to_string()
  json_response(200, body)
}

fn message_to_json(info: MessageInfo) -> json.Json {
  json.object([
    #("id", json.string(info.id)),
    #("content", json.string(info.content)),
    #("from_node", json.string(info.from_node)),
    #("ttl_ms", json.int(info.ttl_ms)),
    #("created_at", json.int(info.created_at)),
  ])
}

fn msg_decoder() -> decode.Decoder(#(String, Int)) {
  use content <- decode.field("content", decode.string)
  use ttl <- decode.field("ttl", decode.int)
  decode.success(#(content, ttl))
}

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
<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
<title>Spectre-Link Dashboard</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { background: #0a0a1a; color: #e0e0ff; font-family: 'Courier New', monospace; overflow: hidden; }
  #canvas { position: fixed; top: 0; left: 0; z-index: 0; }
  #ui { position: fixed; top: 0; left: 0; width: 100%; height: 100%; z-index: 1; display: flex; pointer-events: none; }
  #sidebar { width: 260px; background: rgba(10,10,30,0.85); border-right: 1px solid #2a2a6a; padding: 20px; pointer-events: all; overflow-y: auto; }
  #main { flex: 1; display: flex; flex-direction: column; padding: 20px; }
  h1 { color: #8080ff; font-size: 1.3em; margin-bottom: 16px; text-shadow: 0 0 10px #4040ff; }
  h2 { color: #6060cc; font-size: 1em; margin-bottom: 10px; }
  .node-item { background: rgba(40,40,100,0.5); border: 1px solid #3030a0; padding: 8px 12px; margin-bottom: 6px; border-radius: 4px; font-size: 0.75em; word-break: break-all; }
  .node-self { border-color: #8080ff; color: #b0b0ff; }
  #form-area { position: fixed; bottom: 20px; left: 280px; right: 20px; background: rgba(10,10,30,0.9); border: 1px solid #3030a0; border-radius: 8px; padding: 20px; pointer-events: all; }
  .form-row { display: flex; gap: 12px; align-items: center; flex-wrap: wrap; }
  input[type=text] { flex: 1; min-width: 200px; background: rgba(20,20,60,0.8); border: 1px solid #4040a0; color: #e0e0ff; padding: 10px; border-radius: 4px; font-family: inherit; font-size: 0.9em; }
  input[type=text]::placeholder { color: #5050a0; }
  input[type=range] { width: 160px; accent-color: #8080ff; }
  .ttl-label { color: #8080cc; font-size: 0.8em; min-width: 90px; }
  button { background: linear-gradient(135deg, #4040c0, #8040ff); border: none; color: #fff; padding: 10px 20px; border-radius: 4px; cursor: pointer; font-family: inherit; font-size: 0.9em; transition: opacity 0.2s; }
  button:hover { opacity: 0.85; }
  #status { font-size: 0.75em; color: #6060cc; margin-top: 8px; }
  #msg-count { color: #8080ff; font-size: 0.8em; margin-top: 4px; }
</style>
</head>
<body>
<canvas id=\"canvas\"></canvas>
<div id=\"ui\">
  <div id=\"sidebar\">
    <h1>👻 Spectre-Link</h1>
    <h2>Connected Nodes</h2>
    <div id=\"nodes-list\"><div class=\"node-item\">Loading...</div></div>
    <div id=\"msg-count\"></div>
  </div>
  <div id=\"main\"></div>
</div>
<div id=\"form-area\">
  <div class=\"form-row\">
    <input type=\"text\" id=\"content-input\" placeholder=\"Enter ephemeral message...\" maxlength=\"200\">
    <label class=\"ttl-label\">TTL: <span id=\"ttl-display\">30s</span></label>
    <input type=\"range\" id=\"ttl-input\" min=\"3000\" max=\"120000\" step=\"1000\" value=\"30000\">
    <button onclick=\"sendMessage()\">Send 👻</button>
  </div>
  <div id=\"status\"></div>
</div>
<script>
const canvas = document.getElementById('canvas');
const ctx = canvas.getContext('2d');

let particles = [];
let width, height;

function resize() {
  width = canvas.width = window.innerWidth;
  height = canvas.height = window.innerHeight;
}
resize();
window.addEventListener('resize', resize);

class MessageNode {
  constructor(msg) {
    this.id = msg.id;
    this.content = msg.content;
    this.ttl_ms = msg.ttl_ms;
    this.created_at = msg.created_at;
    this.x = Math.random() * (width - 320) + 270;
    this.y = Math.random() * (height - 200) + 20;
    this.vx = (Math.random() - 0.5) * 1.2;
    this.vy = (Math.random() - 0.5) * 1.2;
    this.r = 38 + Math.random() * 20;
    this.hue = Math.floor(Math.random() * 60) + 200;
    this.phase = Math.random() * Math.PI * 2;
  }

  remainingFraction() {
    const elapsed = Date.now() - this.created_at;
    return Math.max(0, 1 - elapsed / this.ttl_ms);
  }

  update() {
    this.x += this.vx;
    this.y += this.vy;
    if (this.x - this.r < 270) { this.x = 270 + this.r; this.vx = Math.abs(this.vx); }
    if (this.x + this.r > width - 10) { this.x = width - 10 - this.r; this.vx = -Math.abs(this.vx); }
    if (this.y - this.r < 10) { this.y = 10 + this.r; this.vy = Math.abs(this.vy); }
    if (this.y + this.r > height - 180) { this.y = height - 180 - this.r; this.vy = -Math.abs(this.vy); }
    this.phase += 0.03;
  }

  draw(ctx, now) {
    const frac = this.remainingFraction();
    const pulse = 0.7 + 0.3 * Math.sin(this.phase);
    const alpha = frac * 0.9;

    ctx.save();
    ctx.globalAlpha = alpha;

    const grad = ctx.createRadialGradient(this.x, this.y, this.r * 0.2, this.x, this.y, this.r * 1.5);
    grad.addColorStop(0, `hsla(${this.hue}, 80%, 70%, ${0.4 * pulse})`);
    grad.addColorStop(1, 'transparent');
    ctx.fillStyle = grad;
    ctx.beginPath();
    ctx.arc(this.x, this.y, this.r * 1.5, 0, Math.PI * 2);
    ctx.fill();

    ctx.beginPath();
    ctx.arc(this.x, this.y, this.r, 0, Math.PI * 2);
    ctx.fillStyle = `hsla(${this.hue}, 60%, 15%, 0.85)`;
    ctx.fill();
    ctx.strokeStyle = `hsla(${this.hue}, 80%, 60%, ${0.8 * pulse})`;
    ctx.lineWidth = 2;
    ctx.stroke();

    ctx.fillStyle = `hsla(${this.hue}, 90%, 80%, 1)`;
    ctx.font = 'bold 10px Courier New';
    ctx.textAlign = 'center';
    const short = this.content.length > 14 ? this.content.slice(0, 14) + '…' : this.content;
    ctx.fillText(short, this.x, this.y - 6);

    const secsLeft = Math.ceil(this.ttl_ms * frac / 1000);
    ctx.fillStyle = frac < 0.25 ? '#ff6060' : `hsla(${this.hue}, 70%, 65%, 1)`;
    ctx.font = '9px Courier New';
    ctx.fillText('⏱ ' + secsLeft + 's', this.x, this.y + 10);

    ctx.restore();
  }
}

let nodes = {};

function updateNodes(msgs) {
  const newIds = new Set(msgs.map(m => m.id));
  // remove gone
  for (const id of Object.keys(nodes)) {
    if (!newIds.has(id)) delete nodes[id];
  }
  // add new
  for (const m of msgs) {
    if (!nodes[m.id]) nodes[m.id] = new MessageNode(m);
  }
}

function animate() {
  requestAnimationFrame(animate);
  ctx.clearRect(0, 0, width, height);

  // background grid
  ctx.strokeStyle = 'rgba(40,40,120,0.15)';
  ctx.lineWidth = 1;
  for (let x = 0; x < width; x += 60) { ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, height); ctx.stroke(); }
  for (let y = 0; y < height; y += 60) { ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke(); }

  const now = Date.now();
  for (const node of Object.values(nodes)) {
    node.update();
    node.draw(ctx, now);
  }
}
animate();

async function refresh() {
  try {
    const [msgRes, nodeRes] = await Promise.all([
      fetch('/api/messages'),
      fetch('/api/nodes')
    ]);
    const msgs = await msgRes.json();
    const nodeList = await nodeRes.json();

    updateNodes(msgs);

    const nl = document.getElementById('nodes-list');
    nl.innerHTML = '';
    const self = nodeList[0];
    for (const n of nodeList) {
      const d = document.createElement('div');
      d.className = 'node-item' + (n === self ? ' node-self' : '');
      d.textContent = (n === self ? '★ ' : '○ ') + n;
      nl.appendChild(d);
    }

    document.getElementById('msg-count').textContent =
      msgs.length + ' active message' + (msgs.length !== 1 ? 's' : '');
  } catch(e) { }
}

refresh();
setInterval(refresh, 2000);

document.getElementById('ttl-input').addEventListener('input', function() {
  const v = parseInt(this.value);
  document.getElementById('ttl-display').textContent = (v / 1000) + 's';
});

async function sendMessage() {
  const content = document.getElementById('content-input').value.trim();
  if (!content) { setStatus('Enter a message first', true); return; }
  const ttl = parseInt(document.getElementById('ttl-input').value);
  setStatus('Sending…', false);
  try {
    const res = await fetch('/api/messages', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ content, ttl })
    });
    const data = await res.json();
    if (res.ok) {
      setStatus('✓ Message sent: ' + data.id, false);
      document.getElementById('content-input').value = '';
      refresh();
    } else {
      setStatus('Error: ' + (data.error || 'unknown'), true);
    }
  } catch(e) { setStatus('Network error', true); }
}

document.getElementById('content-input').addEventListener('keydown', function(e) {
  if (e.key === 'Enter') sendMessage();
});

function setStatus(msg, isError) {
  const el = document.getElementById('status');
  el.textContent = msg;
  el.style.color = isError ? '#ff6060' : '#8080ff';
}
</script>
</body>
</html>"
}
