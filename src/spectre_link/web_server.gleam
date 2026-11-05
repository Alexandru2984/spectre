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
    Get, [] | Head, [] -> {
      let res = serve_asset("index.html", "text/html; charset=utf-8")
      case request.get_query(req) |> result.unwrap([]) |> list.is_empty() {
        True -> res
        False -> response.set_header(res, "x-robots-tag", "noindex, nofollow")
      }
    }
    Get, ["about"] | Head, ["about"] ->
      serve_asset("about.html", "text/html; charset=utf-8")
    Get, ["privacy"] | Head, ["privacy"] ->
      serve_asset("privacy.html", "text/html; charset=utf-8")
    Get, ["robots.txt"] | Head, ["robots.txt"] ->
      serve_asset("robots.txt", "text/plain; charset=utf-8")
    Get, ["sitemap.xml"] | Head, ["sitemap.xml"] ->
      serve_asset("sitemap.xml", "application/xml; charset=utf-8")
    Get, ["favicon.ico"] | Head, ["favicon.ico"] ->
      serve_asset("favicon.svg", "image/svg+xml")
    Get, ["static", "favicon.svg"] | Head, ["static", "favicon.svg"] ->
      serve_asset("favicon.svg", "image/svg+xml")
    Get, ["static", "social.png"] | Head, ["static", "social.png"] ->
      serve_asset("social.png", "image/png")
    Get, ["static", "dashboard.js"] | Head, ["static", "dashboard.js"] ->
      serve_asset("dashboard.js", "text/javascript; charset=utf-8")
    Get, ["static", "dashboard.css"] | Head, ["static", "dashboard.css"] ->
      serve_asset("dashboard.css", "text/css; charset=utf-8")
    Get, ["static", "icons.svg"] | Head, ["static", "icons.svg"] ->
      serve_asset("icons.svg", "image/svg+xml")
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
    "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'",
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

fn serve_asset(name: String, content_type: String) -> Response(ResponseData) {
  case read_asset(name) {
    Ok(body) ->
      response.new(200)
      |> response.set_header("content-type", content_type)
      |> response.set_header("cache-control", "public, no-cache, no-transform")
      |> response.set_body(mist.Bytes(bytes_tree.from_bit_array(body)))
    Error(_) -> error_response(503, "This page is temporarily unavailable.")
  }
}

@external(erlang, "spectre_link_ffi", "read_asset")
fn read_asset(name: String) -> Result(BitArray, Nil)

fn error_response(status: Int, error: String) -> Response(ResponseData) {
  json_resp(status, j.obj([#("error", j.str(error))]))
  |> response.set_header("connection", "close")
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
