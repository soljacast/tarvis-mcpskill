---
name: connect-device
description: Connect this client to a cloud Tarvis workspace through Tailscale, request browser-approved access, and write the MCP configuration. Use when Tarvis tools are missing, every call fails with an auth error, the plugin was just installed, or the user is setting up a new machine.
allowed-tools: Bash
---

# Connect to a Tarvis workspace

## 0. Check the existing connection

For Claude Code, check whether Tarvis is already configured:

```bash
claude mcp list 2>/dev/null | grep -i tarvis
```

If it is configured and calls work, tell the user a full client restart may be
needed for the tools to appear, then stop. Continue when no entry exists or all
Tarvis calls fail with an authorization error. A revoked or expired token needs
a fresh pairing request; replace the existing user-scoped Tarvis entry rather
than adding a duplicate.


Connect through the workspace's Tailscale address. Use the ordinary workspace
URL only to derive its `.ts` equivalent; use the `.ts` origin for every health,
discovery, pairing, browser authorization, and MCP request.

Perform pairing with the requests below rather than downloading and executing a
script. This keeps the browser authorization step visible and lets the user
approve access themselves.

## 1. Derive the private workspace address

Start by asking for the base workspace URL. It should look like
`https://war.tarvis.site`, not an app URL inside the workspace. Strip any path,
query, or fragment, then insert `.ts` immediately before `.tarvis.site`:

```text
https://war.tarvis.site -> https://war.ts.tarvis.site
```

Call that derived origin `<workspace-origin>` below. If the supplied hostname
already ends in `.ts.tarvis.site`, use it unchanged. Do not send MCP discovery
or pairing requests to the ordinary `*.tarvis.site` hostname.

## 2. Enable the workspace VPN

Assume VPN access has not been configured yet:

1. Guide the user to the workspace's settings and have them enable **VPN**.
2. Have them accept the Tailscale invitation shown there.
3. If Tailscale is not installed on the computer running the MCP client, guide
   them to install it, sign in with the invited account, and join the
   workspace's tailnet.
4. Wait for them to confirm that Tailscale shows connected. Sign-in, invitation
   acceptance, and approval stay in their browser; never ask them to paste
   account credentials into chat.

After Tailscale connects, test the private health endpoint before continuing:

```bash
curl -fsS --max-time 10 <workspace-origin>/health
```

Do not continue until the health request succeeds. The pairing request below
generates the browser URL the user needs.

## 3. Discover the MCP endpoint

Once the private health endpoint works, discover the MCP endpoint:

```bash
curl -fsS --max-time 10 <workspace-origin>/api/agent/discover
```

Use the returned `mcp_url` for `<mcp_url>` later. If it contains any other
hostname, replace only its origin with `<workspace-origin>` and preserve its
path, query, and fragment.

## 4. Ask for access

```bash
curl -fsS -X POST <workspace-origin>/api/agent/auth/request \
  -H 'Content-Type: application/json' -d '{"client_name":"claude-code"}' \
  | tee /tmp/tarvis-req.json
```

You get back `request_id` and `approve_url`; nothing is granted yet. Read the id
back out of that file for the exchange call rather than retyping it — it is
long, and a truncated one fails with a parse error that reads like a bug in the
workspace.

## 5. Open the authorization page

Turn the returned `approve_url` into the private authorization URL before
showing or opening it: preserve its path, query, and fragment, but replace its
origin with `<workspace-origin>`. For example:

```text
https://war.tarvis.site/api/agent/auth/approve?request_id=...
-> https://war.ts.tarvis.site/api/agent/auth/approve?request_id=...
```

Show the private authorization URL to the user, then open it automatically on
the computer running Tailscale. Use a local browser-control capability when one
is available; otherwise use the platform's normal URL opener:

```bash
# macOS
open '<private-approve-url>'

# Linux
xdg-open '<private-approve-url>'

# Windows
start '<private-approve-url>'
```

If opening a browser requires user approval in the current environment, request
it. If no graphical browser is available, leave the URL visible so the user can
open it themselves.

Ask the user to log in on the `.ts` authorization page, approve access, choose
the access duration and whether to allow VMs/coding agents, and give the agent
the code displayed by the page. Recommend 7 days and enabling VMs/coding agents
unless the user says otherwise. The code is single use and short lived. Login
credentials stay in the browser and must never be pasted into chat.

## 6. Exchange the code and configure the client

```bash
curl -fsS -X POST <workspace-origin>/api/agent/auth/exchange \
  -H 'Content-Type: application/json' \
  -d '{"request_id":"<request_id>","code":"<CODE>"}'
```

That returns `token`. Write it into the client without ever printing it — in
Claude Code:

```bash
claude mcp add -s user --transport http tarvis <mcp_url> \
  --header "Authorization: Bearer <token>"
```

If an expired or revoked Tarvis entry already exists, remove or update that
user-scoped entry immediately before adding the replacement. `-s user` is not
optional. Without it the server is written at `local` scope,
which binds it to whichever directory you happened to run the command in — the
workspace connection then vanishes from every other project and the next
session pairs all over again.

For any other client, put `<mcp_url>` and that same header in its MCP config.

Then confirm the workspace answers with the token:

```bash
curl -fsS -X POST <mcp_url> -H "Authorization: Bearer <token>" \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

A healthy workspace returns tens of tools. Tell the user to **fully quit and
reopen** their client — a reload does not pick up new MCP servers.

## 7. When something fails

- **the workspace does not answer** — confirm VPN is enabled in workspace
  settings, Tailscale shows connected on this computer, and the request uses
  `<workspace>.ts.tarvis.site`, not the ordinary workspace hostname.
- **the exchange rejects the code** — codes are single use and short lived. Go
  back to step 4 for a fresh request rather than reusing the id.
- **`tools/list` returns nothing** — the token did not take. Start again from
  step 4.

Stop and explain if it fails twice. Do not loop.

## What this cannot do

**Hosted web connectors cannot reach the Tarvis workspace tailnet.** The `.ts`
endpoint is for clients running on a computer that has joined the Tarvis
workspace VPN.
