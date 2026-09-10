---
name: find-device
description: Resolve a Tarvis cloud workspace URL to its private Tailscale address and diagnose reachability. Use when the user needs the MCP workspace address, a saved Tarvis URL stopped responding, or setup needs to confirm VPN access before pairing.
allowed-tools: Bash
---

# Find the private Tarvis workspace address

Tarvis MCP is available only through the workspace's Tailscale address. Use the
ordinary workspace hostname only to derive the private `.ts` origin.

## 1. Get the workspace URL

Ask the user for the base workspace URL. It should have one workspace label,
for example `https://war.tarvis.site`, rather than an app URL such as
`https://immich.war.tarvis.site`. Strip any path, query, or fragment.

Insert `.ts` immediately before `.tarvis.site`:

```text
https://war.tarvis.site -> https://war.ts.tarvis.site
```

If the supplied hostname already ends in `.ts.tarvis.site`, keep it unchanged.
Call the result `<workspace-origin>`.

## 2. Confirm VPN access

If Tailscale is not connected, guide the user to enable **VPN** in their Tarvis
workspace settings, accept the Tailscale invitation, install Tailscale when
needed, and sign in with the invited account. Credentials and invitation
approval stay in the browser.

Test reachability only after Tailscale shows connected:

```bash
curl -fsS --max-time 10 <workspace-origin>/health
```

A successful health response confirms the private origin. If it fails, verify
that the hostname contains `.ts.tarvis.site`, the workspace VPN is enabled, and
this computer is connected to the invited tailnet. Stop after two failed checks
and explain which prerequisite is still missing.

## 3. Read the advertised MCP URL

When pairing or MCP configuration needs the endpoint, call:

```bash
curl -fsS --max-time 10 <workspace-origin>/api/agent/discover
```

Use its `mcp_url`. If the response contains the ordinary workspace origin,
replace only that origin with `<workspace-origin>` and preserve the path, query,
and fragment. Hand off to the connection skill for browser approval and token
exchange.
