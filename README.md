# Spectre-Link 👻

A distributed ephemeral messaging system built on the BEAM (Erlang Virtual Machine), written in Gleam.

## What is Spectre-Link?

Each message is a **separate OTP Actor process** with a TTL (time-to-live). When the TTL expires, the process dies and the data vanishes — no database, no persistence, no trace. Multiple instances discover each other via Distributed Erlang.

```
  Instance A (port 4000)          Instance B (port 4001)
  ┌─────────────────────┐         ┌─────────────────────┐
  │  NodeRegistry       │◄───────►│  NodeRegistry       │
  │  ┌─────────────┐    │         │  ┌─────────────┐    │
  │  │ Msg "Hello" │    │         │  │ Msg "World" │    │
  │  │ TTL: 30s    │    │         │  │ TTL: 60s    │    │
  │  └─────────────┘    │         │  └─────────────┘    │
  │  ┌─────────────┐    │         └─────────────────────┘
  │  │ Msg "Bye"   │    │
  │  │ TTL: 5s ✗  │    │   ← Process dies, data gone
  │  └─────────────┘    │
  └─────────────────────┘
```

## Erlang Hot-Swapping Architecture

BEAM enables **zero-downtime code upgrades** via OTP's `sys` module callbacks.

### How it works

1. **`code_change/3` callback** — when a new module version is loaded, OTP calls `code_change(OldVsn, State, Extra)` on the running actor. You transform the old state to the new state format.

2. **Two-version module coexistence** — BEAM keeps two versions of each module in memory simultaneously (old + new). Processes already executing in the old module continue safely; new calls start using the new code.

3. **Gleam actors via `gleam_otp`** — Gleam's Actor abstraction sits on top of Erlang's `gen_server`. The `on_message` handler gets called by the OTP framework, which means all OTP system messages (including code upgrade signals) are handled transparently.

4. **Rolling upgrades** — In a cluster, you can upgrade nodes one at a time. Distributed Erlang keeps them talking while you upgrade.

```erlang
%% Erlang gen_server style (what gleam_otp wraps):
code_change(OldVsn, OldState, _Extra) ->
    NewState = migrate_state(OldState),
    {ok, NewState}.
```

## Compilation: Gleam → BEAM Bytecode

```bash
gleam build
```

This:
1. Parses `.gleam` source files
2. Type-checks everything
3. Code-generates Erlang (`.erl` files in `build/dev/erlang/spectre_link/`)
4. Compiles Erlang → `.beam` bytecode files
5. Bundles into an OTP application

The generated `.beam` files live in:
```
build/dev/erlang/spectre_link/ebin/
```

## Multi-Node Setup with Distributed Erlang

### Connecting nodes with `net_adm:ping`

```erlang
%% In Erlang shell on node A:
(spectre_link_4000@localhost)> net_adm:ping('spectre_link_4001@localhost').
pong  %% ← nodes are now connected
```

Or via `erl_connect` from the OS shell:
```bash
erl -name admin@localhost -setcookie secret -eval \
  "net_adm:ping('spectre_link_4000@localhost'), init:stop()."
```

### EPMD (Erlang Port Mapper Daemon)

Distributed Erlang uses `epmd` to find processes. It starts automatically when a node goes distributed. Check active nodes:
```bash
epmd -names
```

## Running

### Single node
```bash
./run.sh
# Opens dashboard at http://localhost:4000
```

### Two nodes (multi-node mesh)
```bash
# Terminal 1
./run.sh

# Terminal 2
./run_peer.sh
# Auto-discovers and connects to port 4000 node
# Opens dashboard at http://localhost:4001
```

## API

| Method | Path | Description |
|--------|------|-------------|
| GET | `/` | Dashboard |
| GET | `/api/messages` | List live messages |
| POST | `/api/messages` | Create message `{"content":"...", "ttl": 30000}` |
| GET | `/api/nodes` | List connected Erlang nodes |

## Architecture

```
spectre_link (main)
├── port_scanner        - FFI: find free TCP port
├── node_registry       - OTP Actor: tracks message actors
│   └── message_actor   - OTP Actor: one per message, dies on TTL
├── mesh_discovery      - FFI: distributed Erlang node management
└── web_server          - mist HTTP server with live dashboard
```

## Dependencies

- [Gleam](https://gleam.run) 1.16.0
- Erlang/OTP 25
- [mist](https://github.com/rawhat/mist) — pure Gleam HTTP server
- [gleam_otp](https://hexdocs.pm/gleam_otp) — OTP actors/supervisors
- [gleam_erlang](https://hexdocs.pm/gleam_erlang) — Erlang interop
- [gleam_json](https://hexdocs.pm/gleam_json) — JSON encoding/decoding
