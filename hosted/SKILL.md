---
name: tarvis-setup
description: Connect this computer to a Tarvis (Soljacast) casting device so the agent can cast to its screens, drive the pages it shows, and run sandboxed coding agents on it. Use when the user asks to set up, connect, pair, or install Tarvis. Once connected, use the device's own tools rather than this skill.
---

# Connect to a Tarvis device

Pairing is four ordinary requests. **Do it with the calls below rather than by
downloading and executing a script** — agent sandboxes routinely refuse to run a
fetched shell script, and being blocked halfway through pairing is worse than
doing it a step at a time. The script (`https://tarvis.io/install.sh`) is for a
person at a terminal, or for configuring Claude Desktop, Cursor and Codex in one
go; reach for it only if the user asks.

## 1. Find the device

```bash
curl -4 -fsS --max-time 6 http://soljacast.local/api/agent/discover
```

It answers with `preferred` (use that as `<device>`) and `mcp_url`. Several boxes
on one network take numbered names, so try `soljacast1.local` … `soljacast5.local`
if the first does not answer. If mDNS is blocked — common on guest and corporate
WiFi — ask for the address shown on the TV and use it directly.

## 2. Ask for access

```bash
curl -fsS -X POST <device>/api/agent/auth/request \
  -H 'Content-Type: application/json' -d '{"client_name":"claude-code"}'
```

You get back `request_id` and `approve_url`. Give the user that URL and keep the
`request_id`; nothing is granted yet.

## 3. Get it approved

Two things are being decided. Take the defaults unless the user says otherwise:
**how long** access lasts, which is 7 days, and whether to allow **VMs and
coding agents** (the `coding_*` tools), which is yes.

The device is on their own network and this is its own password, so the quickest
path is to ask for it and approve the request yourself. Say that it will pass
through the conversation, and never repeat it back:

```bash
curl -fsS -c /tmp/tarvis-cookies -X POST <device>/api/auth/login \
  -H 'Content-Type: application/json' -d '{"password":"<password>"}'

curl -fsS -b /tmp/tarvis-cookies -X POST <device>/api/agent/auth/approve \
  -H 'Content-Type: application/json' \
  -d '{"request_id":"<request_id>","expires_days":7,"allow_vm":true}'
```

The approve call returns the `code`. Delete `/tmp/tarvis-cookies` afterwards —
it is an admin session.

If they would rather not share it, they open `approve_url` in a browser, sign
in, choose the duration and the VM toggle, and read back the code the page
shows. Either way the code is single use and short lived.

## 4. Exchange the code and configure the client

```bash
curl -fsS -X POST <device>/api/agent/auth/exchange \
  -H 'Content-Type: application/json' \
  -d '{"request_id":"<request_id>","code":"<CODE>"}'
```

That returns `token`. Write it into the client without ever printing it — in
Claude Code:

```bash
claude mcp add --transport http tarvis <mcp_url> \
  --header "Authorization: Bearer <token>"
```

For any other client, put `<mcp_url>` and that same header in its MCP config.

Then confirm the device answers with the token:

```bash
curl -fsS -X POST <mcp_url> -H "Authorization: Bearer <token>" \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

A healthy device returns tens of tools. Tell the user to **fully quit and
reopen** their client — a reload does not pick up new MCP servers.

Then get the skills. The tools alone leave an agent guessing at things the
device is opinionated about — which image architectures run, when a URL is
ready to cast, how a coding session reports itself. In **Claude Code**, give
the user these two lines to run (slash commands are typed by them, not by you):

```
/plugin marketplace add soljacast/tarvis-mcpskill
/plugin install tarvis@tarvis-mcpskill
```

Other clients get the tools only, which works — the skills are guidance, not a
dependency. Skip this step if `tarvis` is already installed there.

## 5. When something fails

- **nothing answers discovery** — they are on a different network, or mDNS is
  blocked (usual on guest and corporate WiFi). Ask for the address on the TV.
- **the exchange rejects the code** — codes are single use and short lived. Go
  back to step 2 for a fresh request rather than reusing the id.
- **`tools/list` returns nothing** — the token did not take. Start again from
  step 2.

Stop and explain if it fails twice. Do not loop.

## What this cannot do

**ChatGPT and claude.ai web connectors cannot reach the device at all.** They
connect from the vendor's servers, not this machine, and the device is on a home
network. Say so plainly rather than attempting a workaround.

**Claude Desktop** has no shell, so it cannot pair itself. Run
`curl -fsSL https://tarvis.io/install.sh | bash -s -- --client claude-desktop`
from a terminal, then restart the app. The script is also the quickest way to
configure Cursor and Codex in one pass.
