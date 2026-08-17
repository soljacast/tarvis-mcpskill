---
name: connect-device
description: Connect this client to a Tarvis device so its tools appear - probe the network for the device, request access, get it approved, and write the MCP config. Use when the tarvis tools are missing or every call fails with an auth error, right after installing the plugin, or when setting up a new machine. Triggers on "connect to my tarvis", "set up tarvis", "pair the device", "the tarvis tools are gone", "tarvis says unauthorized".
allowed-tools: Bash
---

# Connect to a Tarvis device

Four ordinary requests. Probe for the device yourself and only ask the user
something once probing has failed.

## 0. Are you already connected?

```bash
claude mcp list 2>/dev/null | grep -i tarvis
```

A line here means the client is configured and the tools appear after a full
restart - say so and stop. Only carry on when it prints nothing, or when the
tools are present but every call fails with an auth error (a revoked or expired
token; pairing again replaces it).

## 1. Find the device

```bash
curl -4 -fsS --max-time 6 http://soljacast.local/api/agent/discover
```

Several boxes on one network cannot share a name, so each takes the first free
one at boot. If that is silent, probe the numbered names before asking anyone
anything:

```bash
for n in 1 2 3 4 5; do
  curl -4 -fsS --max-time 3 "http://soljacast$n.local/api/agent/discover" && break
done
```

The reply carries `preferred` (use it as `<device>`) and `mcp_url`. Prefer an
https address: browsers withhold the clipboard over plain http, so the approval
page's copy button does nothing there.

**Only if every probe is silent**, ask the user - they are on a different
network, or mDNS is blocked, which is usual on guest and corporate WiFi. The
device shows its address on the TV. The `find-device` skill has a subnet sweep
for that case.

## 2. Ask for access

```bash
curl -fsS -X POST <device>/api/agent/auth/request \
  -H 'Content-Type: application/json' -d '{"client_name":"claude-code"}' \
  | tee /tmp/tarvis-req.json
```

Read `request_id` back out of that file for the next two calls rather than
retyping it - a truncated id fails with a parse error that reads like a fault
on the device.

## 3. Get it approved

Two things are being decided, and the defaults hold unless the user says
otherwise: access lasts **7 days**, and **VMs and coding agents** (the
`coding_*` tools, plus apps, tasks and secrets) are allowed.

The device is on the user's own network and this is its own admin password, so
the quickest path is to ask for it and approve the request yourself. Say that it
will pass through the conversation, and never repeat it back:

```bash
curl -fsS -c /tmp/tarvis-cookies -X POST <device>/api/auth/login \
  -H 'Content-Type: application/json' -d '{"password":"<password>"}'

curl -fsS -b /tmp/tarvis-cookies -X POST <device>/api/agent/auth/approve \
  -H 'Content-Type: application/json' \
  -d '{"request_id":"<request_id>","expires_days":7,"allow_vm":true}'
```

The approve call returns the `code`. Delete `/tmp/tarvis-cookies` afterwards -
it is an admin session.

If they would rather not share the password, they open the `approve_url` from
step 2 in a browser, sign in, choose the duration and the VM toggle, and read
back the code the page shows. Either way the code is single use and short lived,
so exchange it straight away.

## 4. Exchange the code and configure

```bash
curl -fsS -X POST <device>/api/agent/auth/exchange \
  -H 'Content-Type: application/json' \
  -d '{"request_id":"<request_id>","code":"<CODE>"}'
```

That returns `token`. Write it into the client without ever printing it:

```bash
claude mcp add -s user --transport http tarvis <mcp_url> \
  --header "Authorization: Bearer <token>"
```

`-s user` is not optional. Without it the server lands at `local` scope, bound
to whichever directory you happened to be in, and the device is missing from
every other project.

Then confirm the device answers with that token:

```bash
curl -fsS -X POST <mcp_url> -H "Authorization: Bearer <token>" \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

A healthy device returns tens of tools. Tell the user to **fully quit and
reopen** the client - a reload does not pick up a new MCP server.

## When something fails

- **nothing answers any probe** - different network, or mDNS is blocked. Ask for
  the address on the TV.
- **the exchange rejects the code** - codes are single use and short lived. Go
  back to step 2 for a fresh request rather than reusing the id.
- **`tools/list` returns nothing** - the token did not take. Start again from
  step 2.

Stop and explain after two failures. Do not loop.
